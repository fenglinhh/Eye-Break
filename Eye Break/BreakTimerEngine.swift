//
//  BreakTimerEngine.swift
//  Eye Break
//
//  职责：应用核心状态机，管理休息提醒的完整生命周期（工作→预提醒→休息→工作）。
//  通过构造函数注入 now() 和 Calendar 实现与真实时钟的解耦，便于纯逻辑测试。
//  所有外部副作用（通知、UI 展示）交由调用方处理，本文件只管理状态转换。
//  依赖：BreakSettings, BreakPhase, BreakKind, AdviceLibrary (无 SwiftUI/AppKit)
//  被使用：DailyBreakModel（唯一 @MainActor 调用方）
//

import Foundation

/// 纯值类型状态机 — 管理所有阶段转换，无 UI 依赖。
///
/// 逻辑：
/// 1. 外部每秒调用 tick() 驱动状态机
/// 2. 通过 phase 枚举追踪当前阶段
/// 3. workDeadline / restDeadline 两个时间戳作为倒计时基准
/// 4. 每个 public mutating 方法对应一个操作（暂停/恢复/跳过/延后/启动休息）
/// 5. private 辅助方法处理各阶段的具体倒计时逻辑
struct BreakTimerEngine {
    // MARK: - 公开状态属性（只读）

    /// 当前阶段（inactive / working / preBreak / resting / paused / postponed / systemAway）
    private(set) var phase: BreakPhase = .inactive
    /// 当前阶段剩余秒数
    private(set) var remainingSeconds: Int = 0
    /// 今日已完成短休息次数（只统计完整完成的休息，用于菜单和持久化展示）
    private(set) var todayShortBreaks: Int = 0
    /// 今日已完成长休息次数
    private(set) var todayLongBreaks: Int = 0
    /// 连续跳过休息次数（影响 toast 文案语气）
    private(set) var consecutiveSkips: Int = 0
    /// 本次暂停累计秒数（仅 paused 状态有效）
    private(set) var totalPausedSeconds: Int = 0
    /// 是否应展示全屏休息蒙层（调用方据此调度 overlay 显示/隐藏）
    private(set) var shouldShowOverlay = false
    /// 是否应发送预提醒通知（调用方消费后清除）
    private(set) var shouldSendPreBreakNotification = false
    /// 上一条 toast 消息（跳过/延后时生成，调用方消费后清除）
    private(set) var lastToastMessage: String?
    /// 非活跃时间段结束后，下一次自动开始的时间（仅 inactive 有效）
    private(set) var nextActiveStart: Date?
    /// 当前休息类型（short / long），用于 restDeadline 和 overlay 展示
    private(set) var currentBreakKind: BreakKind = .short
    /// 历史休息触发记录（完成和跳过都会记录，用于长休息周期计算）
    private(set) var restHistory: [BreakKind] = []

    /// 用户配置（注入后可变，调用 updateSettings 同步变更）
    var settings: BreakSettings

    // MARK: - 注入依赖（测试隔离）

    /// 返回当前时间的闭包（生产环境为 Date.init，测试环境可注入 TestClock）
    private var now: () -> Date
    /// 日历实例（用于日期边界检查，如活跃时间段、工作日判断）
    private var calendar: Calendar

    // MARK: - 工作/休息倒计时基准（私有）

    /// 工作阶段倒计时终点时间戳（working / preBreak / postponed 共享）
    private var workDeadline: Date?
    /// 休息阶段倒计时终点时间戳（resting 使用）
    private var restDeadline: Date?

    // MARK: - 暂停冻结状态缓存

    /// 暂停开始的时间戳（用于计算 totalPausedSeconds）
    private var pauseStartedAt: Date?
    /// 暂停前的剩余秒数（恢复时还原）
    private var pausedRemainingSeconds: Int?
    /// 暂停前的阶段（恢复时还原）
    private var pausedPhase: BreakPhase?
    /// 暂停前的休息类型（仅在 pausedPhase 为 resting 时有意义）
    private var pausedBreakKind: BreakKind?

    // MARK: - 系统离场冻结状态缓存

