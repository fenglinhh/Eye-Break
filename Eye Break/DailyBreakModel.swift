//
//  DailyBreakModel.swift
//  Eye Break
//
//  职责：应用中唯一的 ViewModel，通过 @MainActor ObservableObject 桥接
//  纯状态机 BreakTimerEngine 与 SwiftUI 视图层。
//  持有引擎实例和所有服务实例，通过 1 秒 Timer 驱动 engine.tick() → syncFromEngine() 循环。
//  依赖：BreakTimerEngine, DailyBreakStore, RestOverlayController, PreBreakReminderController,
//        SystemActivityMonitor, ProjectionMonitor, LaunchAtLoginService
//  被使用：MenuBarView, SettingsView（通过 @ObservedObject / @EnvironmentObject）
//

import Foundation
import Combine
import SwiftUI

/// 唯一 ViewModel（@MainActor 限定）— 所有视图只与本类交互。
///
/// 逻辑：
/// 1. 创建时从 store 加载配置和统计，初始化 engine
/// 2. start() 后启动 1 秒 Timer，每秒 tick() → engine.tick() → syncFromEngine()
/// 3. syncFromEngine() 将 engine 内部状态同步到 @Published 属性驱动视图刷新
/// 4. 负责消费 engine 的"一次性标识"（toast/overlay），调度对应服务
@MainActor
final class DailyBreakModel: ObservableObject {
    // MARK: - 发布属性（驱动 SwiftUI 视图刷新）

    /// 当前配置（写时自动持久化、同步 engine、更新登录自启）
    @Published var settings: BreakSettings {
        didSet {
            store.saveSettings(settings)
            engine.updateSettings(settings)
            launchAtLogin.apply(enabled: settings.launchAtLogin)
        }
    }
    /// 当前阶段（只读，由 syncFromEngine 更新）
    @Published private(set) var phase: BreakPhase = .inactive
    /// 当前阶段剩余秒数
    @Published private(set) var remainingSeconds = 0
    /// 今日短休息次数
    @Published private(set) var todayShortBreaks = 0
    /// 今日长休息次数
    @Published private(set) var todayLongBreaks = 0
    /// Toast 浮层消息（显示 3 秒后自动清除）
    @Published var toastMessage: String?
    /// 当前是否检测到投影/外接显示状态
    @Published private(set) var isProjecting = false

    // MARK: - 服务实例

    /// 持久化存储（UserDefaults JSON）
    private let store: DailyBreakStore
    /// 全屏休息蒙层控制器（每个屏幕一个 NSWindow）
    private let overlayController: RestOverlayController
    /// 休息前 30 秒的右下角轻提示窗口
    private let preBreakReminderController: PreBreakReminderController
    /// 系统事件监听（睡眠/锁屏/会话切换）
    private let systemMonitor: SystemActivityMonitor
    /// 投影/外接显示状态监听
    private let projectionMonitor: ProjectionMonitor
    /// 登录自启管理
    private let launchAtLogin: LaunchAtLoginService

    // MARK: - 内部状态

    /// 核心状态机引擎（纯值类型，无 UI 依赖）
    private var engine: BreakTimerEngine
    /// 驱动引擎的 1 秒重复定时器
    private var tickTimer: Timer?
    /// Toast 自动关闭定时器（3 秒）
    private var toastTimer: Timer?
    /// 缓存的最新健康建议（每次休息会话只生成一次）
    private var currentAdvice: String?
    /// 标记 start() 是否已被调用过（防止重复启动）
    private var hasStarted = false
    /// 标记 overlay 当前是否已显示（用于决定调用 show/update/close）
    private var isOverlayVisible = false
    /// 最近一次已持久化的统计快照；统计未变化时不重复写 UserDefaults。
    private var lastPersistedStats: BreakStats?
    /// 标记当前 systemAway 是否由投影检测触发，避免误恢复锁屏/睡眠暂停。
    private var isProjectionPauseActive = false

    // MARK: - 初始化

    /// 便利构造函数（使用默认服务实例）。
    convenience init() {
        self.init(
            store: DailyBreakStore(),
            overlayController: RestOverlayController(),
            preBreakReminderController: PreBreakReminderController(),
            systemMonitor: SystemActivityMonitor(),
            projectionMonitor: ProjectionMonitor(),
            launchAtLogin: LaunchAtLoginService()
        )
    }

