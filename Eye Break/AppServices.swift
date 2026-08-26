//
//  AppServices.swift
//  Eye Break
//
//  职责：提供应用所需的基础服务层，包括登录项管理、系统事件监听、投影检测和全屏休息蒙层控制。
//  依赖：ServiceManagement、AppKit、SwiftUI
//  被使用：DailyBreakModel（在 setupServices 中初始化并持有全部服务实例）
//

import AppKit
import Combine
import CoreGraphics
import ServiceManagement
import SwiftUI

/// 登录自启管理服务
///
/// 逻辑：
/// 1. 通过 SMAppService.mainApp 的 register/unregister 控制开机自启
/// 2. apply(enabled:) 根据入参决定注册或注销，并检查当前状态避免重复操作
final class LaunchAtLoginService {
    /// 登录项系统调用可能触发 LaunchServices/ServiceManagement 内部等待，放到串行队列避免阻塞主线程。
    private let queue = DispatchQueue(label: "com.dailybreak.launch-at-login", qos: .userInitiated)

    /// 应用登录自启设置
    ///
    /// 逻辑：
    /// 1. 将 ServiceManagement 调用派发到 userInitiated 串行队列，避免主线程被系统服务等待拖住
    /// 2. enabled 为 true 且当前状态不为 .enabled 时执行 register
    /// 3. enabled 为 false 且当前状态为 .enabled 时执行 unregister
    /// 4. 捕获异常并记录日志，不向上抛出
    /// - Parameter enabled: 是否启用开机自启
    func apply(enabled: Bool) {
        queue.async {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Daily Break launch-at-login update failed: \(error.localizedDescription)")
            }
        }
    }
}

/// 系统活动状态监听器
///
/// 逻辑：
/// 1. 监听 NSWorkspace 的睡眠、屏幕休眠、会话切换等系统通知
/// 2. 监听 DistributedNotificationCenter 的屏幕锁定/解锁通知
/// 3. 共注册 8 个观察者，通过 onAway/onReturn 回调通知上层
/// 4. 在 deinit 中清理所有观察者，避免野指针
final class SystemActivityMonitor {
    /// 用户离开（睡眠/锁屏/会话切换）时的回调
    var onAway: (() -> Void)?
    /// 用户返回（唤醒/解锁/会话激活）时的回调
    var onReturn: (() -> Void)?

    /// 存储 NSWorkspace 通知中心的观察者令牌，用于 deinit 时移除
    private var workspaceObservers: [NSObjectProtocol] = []
    /// 存储 DistributedNotificationCenter 的观察者令牌，用于 deinit 时移除
    private var distributedObservers: [NSObjectProtocol] = []

    /// 注册所有系统事件监听
    ///
    /// 逻辑：
    /// 1. 在 NSWorkspace.notificationCenter 上注册 6 个通知：睡眠、屏幕休眠、会话失活（触发 onAway），以及唤醒、屏幕唤醒、会话激活（触发 onReturn）
    /// 2. 在 DistributedNotificationCenter 上注册 2 个通知：屏幕锁定（触发 onAway）、屏幕解锁（触发 onReturn）
    /// 3. 所有回调都在主队列执行，且使用 [weak self] 避免循环引用
    func start() {
        // NSWorkspace 通知 — 系统级别的睡眠/唤醒和会话切换
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspaceCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onAway?()
        })
        workspaceObservers.append(workspaceCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onAway?()
        })
        workspaceObservers.append(workspaceCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onAway?()
        })
        workspaceObservers.append(workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onReturn?()
        })
        workspaceObservers.append(workspaceCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onReturn?()
        })
        workspaceObservers.append(workspaceCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onReturn?()
        })

        // 分布式通知中心 — 监听屏幕锁定/解锁（来自 loginwindow 进程）
        let distributedCenter = DistributedNotificationCenter.default()
        distributedObservers.append(distributedCenter.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.onAway?()
        })
        distributedObservers.append(distributedCenter.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.onReturn?()
        })
    }

    deinit {
        // 清理 NSWorkspace 观察者，避免在 deinit 后收到过期通知
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        // 清理分布式通知中心观察者
        for observer in distributedObservers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }
}

/// 投影/外接显示状态监听器。
///
/// 逻辑：
/// 1. 启动时读取当前在线显示器状态
/// 2. 监听 NSApplication.didChangeScreenParametersNotification
/// 3. 检测到外接/投屏显示器数量大于 1，或任一显示器处于镜像集合时，视为投影中
/// 4. 状态变化时只发一次 started/ended 回调，避免重复冻结或恢复
final class ProjectionMonitor {
    var onProjectionStarted: (() -> Void)?
    var onProjectionEnded: (() -> Void)?