    /// 系统离场前的剩余秒数（唤醒后还原）
    private var awayRemainingSeconds: Int?
    /// 系统离场前的阶段
    private var awayPhase: BreakPhase?
    /// 系统离场前的休息类型
    private var awayBreakKind: BreakKind?
    /// 离场开始时间戳（用于计算 awayDuration）
    private var awayStartedAt: Date?
    /// 标记 preBreak 通知是否已发送，防止重复（每个工作周期重置）
    private var preBreakNotificationSent = false

    // MARK: - 初始化

    /// 创建引擎实例。
    /// - 参数 now: 获取当前时间的闭包，默认 Date.init
    /// - 参数 calendar: 日历实例，默认 .current
    init(settings: BreakSettings, now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.settings = settings
        self.now = now
        self.calendar = calendar
    }

    // MARK: - 设置同步

    /// 更新配置并在必要时限制已有倒计时不超过新值。
    ///
    /// 逻辑：
    /// 1. 保存新配置到 self.settings
    /// 2. 如果当前或冻结前处于工作类阶段，将剩余时间限制为不超过新的工作时长
    /// 3. 如果当前或冻结前处于休息阶段，将剩余时间限制为不超过对应的新休息时长
    mutating func updateSettings(_ settings: BreakSettings) {
        self.settings = settings
        clampCurrentAndFrozenRemainingToSettings()
    }

    // MARK: - 持久化恢复

    /// 从持久化统计快照恢复今日数据（应用启动时调用）。
    mutating func restoreStats(_ stats: BreakStats) {
        todayShortBreaks = stats.shortBreaks
        todayLongBreaks = stats.longBreaks
        consecutiveSkips = stats.consecutiveSkips
        restHistory = stats.restHistory
    }

    /// 将当前引擎状态导出为持久化统计快照。
    var stats: BreakStats {
        BreakStats(
            dayKey: BreakStats.dayKey(for: now(), calendar: calendar),
            shortBreaks: todayShortBreaks,
            longBreaks: todayLongBreaks,
            consecutiveSkips: consecutiveSkips,
            restHistory: restHistory
        )
    }

    // MARK: - 启动入口

    /// 尝试启动工作周期（应用启动时或每日首次调用）。
    ///
    /// 逻辑：
    /// 1. 检查当前时间是否在活跃时间段内；如果不是，进入 inactive
    /// 2. 如果引擎不在 inactive 状态（已启动），退化为 tick() 更新倒计时
    /// 3. 如果是首次启动（inactive），调用 startWorkCycle 开始新工作周期
    mutating func startIfAllowed() {
        guard isActiveTime(now()) else {
            becomeInactive()
            return
        }
        guard phase == .inactive else {
            tick()
            return
        }
        startWorkCycle(duration: settings.workDurationSeconds)
    }

    // MARK: - 核心循环（每秒调用）

    /// 每秒调用的主状态机驱动。
    ///
    /// 逻辑：
    /// 1. 先检查活跃时间段，不在活跃时间段内则进入 inactive
    /// 2. 重置 shouldSendPreBreakNotification 标志（每 tick 先清空，由各阶段逻辑按需置位）
    /// 3. 根据当前 phase 分发到对应的倒计时更新方法
    ///   - working/preBreak → updateWorkCountdown()
    ///   - resting → updateRestCountdown()
    ///   - paused → updatePauseAccounting()（只累加暂停时长，不倒计时）
    ///   - postponed → updatePostponedCountdown()
    ///   - systemAway → 不做任何事（时间冻结）
    ///   - inactive → 自动开始新周期
    mutating func tick() {
        shouldSendPreBreakNotification = false

        guard isActiveTime(now()) else {
            tickOutsideActiveTime()
            return
        }

        switch phase {
        case .inactive:
            startWorkCycle(duration: settings.workDurationSeconds)
        case .working, .preBreak:
            updateWorkCountdown()
        case .resting:
            updateRestCountdown()
        case .paused:
            updatePauseAccounting()
        case .postponed:
            updatePostponedCountdown()
        case .systemAway:
            break
        }
    }

