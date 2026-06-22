import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UserNotifications

final class NotificationService {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func sendPreBreakNotification(playSound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "30 秒后开始休息"
        content.subtitle = "可以先保存一下当前工作"
        if playSound {
            content.sound = .default
        }
        let request = UNNotificationRequest(identifier: "daily-break.pre-break", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

final class LaunchAtLoginService {
    func apply(enabled: Bool) {
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

final class SystemActivityMonitor {
    var onAway: (() -> Void)?
    var onReturn: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onAway?()
        })
        observers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onAway?()
        })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onAway?()
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onReturn?()
        })
        observers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onReturn?()
        })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onReturn?()
        })
    }

    deinit {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}

final class RestOverlayController {
    private struct OverlayEntry {
        let window: NSWindow
        let model: RestOverlayWindowModel
    }

    private var entries: [OverlayEntry] = []
    private var retiredEntries: [OverlayEntry] = []

    var onSkip: (() -> Void)?
    var onPostpone: (() -> Void)?

    func show(state: RestOverlayState) {
        close()
        entries = NSScreen.screens.enumerated().map { index, screen in
            let model = RestOverlayWindowModel(
                state: state,
                isPrimary: index == 0,
                onSkip: { [weak self] in self?.onSkip?() },
                onPostpone: { [weak self] in self?.onPostpone?() }
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

    func update(state: RestOverlayState) {
        guard !entries.isEmpty else {
            show(state: state)
            return
        }
        for entry in entries {
            entry.model.state = state
        }
    }

    func close() {
        guard !entries.isEmpty else { return }

        let closingEntries = entries
        entries.removeAll()
        retiredEntries.append(contentsOf: closingEntries)

        for entry in closingEntries {
            entry.window.ignoresMouseEvents = true
            entry.window.orderOut(nil)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            for entry in closingEntries {
                entry.window.contentView = nil
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.retiredEntries.removeAll { retired in
                closingEntries.contains { $0.window === retired.window }
            }
        }
    }
}