    /// 完整构造函数（支持依赖注入，便于测试）。
    ///
    /// 逻辑：
    /// 1. 从 store 加载配置
    /// 2. 用配置创建 engine
    /// 3. 从 store 恢复统计
    /// 4. 绑定服务回调
    /// 5. 执行首次 syncFromEngine 初始化发布属性
    init(
        store: DailyBreakStore,
        overlayController: RestOverlayController,
        preBreakReminderController: PreBreakReminderController,
        systemMonitor: SystemActivityMonitor,
        projectionMonitor: ProjectionMonitor,
        launchAtLogin: LaunchAtLoginService
    ) {
        self.store = store
        self.overlayController = overlayController
        self.preBreakReminderController = preBreakReminderController
        self.systemMonitor = systemMonitor
        self.projectionMonitor = projectionMonitor
        self.launchAtLogin = launchAtLogin
        let loadedSettings = store.loadSettings()
        let loadedStats = store.loadStats()
        self.settings = loadedSettings
        self.engine = BreakTimerEngine(settings: loadedSettings)
        self.engine.restoreStats(loadedStats)
        self.lastPersistedStats = loadedStats
        bindServices()
        syncFromEngine()
    }

    /// 释放模型时清理 RunLoop Timer，避免测试或未来多实例场景中空转。
    deinit {
        tickTimer?.invalidate()
        toastTimer?.invalidate()
    }

    // MARK: - 启动

    /// 启动模型（应用启动时调用一次）。
    ///
    /// 逻辑：
    /// 1. 应用登录自启设置
    /// 2. 启动系统事件监听
    /// 3. 调用 engine.startIfAllowed() 根据当前时间决定是否开始周期
    /// 4. 启动投影检测，投影中会冻结当前倒计时
    /// 5. 创建 1 秒重复 Timer，驱动 engine.tick() + syncFromEngine()
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        launchAtLogin.apply(enabled: settings.launchAtLogin)
        systemMonitor.start()
        engine.startIfAllowed()
        syncFromEngine()
        projectionMonitor.start()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    // MARK: - 用户操作（均遵循 engine.操作() → syncFromEngine() 模式）

    /// 暂停当前阶段（委托给 engine → 同步）。
    func pause() {
        engine.pause()
        syncFromEngine()
    }

    /// 从暂停恢复（委托给 engine → 同步）。
    func resume() {
        engine.resume()
        syncFromEngine()
    }

    /// 立即开始休息（委托给 engine → 同步）。
    func startBreakNow() {
        engine.startBreakNow()
        syncFromEngine()
    }

    /// 跳过本次休息（委托给 engine → 同步）。
    func skipBreak() {
        engine.skipBreak()
        syncFromEngine()
    }

    /// 重置工作周期（委托给 engine → 同步）。
    func resetWorkCycle() {
        engine.resetWorkCycle()
        syncFromEngine()
    }

    // MARK: - 计算属性（供视图直接绑定）

    /// 详细状态文案（用于菜单栏弹出窗口的详情显示）。
    var statusLine: String {
        switch phase {
        case .inactive:
            if let next = engine.nextActiveStart {
                return "已暂停，\(next.formatted(date: .omitted, time: .shortened)) 开始"
            }
            return "未在执行时间"
        case .working:
            return "距离休息还有 \(formatDuration(remainingSeconds))"
        case .preBreak:
            return "\(remainingSeconds) 秒后休息"
        case .resting(let kind):
            return kind == .short ? "短休息中" : "长休息中"
        case .paused:
            return "已暂停 \(formatDuration(engine.totalPausedSeconds)) · 剩余 \(formatDuration(remainingSeconds))"
        case .systemAway:
            return isProjecting ? "投影中，已暂停；退出投影后自动继续" : "锁屏或睡眠暂停中"
        case .postponed:
            return "已延后 · \(formatDuration(remainingSeconds)) 后提醒"
        }
    }