    // MARK: - 手动暂停/恢复

    /// 手动暂停当前阶段。
    ///
    /// 逻辑：
    /// 1. 检查当前阶段是否允许暂停（working/preBreak/resting/postponed 可暂停）
    /// 2. 缓存当前阶段、剩余秒数、休息类型到 paused* 变量
    /// 3. 记录暂停开始时间戳，重置 totalPausedSeconds
    /// 4. 切换到 paused 阶段，关闭 overlay 并清除 deadline
    mutating func pause() {
        guard canFreeze(phase) else { return }
        pausedPhase = phase
        if case let .resting(kind) = phase {
            pausedBreakKind = kind
        } else {
            pausedBreakKind = nil
        }
        pausedRemainingSeconds = remainingSeconds
        pauseStartedAt = now()
        totalPausedSeconds = 0
        phase = .paused
        shouldShowOverlay = false
        workDeadline = nil
        restDeadline = nil
    }

    /// 从暂停恢复。
    ///
    /// 逻辑：
    /// 1. 先 updatePauseAccounting 累计暂停时长
    /// 2. 根据缓存的原阶段调用 resumeFrozenPhase 恢复倒计时
    /// 3. 清除暂停缓存变量
    mutating func resume() {
        guard phase == .paused else { return }
        updatePauseAccounting()
        resumeFrozenPhase(pausedPhase, remaining: pausedRemainingSeconds ?? settings.workDurationSeconds, breakKind: pausedBreakKind)
        pauseStartedAt = nil
        pausedRemainingSeconds = nil
        pausedPhase = nil
        pausedBreakKind = nil
        totalPausedSeconds = 0
    }

    // MARK: - 休息操作

    /// 立即开始休息（跳过 preBreak 等待）。
    ///
    /// 逻辑：
    /// 1. 如果已经在休息状态，直接返回
    /// 2. 使用 nextBreakKind() 确定休息类型（短休息/长休息）
    /// 3. 不发送 preBreak 通知（因用户主动发起）
    mutating func startBreakNow() {
        guard !isResting else { return }
        startRest(kind: nextBreakKind(), sendMissedPreBreakNotification: false)
    }

    /// 延后本次休息提醒。
    ///
    /// 逻辑：
    /// 1. 仅在 preBreak/working/resting 状态下允许
    /// 2. 设置剩余时间为 30 秒 + 延后分钟数（最小 1 分钟）
    /// 3. 切换到 postponed 阶段，关闭 overlay
    /// 4. 重置 preBreakNotificationSent 以允许在 postponed 结束后再次发通知
    mutating func postpone(minutes: Int) {
        guard phase == .preBreak || phase == .working || isResting else { return }
        let added = max(1, minutes) * 60
        shouldShowOverlay = false
        remainingSeconds = 30 + added
        workDeadline = now().addingTimeInterval(TimeInterval(remainingSeconds))
        phase = .postponed
        preBreakNotificationSent = false
    }

    /// 跳过当前休息（计入触发历史和连续跳过次数，但不计入已完成统计）。
    ///
    /// 逻辑：
    /// 1. 如果尚未进入休息阶段，按下一次休息类型记录一次触发
    /// 2. 已进入休息阶段时，触发历史已在 startRest 记录，不重复记录
    /// 3. 递增 consecutiveSkips，生成对应程度的 toast 文案
    /// 4. 立即开始新的工作周期
    mutating func skipBreak() {
        guard phase == .preBreak || isResting || phase == .working || phase == .postponed else { return }
        if !isResting {
            recordRestTrigger(nextBreakKind())
        }
        consecutiveSkips += 1
        lastToastMessage = skipMessage(for: consecutiveSkips)
        shouldShowOverlay = false
        startWorkCycle(duration: settings.workDurationSeconds)
    }

    // MARK: - 工作周期重置

    /// 重置工作倒计时（重新开始一轮工作）。
    /// 仅在 working / preBreak / postponed 阶段可用。
    mutating func resetWorkCycle() {
        guard phase == .working || phase == .preBreak || phase == .postponed else { return }
        startWorkCycle(duration: settings.workDurationSeconds)
    }

