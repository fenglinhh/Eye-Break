import Foundation

enum BreakKind: String, Codable, Equatable {
    case short
    case long
}

enum BreakPhase: Equatable {
    case inactive
    case working
    case preBreak
    case resting(BreakKind)
    case paused
    case systemAway
    case postponed
}

enum ActiveDays: String, Codable, CaseIterable, Identifiable {
    case weekdays
    case everyday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekdays: "工作日"
        case .everyday: "每天"
        }
    }
}

enum OverlayIntensity: String, Codable, CaseIterable, Identifiable {
    case light
    case medium
    case strong

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "轻度"
        case .medium: "中度"
        case .strong: "强度"
        }
    }

    var opacity: Double {
        switch self {
        case .light: 0.72
        case .medium: 0.84
        case .strong: 0.93
        }
    }
}

struct BreakSettings: Codable, Equatable {
    var workDurationSeconds: Int
    var shortBreakSeconds: Int
    var longBreakSeconds: Int
    var longBreakFrequency: Int
    var activeDays: ActiveDays
    var activeStartMinute: Int
    var activeEndMinute: Int
    var lunchPauseEnabled: Bool
    var lunchStartMinute: Int
    var lunchEndMinute: Int
    var preBreakNotificationEnabled: Bool
    var playSound: Bool
    var showDockReminder: Bool
    var launchAtLogin: Bool
    var menuBarCountdownEnabled: Bool
    var overlayIntensity: OverlayIntensity
    var animationEnabled: Bool
    var healthTipsEnabled: Bool
    var allowSkip: Bool
    var pauseOnLock: Bool
    var resetAfterLongAway: Bool

    static let defaults = BreakSettings(
        workDurationSeconds: 20 * 60,
        shortBreakSeconds: 20,
        longBreakSeconds: 3 * 60,
        longBreakFrequency: 3,
        activeDays: .weekdays,
        activeStartMinute: 9 * 60,
        activeEndMinute: 18 * 60,
        lunchPauseEnabled: true,
        lunchStartMinute: 12 * 60,
        lunchEndMinute: 14 * 60,
        preBreakNotificationEnabled: true,
        playSound: false,
        showDockReminder: false,
        launchAtLogin: false,
        menuBarCountdownEnabled: true,
        overlayIntensity: .medium,
        animationEnabled: true,
        healthTipsEnabled: true,
        allowSkip: true,
        pauseOnLock: true,
        resetAfterLongAway: true
    )
}

struct BreakStats: Codable, Equatable {
    var dayKey: String
    var shortBreaks: Int
    var longBreaks: Int
    var consecutiveSkips: Int

    static func today(calendar: Calendar = .current, now: Date = Date()) -> BreakStats {
        BreakStats(dayKey: Self.dayKey(for: now, calendar: calendar), shortBreaks: 0, longBreaks: 0, consecutiveSkips: 0)
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

struct RestOverlayState: Equatable {
    var kind: BreakKind
    var remainingSeconds: Int
    var totalSeconds: Int
    var advice: String
    var intensity: OverlayIntensity
    var animationEnabled: Bool
}

enum AdviceLibrary {
    static let shortBreakTips = [
        "看看远处，放松眼睛",
        "慢慢眨眼，让眼睛休息一下",
        "放松肩颈",
        "深呼吸一下"
    ]

    static let longBreakTips = [
        "站起来活动一下",
        "喝口水",
        "伸展一下身体",
        "离开屏幕几分钟"
    ]

    static func randomTip(for kind: BreakKind) -> String {
        switch kind {
        case .short: shortBreakTips.randomElement() ?? "看看远处，放松眼睛"
        case .long: longBreakTips.randomElement() ?? "站起来活动一下"
        }
    }
}

func formatDuration(_ seconds: Int) -> String {
    let clamped = max(0, seconds)
    let minutes = clamped / 60
    let seconds = clamped % 60
    return String(format: "%02d:%02d", minutes, seconds)
}