    /// 极简短标题（用于菜单栏图标旁的文字）。
    var menuBarTitle: String {
        switch phase {
        case .inactive:
            return "休息"
        case .paused:
            return "暂停 \(formatDuration(engine.totalPausedSeconds))"
        case .preBreak:
            return "\(remainingSeconds)秒"
        case .resting:
            return "休息 \(formatDuration(remainingSeconds))"
        default:
            return formatDuration(remainingSeconds)
        }
    }

    /// 是否显示屏幕右下角临近休息提示。
    ///
    /// 逻辑：
    /// 1. 只在 preBreak 阶段显示，避免工作早期持续占用屏幕空间
    /// 2. 剩余时间限定在 1...30 秒，休息真正开始、暂停或非活跃时自动消失
    /// 3. 不受 menuBarCountdownEnabled 影响；这是临近休息的强提示，不是普通菜单栏倒计时
    var shouldShowPreBreakScreenReminder: Bool {
        phase == .preBreak && (1...30).contains(remainingSeconds)
    }

    /// 下一次休息类型提示（仅 breakCycleEnabled 时显示）。
    var nextBreakLine: String? {
        guard settings.breakCycleEnabled else { return nil }
        switch engine.upcomingBreakKind {
        case .short:
            return "下一次：短休息"
        case .long:
            return "下一次：长休息"
        }
    }

    /// 是否允许重置工作周期（仅在工作或预提醒阶段可重置）。
    var canResetWorkCycle: Bool {
        switch phase {
        case .working, .preBreak, .postponed:
            return true
        case .inactive, .resting, .paused, .systemAway:
            return false
        }
    }

    /// 是否允许手动暂停当前状态。
    var canPause: Bool {
        switch phase {
        case .working, .preBreak, .resting, .postponed:
            return true
        case .inactive, .paused, .systemAway:
            return false
        }
    }

    // MARK: - 服务回调绑定

    /// 绑定 overlay 和系统事件监听的回调。
    ///
    /// 逻辑：
    /// 1. overlayController.onSkip → 用户在休息蒙层上点击跳过
    /// 2. systemMonitor.onAway → 锁屏/睡眠/会话切换（调用 engine.systemWillSleepOrLock）
    /// 3. systemMonitor.onReturn → 唤醒/解锁/会话恢复（调用 engine.systemDidWakeOrUnlock）
    private func bindServices() {
        overlayController.onSkip = { [weak self] in
            Task { @MainActor in self?.skipBreak() }
        }
        systemMonitor.onAway = { [weak self] in
            Task { @MainActor in
                self?.engine.systemWillSleepOrLock()
                self?.syncFromEngine()
            }
        }
        systemMonitor.onReturn = { [weak self] in
            Task { @MainActor in
                self?.engine.systemDidWakeOrUnlock()
                self?.syncFromEngine()
            }
        }
        projectionMonitor.onProjectionStarted = { [weak self] in
            Task { @MainActor in
                self?.handleProjectionStarted()
            }
        }
        projectionMonitor.onProjectionEnded = { [weak self] in
            Task { @MainActor in
                self?.handleProjectionEnded()
            }
        }
    }

    /// 进入投影：冻结当前倒计时，并让状态栏显示黄色状态。
    private func handleProjectionStarted() {
        isProjecting = true
        guard !isProjectionPauseActive else {
            syncFromEngine()
            return
        }
        let previousPhase = engine.phase
        engine.systemWillSleepOrLock()
        isProjectionPauseActive = previousPhase != .systemAway && engine.phase == .systemAway
        syncFromEngine()
    }

    /// 退出投影：仅恢复由投影触发的冻结，避免误恢复锁屏/睡眠暂停。
    private func handleProjectionEnded() {
        isProjecting = false
        guard isProjectionPauseActive else {
            syncFromEngine()
            return
        }
        isProjectionPauseActive = false
        engine.systemDidWakeOrUnlock()
        syncFromEngine()
    }

    // MARK: - 核心循环

    /// 每秒调用一次：驱动 engine 状态机，然后同步结果到发布属性。
    private func tick() {
        engine.tick()
        syncFromEngine()
    }

    // MARK: - 状态同步（核心方法）