    // MARK: - 系统事件处理

    /// 系统即将睡眠或锁屏时调用。
    ///
    /// 逻辑：
    /// 1. 如果设置 pauseOnLock 关闭，直接返回
    /// 2. 检查当前阶段是否允许冻结（同 pause 条件）
    /// 3. 缓存当前阶段、剩余秒数、休息类型到 away* 变量
    /// 4. 切换到 systemAway 阶段，关闭 overlay
    mutating func systemWillSleepOrLock() {
        guard settings.pauseOnLock else { return }
        guard canFreeze(phase) else { return }
        awayPhase = phase
        if case let .resting(kind) = phase {
            awayBreakKind = kind
        } else {
            awayBreakKind = nil
        }
        awayRemainingSeconds = remainingSeconds
        awayStartedAt = now()
        phase = .systemAway
        shouldShowOverlay = false
        workDeadline = nil
        restDeadline = nil
    }

    /// 系统唤醒或解锁后恢复。
    ///
    /// 逻辑：
    /// 1. 根据缓存的原阶段走不同恢复分支：
    ///    - resting：扣除 awayDuration 后继续休息；如果超时则完成休息
    ///    - working/preBreak/postponed：如果 resetAfterLongAway 开启且 awayDuration >= 剩余时间 → 重启工作周期；否则恢复倒计时
    ///    - 其他阶段：直接恢复倒计时
    /// 2. 如果唤醒时不在活跃时段，进入 inactive
    mutating func systemDidWakeOrUnlock() {
        guard phase == .systemAway else { return }
        let rememberedRemaining = awayRemainingSeconds ?? settings.workDurationSeconds
        let rememberedPhase = awayPhase
        let rememberedBreakKind = awayBreakKind
        let awayDuration = awayStartedAt.map { Int(now().timeIntervalSince($0)) } ?? 0
        awayRemainingSeconds = nil
        awayPhase = nil
        awayBreakKind = nil
        awayStartedAt = nil

        switch rememberedPhase {
        case .resting:
            // 休息阶段：扣除离场时间后继续剩余休息；如果离场已经够久，直接完成休息
            let remainingAfterAway = rememberedRemaining - awayDuration
            currentBreakKind = rememberedBreakKind ?? currentBreakKind
            if remainingAfterAway <= 0 {
                completeRest()
            } else {
                resumeRest(kind: currentBreakKind, duration: remainingAfterAway)
            }
        case .working, .preBreak, .postponed:
            guard isActiveTime(now()) else {
                becomeInactive()
                return
            }
            // 工作阶段：如果设置了长时间离场重置且离场时长 ≥ 剩余时间 → 重启周期；否则恢复
            if settings.resetAfterLongAway && awayDuration >= rememberedRemaining {
                startWorkCycle(duration: settings.workDurationSeconds)
            } else {
                resumeFrozenPhase(rememberedPhase, remaining: rememberedRemaining, breakKind: rememberedBreakKind)
            }
        case .inactive, .paused, .systemAway, .none:
            guard isActiveTime(now()) else {
                becomeInactive()
                return
            }
            resumeFrozenPhase(rememberedPhase, remaining: rememberedRemaining, breakKind: rememberedBreakKind)
        }
    }

    // MARK: - 一次性标识消费（调用方应在同步循环中调用）

    /// 消费并返回 toast 消息（消费后清空）。
    mutating func consumeToast() -> String? {
        let message = lastToastMessage
        lastToastMessage = nil
        return message
    }

    /// 消费并返回 preBreak 通知标识。
    mutating func consumePreBreakNotificationFlag() -> Bool {
        let value = shouldSendPreBreakNotification
        shouldSendPreBreakNotification = false
        return value
    }

    /// 清除 overlay 显示标识。
    mutating func clearOverlayFlag() {
        shouldShowOverlay = false
    }

    // MARK: - Overlay 状态构建

