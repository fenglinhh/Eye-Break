import Foundation

struct BreakTimerEngine {
    private(set) var phase: BreakPhase = .inactive
    private(set) var remainingSeconds: Int = 0
    private(set) var todayShortBreaks: Int = 0
    private(set) var todayLongBreaks: Int = 0
    private(set) var consecutiveSkips: Int = 0
    private(set) var totalPausedSeconds: Int = 0
    private(set) var shouldShowOverlay = false
    private(set) var shouldSendPreBreakNotification = false
    private(set) var lastToastMessage: String?
    private(set) var nextActiveStart: Date?
    private(set) var currentBreakKind: BreakKind = .short

    var settings: BreakSettings
    private var now: () -> Date
    private var calendar: Calendar
    private var workDeadline: Date?
    private var restDeadline: Date?
    private var pauseStartedAt: Date?
    private var pausedRemainingSeconds: Int?
    private var pausedPhase: BreakPhase?
    private var pausedBreakKind: BreakKind?
    private var awayRemainingSeconds: Int?
    private var awayPhase: BreakPhase?
    private var awayBreakKind: BreakKind?
    private var preBreakNotificationSent = false

    init(settings: BreakSettings, now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.settings = settings
        self.now = now
        self.calendar = calendar
    }

    mutating func updateSettings(_ settings: BreakSettings) {
        self.settings = settings
        if phase == .working || phase == .preBreak {
            remainingSeconds = min(remainingSeconds, settings.workDurationSeconds)
        }
    }

    mutating func restoreStats(_ stats: BreakStats) {
        todayShortBreaks = stats.shortBreaks
        todayLongBreaks = stats.longBreaks
        consecutiveSkips = stats.consecutiveSkips
    }

    var stats: BreakStats {
        BreakStats(dayKey: BreakStats.dayKey(for: now(), calendar: calendar), shortBreaks: todayShortBreaks, longBreaks: todayLongBreaks, consecutiveSkips: consecutiveSkips)
    }

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

    mutating func tick() {
        guard isActiveTime(now()) else {
            becomeInactive()
            return
        }

        shouldSendPreBreakNotification = false

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

    mutating func startBreakNow() {
        startRest(kind: .short, sendMissedPreBreakNotification: false)
    }

    mutating func postpone(minutes: Int) {
        guard phase == .preBreak || phase == .working || isResting else { return }
        let added = max(1, minutes) * 60
        shouldShowOverlay = false
        remainingSeconds = 30 + added
        workDeadline = now().addingTimeInterval(TimeInterval(remainingSeconds))
        phase = .postponed
        preBreakNotificationSent = false
    }

    mutating func skipBreak() {
        guard phase == .preBreak || isResting || phase == .working || phase == .postponed else { return }
        consecutiveSkips += 1
        lastToastMessage = skipMessage(for: consecutiveSkips)
        shouldShowOverlay = false
        startWorkCycle(duration: settings.workDurationSeconds)
    }

    mutating func resetWorkCycle() {
        guard phase == .working || phase == .preBreak || phase == .postponed else { return }
        startWorkCycle(duration: settings.workDurationSeconds)
    }

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
        phase = .systemAway
        shouldShowOverlay = false
        workDeadline = nil
        restDeadline = nil
    }

    mutating func systemDidWakeOrUnlock() {
        guard phase == .systemAway else { return }
        let rememberedRemaining = awayRemainingSeconds ?? settings.workDurationSeconds
        let rememberedPhase = awayPhase
        let rememberedBreakKind = awayBreakKind
        awayRemainingSeconds = nil
        awayPhase = nil
        awayBreakKind = nil

        guard isActiveTime(now()) else {
            becomeInactive()
            return
        }

        resumeFrozenPhase(rememberedPhase, remaining: rememberedRemaining, breakKind: rememberedBreakKind)
    }

    mutating func consumeToast() -> String? {
        let message = lastToastMessage
        lastToastMessage = nil
        return message
    }

    mutating func consumePreBreakNotificationFlag() -> Bool {
        let value = shouldSendPreBreakNotification
        shouldSendPreBreakNotification = false
        return value
    }