    private var observer: NSObjectProtocol?
    private(set) var isProjecting = false

    func start() {
        guard observer == nil else { return }
        isProjecting = Self.detectProjection()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshProjectionState()
        }
        if isProjecting {
            onProjectionStarted?()
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func refreshProjectionState() {
        let nextState = Self.detectProjection()
        guard nextState != isProjecting else { return }
        isProjecting = nextState
        if nextState {
            onProjectionStarted?()
        } else {
            onProjectionEnded?()
        }
    }

    private static func detectProjection() -> Bool {
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount)
        guard displayCount > 0 else { return NSScreen.screens.count > 1 }
        if displayCount > 1 { return true }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetOnlineDisplayList(displayCount, &displays, &displayCount)
        return displays.prefix(Int(displayCount)).contains { display in
            CGDisplayIsInMirrorSet(display) != 0
        }
    }
}

/// 全屏休息蒙层控制器
///
/// 逻辑：
/// 1. 为每个 NSScreen 创建一个全屏 NSWindow，使用 .screenSaver 层级覆盖所有内容
/// 2. 每个窗口绑定一个 RestOverlayWindowModel，通过 SwiftUI RestOverlayView 渲染
/// 3. show/update/close 管理窗口生命周期，close 使用延时释放避免视觉闪烁
final class RestOverlayController {
    /// 单个屏幕的蒙层条目，包含窗口引用和对应的视图模型
    private struct OverlayEntry {
        let window: NSWindow
        let model: RestOverlayWindowModel
    }

    /// 当前活跃的蒙层条目，与 NSScreen.screens 一一对应
    private var entries: [OverlayEntry] = []
    /// 已关闭但尚未释放的条目，用于延时清理 contentView 避免残留
    private var retiredEntries: [OverlayEntry] = []

    /// 用户点击"跳过"时的回调，透传给 RestOverlayWindowModel
    var onSkip: (() -> Void)?

    /// 在所有屏幕上显示休息蒙层
    ///
    /// 逻辑：
    /// 1. 先关闭已有蒙层
    /// 2. 遍历每个屏幕，为主屏幕（index == 0）和副屏幕分别创建 OverlayEntry
    /// 3. 每个窗口的 contentView 设置为 NSHostingView 包裹的 RestOverlayView
    /// 4. 窗口层级设为 .screenSaver 以确保盖住 Dock、菜单栏和其他应用
    /// 5. 设置 collectionBehavior 使其跟随所有 Space 且保持固定位置
    /// - Parameter state: 蒙层状态，包含倒计时、强度、动画开关等信息
    func show(state: RestOverlayState) {
        close()
        entries = NSScreen.screens.enumerated().map { index, screen in
            let model = RestOverlayWindowModel(
                state: state,
                isPrimary: index == 0,
                onSkip: { [weak self] in self?.onSkip?() }
            )
            let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
            window.contentView = NSHostingView(rootView: RestOverlayView(model: model))
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = false
            window.alphaValue = 1
            window.makeKeyAndOrderFront(nil)
            return OverlayEntry(window: window, model: model)
        }
    }

    /// 更新所有屏幕蒙层的状态（倒计时刷新）
    ///
    /// 逻辑：
    /// 1. 如果当前没有活跃条目，降级为调用 show 重新创建
    /// 2. 否则遍历所有条目，直接更新其 model.state
    /// - Parameter state: 新的蒙层状态
    func update(state: RestOverlayState) {
        guard !entries.isEmpty else {
            show(state: state)
            return
        }
        for entry in entries {
            entry.model.state = state
        }
    }

    /// 关闭所有屏幕的蒙层
    ///
    /// 逻辑：
    /// 1. 将 entries 转移到 retiredEntries 中，立即清空活跃列表
    /// 2. 将所有窗口设为忽略鼠标事件并 orderOut 隐藏
    /// 3. 0.35 秒后将 contentView 置为 nil 以释放视图资源
    /// 4. 1 秒后从 retiredEntries 中移除已关闭的条目（完成完整生命周期）
    func close() {
        guard !entries.isEmpty else { return }

        // 将当前条目转移到退休列表，方便延时清理
        let closingEntries = entries
        entries.removeAll()
        retiredEntries.append(contentsOf: closingEntries)

        // 立即隐藏窗口并禁用它
        for entry in closingEntries {
            entry.window.ignoresMouseEvents = true
            entry.window.orderOut(nil)
        }

        // 延时释放 contentView，确保动画过渡完成后才回收
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            for entry in closingEntries {
                entry.window.contentView = nil
            }
        }

        // 从退休列表中清除已关闭的条目，完成完整生命周期
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.retiredEntries.removeAll { retired in
                closingEntries.contains { $0.window === retired.window }
            }
        }
    }
}