    /// 如果当前在休息阶段，构造 RestOverlayState 供 UI 层渲染全屏休息界面。
    ///
    /// 逻辑：
    /// 1. 仅在 phase 为 .resting 时返回值
    /// 2. 根据休息类型取对应时长（shortBreakSeconds / longBreakSeconds）
    /// 3. 若调用方提供了 advice 则使用，否则使用 AdviceLibrary 随机健康建议
    func currentOverlayState(advice: String? = nil) -> RestOverlayState? {
        guard case let .resting(kind) = phase else { return nil }
        let total = kind == .short ? settings.shortBreakSeconds : settings.longBreakSeconds
        return RestOverlayState(
            kind: kind,
            remainingSeconds: remainingSeconds,
            totalSeconds: total,
            advice: advice ?? AdviceLibrary.randomTip(for: kind),
            intensity: settings.overlayIntensity,
            animationEnabled: settings.animationEnabled
        )
    }

    /// 判断下一次应使用哪种休息类型（短休息/长休息）。
    var upcomingBreakKind: BreakKind {
        nextBreakKind()
    }

    // MARK: - 计算属性（私有）

    /// 当前是否处于休息阶段。
    private var isResting: Bool {
        if case .resting = phase { return true }
        return false
    }

    // MARK: - 状态冻结检查

    /// 判断指定阶段是否允许"冻结"（暂停或系统离场）。
    /// 活跃阶段（working/preBreak/resting/postponed）可冻结，非活跃阶段不可。
    private func canFreeze(_ phase: BreakPhase) -> Bool {
        switch phase {
        case .working, .preBreak, .resting, .postponed:
            return true
        case .inactive, .paused, .systemAway:
            return false
        }
    }

    // MARK: - 冻结恢复

    /// 根据缓存的原始阶段恢复倒计时。
    ///
    /// 逻辑：
    /// 1. resting → 调用 resumeRest 继续休息
    /// 2. preBreak/postponed → 恢复工作倒计时，如果剩余 ≤ 30 秒则重置为 preBreak
    /// 3. working/其他 → 直接开始新工作周期
    private mutating func resumeFrozenPhase(_ frozenPhase: BreakPhase?, remaining: Int, breakKind: BreakKind?) {
        let safeRemaining = clampedRemaining(remaining, for: frozenPhase, breakKind: breakKind)
        switch frozenPhase {
        case .resting:
            resumeRest(kind: breakKind ?? currentBreakKind, duration: safeRemaining)
        case .preBreak, .postponed:
            startWorkCycle(duration: safeRemaining)
            if safeRemaining <= 30 {
                phase = .preBreak
            }
        case .working:
            startWorkCycle(duration: safeRemaining)
        case .inactive, .paused, .systemAway, .none:
            startWorkCycle(duration: safeRemaining)
        }
    }

    // MARK: - 倒计时更新（私有）

    /// 更新工作阶段倒计时。
    ///
    /// 逻辑：
    /// 1. 从 workDeadline 计算剩余秒数
    /// 2. 剩余为 0 → 自动开始休息
    /// 3. 剩余 ≤ 30 → 切换到 preBreak 阶段；如果启用预提醒且未发过，置位 shouldSendPreBreakNotification
    /// 4. 剩余 > 30 → 保持在 working 阶段
    private mutating func updateWorkCountdown() {
        guard let deadline = workDeadline else {
            startWorkCycle(duration: settings.workDurationSeconds)
            return
        }

        remainingSeconds = max(0, Int(ceil(deadline.timeIntervalSince(now()))))
        if remainingSeconds == 0 {
            startRest()
        } else if remainingSeconds <= 30 {
            phase = .preBreak
            if settings.preBreakNotificationEnabled && !preBreakNotificationSent {
                shouldSendPreBreakNotification = true
                preBreakNotificationSent = true
            }
        } else {
            phase = .working
        }
    }