    /// 将 engine 内部状态同步到 @Published 属性 + 调度副作用服务。
    ///
    /// 逻辑：
    /// 1. 复制 engine 的 phase、剩余秒数、休息计数到 @Published 属性触发 UI 刷新
    /// 2. 保存最新统计到 store
    /// 3. 消费 engine 的 preBreak 通知标识，防止一次性标识积压；不再发送系统通知
    /// 4. 消费 engine 的 toast 消息 → 如果有，显示 3 秒 toast
    /// 5. 处理 overlay 生命周期：
    ///    a. 若 phase 是 resting 且 engine 说应显示 → 调用 overlayController.show() 创建/展示蒙层
    ///    b. 若 phase 是 resting 但蒙层已显示 → 调用 overlayController.update() 更新倒计时
    ///    c. 若 phase 不是 resting → 调用 overlayController.close() 关闭蒙层
    /// 6. 缓存 isOverlayVisible 和 currentAdvice 供下一轮使用
    private func syncFromEngine() {
        phase = engine.phase
        remainingSeconds = engine.remainingSeconds
        todayShortBreaks = engine.todayShortBreaks
        todayLongBreaks = engine.todayLongBreaks
        persistStatsIfNeeded(engine.stats)

        // 仅消费 preBreak 通知标识；当前版本使用屏幕浮层提示，不再申请权限或发送系统通知。
        _ = engine.consumePreBreakNotificationFlag()

        // 消费 toast 消息（跳过/延后时生成）
        if let message = engine.consumeToast() {
            showToast(message)
        }

        // 处理休息前右下角轻提示：仅在最后 30 秒显示，休息开始或状态切换时关闭
        if shouldShowPreBreakScreenReminder {
            preBreakReminderController.showOrUpdate(seconds: remainingSeconds)
        } else {
            preBreakReminderController.close()
        }

        // 处理全屏蒙层生命周期
        if let overlayState = makeOverlayState() {
            if engine.shouldShowOverlay {
                // 首次进入休息 → 创建并展示蒙层
                overlayController.show(state: overlayState)
                engine.clearOverlayFlag()
            } else {
                // 蒙层已存在 → 仅更新倒计时和文案
                overlayController.update(state: overlayState)
            }
            isOverlayVisible = true
        } else {
            // 不在休息阶段 → 如果蒙层还开着，关闭它
            if isOverlayVisible {
                overlayController.close()
                isOverlayVisible = false
            }
            currentAdvice = nil
        }
    }

    /// 按需持久化统计数据。
    ///
    /// 逻辑：
    /// 1. engine 每秒 tick，但每日统计只在完成/跳过/跨天等事件中变化
    /// 2. 统计未变化时跳过 JSON 编码和 UserDefaults 写入，降低主线程 I/O 压力
    /// 3. 写入成功后更新本地快照，后续 tick 不再重复写同一份数据
    private func persistStatsIfNeeded(_ stats: BreakStats) {
        guard stats != lastPersistedStats else { return }
        store.saveStats(stats)
        lastPersistedStats = stats
    }

    // MARK: - Overlay 状态构造

    /// 构造 RestOverlayState（仅在 resting 阶段返回值）。
    ///
    /// 逻辑：
    /// 1. 每次休息会话只在首次调用时生成 healthTip（currentAdvice 为空时）
    /// 2. 后续调用复用缓存的 advice，确保整个休息过程显示同一条建议
    private func makeOverlayState() -> RestOverlayState? {
        guard case let .resting(kind) = engine.phase else { return nil }
        if currentAdvice == nil {
            currentAdvice = settings.healthTipsEnabled ? AdviceLibrary.randomTip(for: kind) : ""
        }
        return engine.currentOverlayState(advice: currentAdvice)
    }

    // MARK: - Toast 显示

    /// 显示 toast 消息，3 秒后自动消失。
    ///
    /// 逻辑：
    /// 1. 设置 toastMessage（触发 UI 显示）
    /// 2. 取消之前的 auto-dismiss 定时器
    /// 3. 创建新的 3 秒定时器，到期后清空 toastMessage
    private func showToast(_ message: String) {
        toastMessage = message
        toastTimer?.invalidate()
        let timer = Timer(timeInterval: 3, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.toastMessage = nil }
        }
        RunLoop.main.add(timer, forMode: .common)
        toastTimer = timer
    }
}