    mutating func clearOverlayFlag() {
        shouldShowOverlay = false
    }

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

    private var isResting: Bool {
        if case .resting = phase { return true }
        return false
    }

    private func canFreeze(_ phase: BreakPhase) -> Bool {
        switch phase {
        case .working, .preBreak, .resting, .postponed:
            return true
        case .inactive, .paused, .systemAway:
            return false
        }
    }

    private mutating func resumeFrozenPhase(_ frozenPhase: BreakPhase?, remaining: Int, breakKind: BreakKind?) {
        switch frozenPhase {
        case .resting:
            resumeRest(kind: breakKind ?? currentBreakKind, duration: remaining)
        case .preBreak, .postponed:
            startWorkCycle(duration: remaining)
            if remaining <= 30 {
                phase = .preBreak
            }
        case .working:
            startWorkCycle(duration: remaining)
        case .inactive, .paused, .systemAway, .none:
            startWorkCycle(duration: remaining)
        }
    }

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

    private mutating func updateRestCountdown() {
        guard let deadline = restDeadline else { return }
        remainingSeconds = max(0, Int(ceil(deadline.timeIntervalSince(now()))))
        if remainingSeconds == 0 {
            completeRest()
        }
    }

    private mutating func updatePauseAccounting() {
        guard let pauseStartedAt else { return }
        totalPausedSeconds = Int(now().timeIntervalSince(pauseStartedAt))
    }

    private mutating func startWorkCycle(duration: Int) {
        phase = duration <= 30 ? .preBreak : .working
        remainingSeconds = max(1, duration)
        workDeadline = now().addingTimeInterval(TimeInterval(remainingSeconds))
        restDeadline = nil
        shouldShowOverlay = false
        shouldSendPreBreakNotification = false
        preBreakNotificationSent = duration <= 30 ? false : false
    }

    private mutating func startRest() {
        startRest(kind: nextBreakKind(), sendMissedPreBreakNotification: settings.preBreakNotificationEnabled && !preBreakNotificationSent)
    }

    private mutating func startRest(kind: BreakKind, sendMissedPreBreakNotification: Bool) {
        currentBreakKind = kind
        let duration = currentBreakKind == .short ? settings.shortBreakSeconds : settings.longBreakSeconds
        phase = .resting(currentBreakKind)
        remainingSeconds = duration
        restDeadline = now().addingTimeInterval(TimeInterval(duration))
        workDeadline = nil
        shouldShowOverlay = true
        shouldSendPreBreakNotification = sendMissedPreBreakNotification
        preBreakNotificationSent = false
    }

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

    private mutating func completeRest() {
        switch currentBreakKind {
        case .short:
            todayShortBreaks += 1
        case .long:
            todayLongBreaks += 1
        }
        consecutiveSkips = 0
        shouldShowOverlay = false
        startWorkCycle(duration: settings.workDurationSeconds)
    }

    private func nextBreakKind() -> BreakKind {
        let nextShortCompletion = todayShortBreaks + 1
        if nextShortCompletion > 0 && nextShortCompletion % settings.longBreakFrequency == 0 {
            return .long
        }
        return .short
    }

    private mutating func becomeInactive() {
        phase = .inactive
        remainingSeconds = 0
        shouldShowOverlay = false
        shouldSendPreBreakNotification = false
        workDeadline = nil
        restDeadline = nil
        nextActiveStart = nextStart(after: now())
    }

    private func isActiveTime(_ date: Date) -> Bool {
        guard isActiveDay(date) else { return false }
        let minute = minuteOfDay(for: date)
        guard minute >= settings.activeStartMinute && minute < settings.activeEndMinute else { return false }
        if settings.lunchPauseEnabled && minute >= settings.lunchStartMinute && minute < settings.lunchEndMinute {
            return false
        }
        return true
    }

    private func isActiveDay(_ date: Date) -> Bool {
        switch settings.activeDays {
        case .everyday:
            return true
        case .weekdays:
            let weekday = calendar.component(.weekday, from: date)
            return weekday >= 2 && weekday <= 6
        }
    }

    private func minuteOfDay(for date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func nextStart(after date: Date) -> Date? {
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