    /// 更新延后期倒计时。
    ///
    /// 逻辑：
    /// 1. 从 workDeadline 计算剩余（延后期共享 workDeadline）
    /// 2. 剩余 ≤ 30 → 切换到 preBreak 阶段（重新激活提醒），允许发送通知
    private mutating func updatePostponedCountdown() {
        guard let deadline = workDeadline else {
            startWorkCycle(duration: settings.workDurationSeconds)
            return
        }
        remainingSeconds = max(0, Int(ceil(deadline.timeIntervalSince(now()))))
        if remainingSeconds <= 30 {
            phase = .preBreak
            if settings.preBreakNotificationEnabled && !preBreakNotificationSent {
                shouldSendPreBreakNotification = true
                preBreakNotificationSent = true
            }
        }
    }

    /// 更新休息阶段倒计时。
    ///
    /// 逻辑：
    /// 1. 从 restDeadline 计算剩余秒数
    /// 2. 剩余为 0 → 完成休息（completeRest），开始新一轮工作
    private mutating func updateRestCountdown() {
        guard let deadline = restDeadline else { return }
        remainingSeconds = max(0, Int(ceil(deadline.timeIntervalSince(now()))))
        if remainingSeconds == 0 {
            completeRest()
        }
    }

    /// 累计暂停时长（每次 resume 或 tick 时调用）。
    private mutating func updatePauseAccounting() {
        guard let pauseStartedAt else { return }
        totalPausedSeconds = Int(now().timeIntervalSince(pauseStartedAt))
    }

    // MARK: - 阶段转换（私有）

    /// 开始新的工作周期。
    ///
    /// 逻辑：
    /// 1. 如果时长为 0，直接进入 preBreak；否则进入 working
    /// 2. 设置 workDeadline 为 now + duration
    /// 3. 清除 restDeadline、overlay、通知标志
    private mutating func startWorkCycle(duration: Int) {
        phase = duration <= 30 ? .preBreak : .working
        remainingSeconds = max(1, duration)
        workDeadline = now().addingTimeInterval(TimeInterval(remainingSeconds))
        restDeadline = nil
        shouldShowOverlay = false
        shouldSendPreBreakNotification = false
        preBreakNotificationSent = false
    }

    /// 自动开始休息（无参版本，由 updateWorkCountdown 调用）。
    /// 确定下次休息类型并调用完整版 startRest。
    private mutating func startRest() {
        startRest(kind: nextBreakKind(), sendMissedPreBreakNotification: settings.preBreakNotificationEnabled && !preBreakNotificationSent)
    }

    /// 开始休息并将该次休息记入触发历史。
    ///
    /// 逻辑：
    /// 1. 记录本次休息类型到触发历史，供长休息间隔使用
    /// 2. 根据休息类型设置对应时长（short / long）
    /// 3. 切换到 resting(phase) 阶段，设置 restDeadline
    /// 4. 置位 shouldShowOverlay 触发全屏休息界面
    /// 5. 如果之前错过了 preBreak 通知，允许补发
    private mutating func startRest(kind: BreakKind, sendMissedPreBreakNotification: Bool) {
        currentBreakKind = kind
        recordRestTrigger(currentBreakKind)
        let duration = currentBreakKind == .short ? settings.shortBreakSeconds : settings.longBreakSeconds
        phase = .resting(currentBreakKind)
        remainingSeconds = duration
        restDeadline = now().addingTimeInterval(TimeInterval(duration))
        workDeadline = nil
        shouldShowOverlay = true
        shouldSendPreBreakNotification = sendMissedPreBreakNotification
        preBreakNotificationSent = false
    }

    /// 恢复被暂停/离场中断的休息（与 startRest 类似，但不记录历史）。
    private mutating func resumeRest(kind: BreakKind, duration: Int) {
        currentBreakKind = kind
        phase = .resting(kind)
        remainingSeconds = max(1, duration)
        restDeadline = now().addingTimeInterval(TimeInterval(remainingSeconds))
        workDeadline = nil
        shouldShowOverlay = true
        shouldSendPreBreakNotification = false
        preBreakNotificationSent = false
    }

    /// 完成一次休息，增加完成统计、重置跳过计数并开始新的工作周期。
    private mutating func completeRest() {
        recordCompletedRest(currentBreakKind)
        consecutiveSkips = 0
        shouldShowOverlay = false
        if isActiveTime(now()) {
            startWorkCycle(duration: settings.workDurationSeconds)
        } else {
            becomeInactive()
        }
    }

