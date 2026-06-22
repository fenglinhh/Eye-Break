import Foundation
import Combine
import SwiftUI

@MainActor
final class DailyBreakModel: ObservableObject {
    @Published var settings: BreakSettings {
        didSet {
            store.saveSettings(settings)
            engine.updateSettings(settings)
            launchAtLogin.apply(enabled: settings.launchAtLogin)
        }
    }
    @Published private(set) var phase: BreakPhase = .inactive
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var todayShortBreaks = 0
    @Published private(set) var todayLongBreaks = 0
    @Published var toastMessage: String?

    private let store: DailyBreakStore
    private let notifications: NotificationService
    private let overlayController: RestOverlayController
    private let systemMonitor: SystemActivityMonitor
    private let launchAtLogin: LaunchAtLoginService
    private var engine: BreakTimerEngine
    private var tickTimer: Timer?
    private var toastTimer: Timer?
    private var currentAdvice: String?
    private var hasStarted = false
    private var isOverlayVisible = false

    convenience init() {
        self.init(
            store: DailyBreakStore(),
            notifications: NotificationService(),
            overlayController: RestOverlayController(),
            systemMonitor: SystemActivityMonitor(),
            launchAtLogin: LaunchAtLoginService()
        )
    }

    init(
        store: DailyBreakStore,
        notifications: NotificationService,
        overlayController: RestOverlayController,
        systemMonitor: SystemActivityMonitor,
        launchAtLogin: LaunchAtLoginService
    ) {
        self.store = store
        self.notifications = notifications
        self.overlayController = overlayController
        self.systemMonitor = systemMonitor
        self.launchAtLogin = launchAtLogin
        let loadedSettings = store.loadSettings()
        self.settings = loadedSettings
        self.engine = BreakTimerEngine(settings: loadedSettings)
        self.engine.restoreStats(store.loadStats())
        bindServices()
        syncFromEngine()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        notifications.requestAuthorization()
        launchAtLogin.apply(enabled: settings.launchAtLogin)
        systemMonitor.start()
        engine.startIfAllowed()
        syncFromEngine()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    func pauseThirtyMinutes() {
        engine.pause(minutes: 30)
        syncFromEngine()
    }

    func pauseUntilTomorrow() {
        engine.pauseUntilTomorrow()
        syncFromEngine()
    }

    func resume() {
        engine.resume()
        syncFromEngine()
    }

    func startBreakNow() {
        engine.startBreakNow()
        syncFromEngine()
    }

    func skipBreak() {
        engine.skipBreak()
        syncFromEngine()
    }

    func postponeOneMinute() {
        engine.postpone(minutes: 1)
        syncFromEngine()
    }

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
            return "已暂停 · 剩余 \(formatDuration(remainingSeconds))"
        case .systemAway:
            return "锁屏或睡眠暂停中"
        case .postponed:
            return "已延后 · \(formatDuration(remainingSeconds)) 后提醒"
        }
    }

    var menuBarTitle: String {
        switch phase {
        case .inactive:
            return "休息"
        case .paused:
            return "暂停 \(formatDuration(remainingSeconds))"
        case .preBreak:
            return "\(remainingSeconds)秒"
        case .resting:
            return "休息 \(formatDuration(remainingSeconds))"
        default:
            return formatDuration(remainingSeconds)
        }
    }

    var canPostponeBreak: Bool {
        switch phase {
        case .working, .preBreak, .resting:
            return true
        case .inactive, .paused, .systemAway, .postponed:
            return false
        }
    }

    private func bindServices() {
        overlayController.onSkip = { [weak self] in
            Task { @MainActor in self?.skipBreak() }
        }
        overlayController.onPostpone = { [weak self] in
            Task { @MainActor in self?.postponeOneMinute() }
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
    }

    private func tick() {
        engine.tick()
        syncFromEngine()
    }

    private func syncFromEngine() {
        phase = engine.phase
        remainingSeconds = engine.remainingSeconds
        todayShortBreaks = engine.todayShortBreaks
        todayLongBreaks = engine.todayLongBreaks
        store.saveStats(engine.stats)

        if engine.consumePreBreakNotificationFlag() {
            notifications.sendPreBreakNotification(playSound: settings.playSound)
        }

        if let message = engine.consumeToast() {
            showToast(message)
        }

        if let overlayState = makeOverlayState() {
            if engine.shouldShowOverlay {
                overlayController.show(state: overlayState)
                engine.clearOverlayFlag()
            } else {
                overlayController.update(state: overlayState)
            }
            isOverlayVisible = true
        } else {
            if isOverlayVisible {
                overlayController.close()
                isOverlayVisible = false
            }
            currentAdvice = nil
        }
    }

    private func makeOverlayState() -> RestOverlayState? {
        guard case let .resting(kind) = engine.phase else { return nil }
        if currentAdvice == nil {
            currentAdvice = settings.healthTipsEnabled ? AdviceLibrary.randomTip(for: kind) : ""
        }
        return engine.currentOverlayState(advice: currentAdvice)
    }

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