    /// 根据新设置裁剪当前和冻结缓存中的剩余时间。
    ///
    /// 逻辑：
    /// 1. 当前正在运行的工作/休息倒计时需要同步裁剪，并刷新 deadline
    /// 2. 暂停和系统离场保存的 remaining 也要裁剪，否则恢复后会超过新设置
    /// 3. 不主动延长倒计时，只限制到新的最大时长
    private mutating func clampCurrentAndFrozenRemainingToSettings() {
        switch phase {
        case .working, .preBreak, .postponed:
            remainingSeconds = clampedRemaining(remainingSeconds, for: phase, breakKind: nil)
            workDeadline = now().addingTimeInterval(TimeInterval(remainingSeconds))
        case .resting(let kind):
            remainingSeconds = clampedRemaining(remainingSeconds, for: phase, breakKind: kind)
            restDeadline = now().addingTimeInterval(TimeInterval(remainingSeconds))
        case .paused:
            if let pausedRemainingSeconds {
                let clamped = clampedRemaining(pausedRemainingSeconds, for: pausedPhase, breakKind: pausedBreakKind)
                self.pausedRemainingSeconds = clamped
                remainingSeconds = clamped
            }
        case .systemAway:
            if let awayRemainingSeconds {
                let clamped = clampedRemaining(awayRemainingSeconds, for: awayPhase, breakKind: awayBreakKind)
                self.awayRemainingSeconds = clamped
                remainingSeconds = clamped
            }
        case .inactive:
            break
        }
    }

    /// 根据阶段返回不超过当前设置上限的剩余秒数。
    private func clampedRemaining(_ remaining: Int, for phase: BreakPhase?, breakKind: BreakKind?) -> Int {
        let upperBound: Int
        switch phase {
        case .resting(let kind):
            upperBound = kind == .short ? settings.shortBreakSeconds : settings.longBreakSeconds
        default:
            upperBound = settings.workDurationSeconds
        }
        return max(1, min(remaining, upperBound))
    }

    /// 非活跃时间段内的 tick 分发。
    ///
    /// 逻辑：
    /// 1. 用户手动触发的休息应继续倒计时，不被工作可用时间窗口打断
    /// 2. 暂停状态继续累计暂停时长
    /// 3. 其他自动工作状态回到 inactive，等待下一次活跃时间
    private mutating func tickOutsideActiveTime() {
        switch phase {
        case .resting:
            updateRestCountdown()
        case .paused:
            updatePauseAccounting()
        case .systemAway:
            break
        default:
            becomeInactive()
        }
    }

    // MARK: - 休息周期管理

    /// 根据周期设置和休息触发历史，决定下一次的休息类型。
    ///
    /// 逻辑：
    /// 1. 如果 breakCycleEnabled 关闭，始终返回 .short
    /// 2. 如果自上次长休息触发后短休息触发数 >= longBreakFrequency，返回 .long
    /// 3. 否则返回 .short
    private func nextBreakKind() -> BreakKind {
        guard settings.breakCycleEnabled else { return .short }
        if shortBreaksSinceLastLong >= settings.longBreakFrequency {
            return .long
        }
        return .short
    }

    /// 计算自上次长休息触发以来的短休息触发次数。
    ///
    /// 逻辑：
    /// 1. 如果历史为空，用减法估算（今日短休息总数 - 长休息次数 × 长休息频率）
    /// 2. 否则从历史记录末尾向前遍历，直到遇到长休息
    private var shortBreaksSinceLastLong: Int {
        if restHistory.isEmpty {
            return max(0, todayShortBreaks - todayLongBreaks * settings.longBreakFrequency)
        }
        let afterLastLong = restHistory.reversed().prefix { $0 != .long }
        return afterLastLong.filter { $0 == .short }.count
    }

    /// 将一次休息触发记入历史。
    private mutating func recordRestTrigger(_ kind: BreakKind) {
        restHistory.append(kind)
    }

    /// 将一次完整完成的休息计入今日统计。
    private mutating func recordCompletedRest(_ kind: BreakKind) {
        switch kind {
        case .short:
            todayShortBreaks += 1
        case .long:
            todayLongBreaks += 1
        }
    }

    // MARK: - 非活跃时段处理

    /// 进入非活跃状态（不在活跃时间段内）。
    ///
    /// 逻辑：
    /// 1. 重置所有计时状态
    /// 2. 计算并保存下一次活跃开始时间（供 UI 展示"X 点开始"）
    private mutating func becomeInactive() {
        phase = .inactive
        remainingSeconds = 0
        shouldShowOverlay = false
        shouldSendPreBreakNotification = false
        workDeadline = nil
        restDeadline = nil
        nextActiveStart = nextStart(after: now())
    }

    // MARK: - 时间边界检查

    /// 判断指定时间是否在活跃时间段内（活跃日期、开始/结束窗口、午休暂停全部生效）。
    ///
    /// 逻辑：
    /// 1. 普通当天窗口按 start <= minute < end 判断
    /// 2. 跨天窗口按 start...24:00 或 00:00..<end 判断，凌晨段归属前一天的活跃日期
    /// 3. 开始和结束相同视为无效窗口，避免误当作全天
    private func isActiveTime(_ date: Date) -> Bool {
        guard settings.activeStartMinute != settings.activeEndMinute else { return false }
        let minute = minuteOfDay(for: date)
        guard isInsideActiveWindow(minute: minute, date: date) else { return false }
        if settings.lunchPauseEnabled && minute >= settings.lunchStartMinute && minute < settings.lunchEndMinute {
            return false
        }
        return true
    }

    /// 判断分钟是否落入工作可用窗口，并处理跨天窗口的日期归属。
    ///
    /// 逻辑：
    /// 1. 非跨天：当前日期必须是活跃日
    /// 2. 跨天晚间段：当前日期是活跃日
    /// 3. 跨天凌晨段：前一天是活跃日，因为这段时间来自前一天开始的工作窗口
    private func isInsideActiveWindow(minute: Int, date: Date) -> Bool {
        if settings.activeEndMinute > settings.activeStartMinute {
            return isActiveDay(date) && minute >= settings.activeStartMinute && minute < settings.activeEndMinute
        }

        if minute >= settings.activeStartMinute {
            return isActiveDay(date)
        }

        if minute < settings.activeEndMinute {
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: date) else { return false }
            return isActiveDay(previousDay)
        }

        return false
    }

    /// 判断指定日期是否为活跃日（工作日/自定义）。
    private func isActiveDay(_ date: Date) -> Bool {
        switch settings.activeDays {
        case .everyday:
            return true
        case .weekdays:
            let weekday = calendar.component(.weekday, from: date)
            return weekday >= 2 && weekday <= 6
        case .custom:
            let weekday = calendar.component(.weekday, from: date)
            return settings.customActiveWeekdays.contains(weekday)
        }
    }

    /// 将日期转换为分钟数（从午夜开始的分钟偏移）。
    private func minuteOfDay(for date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    /// 寻找指定时间之后的下一个活跃开始时间（最多搜索未来 14 天）。
    ///
    /// 逻辑：下一个开始时间始终是某个活跃日的 activeStartMinute；跨天窗口的凌晨段不额外生成开始点。
    private func nextStart(after date: Date) -> Date? {
        guard settings.activeStartMinute != settings.activeEndMinute else { return nil }
        for offset in 0...14 {
            guard let candidateDay = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)),
                  isActiveDay(candidateDay) else { continue }
            let candidate = calendar.date(byAdding: .minute, value: settings.activeStartMinute, to: candidateDay)
            if let candidate, candidate > date {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Toast 文案生成

    /// 根据连续跳过次数生成不同语气的提示文案。
    private func skipMessage(for count: Int) -> String {
        switch count {
        case 0...1:
            return "已跳过本次休息"
        case 2:
            return "你今天已经跳过 2 次休息了"
        case 3...4:
            return "建议找个时间休息一下"
        default:
            return "你已经连续工作较长时间了"
        }
    }
}
