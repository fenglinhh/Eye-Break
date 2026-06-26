//
//  BreakModels.swift
//  Eye Break
//
//  职责：定义应用中所有数据模型、枚举和状态类型，包含设置持久化所需的所有 Codable 类型
//  依赖：无外部依赖，仅使用 Foundation
//  被使用：Engine 层、ViewModel 层、View 层、Store 层均引用此文件
//

import Foundation

/// 休息类型：短休息 vs 长休息
///
/// 逻辑：
/// 1. breakCycleEnabled 开启时，Engine 按 short→short→long 的 cycle 切换
/// 2. 不同休息类型对应不同的时长、提示文案和叠加层样式
enum BreakKind: String, Codable, Equatable {
    case short
    case long
}

/// 状态机阶段：描述应用从工作到休息再到工作的完整生命周期
///
/// 逻辑：
/// 1. 正常工作 → 预提醒 → 休息中 → 回到工作，形成循环
/// 2. 暂停、锁屏离场、延迟提醒等特殊状态可从任意阶段进入
/// 3. .resting 携带 BreakKind 以区分短/长休息
enum BreakPhase: Equatable {
    case inactive
    case working
    case preBreak
    case resting(BreakKind)
    case paused
    case systemAway
    case postponed
}

/// 活跃天数策略：控制应用在哪些日期运行提醒
///
/// 逻辑：
/// 1. .everyday — 每天运行
/// 2. .weekdays — 仅工作日（周一至周五）
/// 3. .custom — 用户自定义选择星期组合
enum ActiveDays: String, Codable, CaseIterable, Identifiable {
    case everyday
    case weekdays
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyday: "每天"
        case .weekdays: "周一至周五"
        case .custom: "自定义"
        }
    }
}

/// 叠加层不透明度级别：控制休息时屏幕蒙层的透明度
///
/// 逻辑：
/// 1. opacity 值分别为 0.72 / 0.84 / 0.93
/// 2. 强度越大蒙层越不透明，阻挡干扰效果越强
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

/// 用户可配置的全部设置项，通过 UserDefaults 持久化
///
/// 逻辑：
/// 1. 所有时长的单位是秒，时间段的单位是分钟（从 0:00 开始计算的分钟数）
/// 2. custom decoder 用 decodeIfPresent + fallback 实现前向兼容
/// 3. static defaults 作为初始值和 decoder fallback 的双重默认值来源
struct BreakSettings: Codable, Equatable {
    var workDurationSeconds: Int
    var shortBreakSeconds: Int
    var longBreakSeconds: Int
    var longBreakFrequency: Int
    var breakCycleEnabled: Bool
    var activeDays: ActiveDays
    var customActiveWeekdays: Set<Int>
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
        breakCycleEnabled: false,
        activeDays: .everyday,
        customActiveWeekdays: [1, 2, 3, 4, 5, 6, 7],
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

    init(
        workDurationSeconds: Int,
        shortBreakSeconds: Int,
        longBreakSeconds: Int,
        longBreakFrequency: Int,
        breakCycleEnabled: Bool = false,
        activeDays: ActiveDays,
        customActiveWeekdays: Set<Int> = [1, 2, 3, 4, 5, 6, 7],
        activeStartMinute: Int,
        activeEndMinute: Int,
        lunchPauseEnabled: Bool,
        lunchStartMinute: Int,
        lunchEndMinute: Int,
        preBreakNotificationEnabled: Bool,
        playSound: Bool,
        showDockReminder: Bool,
        launchAtLogin: Bool,
        menuBarCountdownEnabled: Bool,
        overlayIntensity: OverlayIntensity,
        animationEnabled: Bool,
        healthTipsEnabled: Bool,
        allowSkip: Bool,
        pauseOnLock: Bool,
        resetAfterLongAway: Bool
    ) {
        self.workDurationSeconds = workDurationSeconds
        self.shortBreakSeconds = shortBreakSeconds
        self.longBreakSeconds = longBreakSeconds
        self.longBreakFrequency = longBreakFrequency
        self.breakCycleEnabled = breakCycleEnabled
        self.activeDays = activeDays
        self.customActiveWeekdays = customActiveWeekdays
        self.activeStartMinute = activeStartMinute
        self.activeEndMinute = activeEndMinute
        self.lunchPauseEnabled = lunchPauseEnabled
        self.lunchStartMinute = lunchStartMinute
        self.lunchEndMinute = lunchEndMinute
        self.preBreakNotificationEnabled = preBreakNotificationEnabled
        self.playSound = playSound
        self.showDockReminder = showDockReminder
        self.launchAtLogin = launchAtLogin
        self.menuBarCountdownEnabled = menuBarCountdownEnabled
        self.overlayIntensity = overlayIntensity
        self.animationEnabled = animationEnabled
        self.healthTipsEnabled = healthTipsEnabled
        self.allowSkip = allowSkip
        self.pauseOnLock = pauseOnLock
        self.resetAfterLongAway = resetAfterLongAway
    }

    /// 自定义解码器：decodeIfPresent + fallback 实现前向兼容
    ///
    /// 逻辑：
    /// 1. 用 decodeIfPresent 尝试读取各字段，缺失时回退到 defaults
    /// 2. 未来版本新增字段时，旧版 JSON 不会造成反序列化失败
    init(from decoder: Decoder) throws {
        let defaults = Self.defaults
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .workDurationSeconds) ?? defaults.workDurationSeconds
        shortBreakSeconds = try container.decodeIfPresent(Int.self, forKey: .shortBreakSeconds) ?? defaults.shortBreakSeconds
        longBreakSeconds = try container.decodeIfPresent(Int.self, forKey: .longBreakSeconds) ?? defaults.longBreakSeconds
        longBreakFrequency = try container.decodeIfPresent(Int.self, forKey: .longBreakFrequency) ?? defaults.longBreakFrequency
        breakCycleEnabled = try container.decodeIfPresent(Bool.self, forKey: .breakCycleEnabled) ?? defaults.breakCycleEnabled
        activeDays = try container.decodeIfPresent(ActiveDays.self, forKey: .activeDays) ?? defaults.activeDays
        customActiveWeekdays = try container.decodeIfPresent(Set<Int>.self, forKey: .customActiveWeekdays) ?? defaults.customActiveWeekdays
        activeStartMinute = try container.decodeIfPresent(Int.self, forKey: .activeStartMinute) ?? defaults.activeStartMinute
        activeEndMinute = try container.decodeIfPresent(Int.self, forKey: .activeEndMinute) ?? defaults.activeEndMinute
        lunchPauseEnabled = try container.decodeIfPresent(Bool.self, forKey: .lunchPauseEnabled) ?? defaults.lunchPauseEnabled
        lunchStartMinute = try container.decodeIfPresent(Int.self, forKey: .lunchStartMinute) ?? defaults.lunchStartMinute
        lunchEndMinute = try container.decodeIfPresent(Int.self, forKey: .lunchEndMinute) ?? defaults.lunchEndMinute
        preBreakNotificationEnabled = try container.decodeIfPresent(Bool.self, forKey: .preBreakNotificationEnabled) ?? defaults.preBreakNotificationEnabled
        playSound = try container.decodeIfPresent(Bool.self, forKey: .playSound) ?? defaults.playSound
        showDockReminder = try container.decodeIfPresent(Bool.self, forKey: .showDockReminder) ?? defaults.showDockReminder
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        menuBarCountdownEnabled = try container.decodeIfPresent(Bool.self, forKey: .menuBarCountdownEnabled) ?? defaults.menuBarCountdownEnabled
        overlayIntensity = try container.decodeIfPresent(OverlayIntensity.self, forKey: .overlayIntensity) ?? defaults.overlayIntensity
        animationEnabled = try container.decodeIfPresent(Bool.self, forKey: .animationEnabled) ?? defaults.animationEnabled
        healthTipsEnabled = try container.decodeIfPresent(Bool.self, forKey: .healthTipsEnabled) ?? defaults.healthTipsEnabled
        allowSkip = try container.decodeIfPresent(Bool.self, forKey: .allowSkip) ?? defaults.allowSkip
        pauseOnLock = try container.decodeIfPresent(Bool.self, forKey: .pauseOnLock) ?? defaults.pauseOnLock
        resetAfterLongAway = try container.decodeIfPresent(Bool.self, forKey: .resetAfterLongAway) ?? defaults.resetAfterLongAway
    }
}

/// 每日统计数据：追踪当日完整完成的休息次数、连续跳过次数和休息触发历史
///
/// 逻辑：
/// 1. dayKey 是 "年-月-日" 字符串，用于跨天检测并自动归零
/// 2. shortBreaks / longBreaks 只记录完整完成的休息，用于菜单展示
/// 3. restHistory 记录完成和跳过都会产生的触发序列，用于决定下一次休息类型
/// 4. consecutiveSkips 累积连续跳过次数，影响跳过时的提示文案
struct BreakStats: Codable, Equatable {
    var dayKey: String
    var shortBreaks: Int
    var longBreaks: Int
    var consecutiveSkips: Int
    var restHistory: [BreakKind]

    init(dayKey: String, shortBreaks: Int, longBreaks: Int, consecutiveSkips: Int, restHistory: [BreakKind] = []) {
        self.dayKey = dayKey
        self.shortBreaks = shortBreaks
        self.longBreaks = longBreaks
        self.consecutiveSkips = consecutiveSkips
        self.restHistory = restHistory
    }

    /// 生成当日零值统计数据（用于新的一天首次初始化）
    static func today(calendar: Calendar = .current, now: Date = Date()) -> BreakStats {
        BreakStats(dayKey: Self.dayKey(for: now, calendar: calendar), shortBreaks: 0, longBreaks: 0, consecutiveSkips: 0)
    }

    /// 根据日期生成 dayKey：以年月日字符串作为每日 ID
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let today = Self.today()
        dayKey = try container.decodeIfPresent(String.self, forKey: .dayKey) ?? today.dayKey
        shortBreaks = try container.decodeIfPresent(Int.self, forKey: .shortBreaks) ?? today.shortBreaks
        longBreaks = try container.decodeIfPresent(Int.self, forKey: .longBreaks) ?? today.longBreaks
        consecutiveSkips = try container.decodeIfPresent(Int.self, forKey: .consecutiveSkips) ?? today.consecutiveSkips
        restHistory = try container.decodeIfPresent([BreakKind].self, forKey: .restHistory) ?? []
    }
}

/// 休息叠加层的不可变快照：RestOverlayController 据此渲染全屏蒙层
///
/// 逻辑：
/// 1. 这是一个纯数据值类型，由 ViewModel 在阶段转换时创建并传递给 Controller
/// 2. 包含蒙层所需的一切 UI 参数：倒计时、提示文案、不透明度、动画开关
struct RestOverlayState: Equatable {
    var kind: BreakKind
    var remainingSeconds: Int
    var totalSeconds: Int
    var advice: String
    var intensity: OverlayIntensity
    var animationEnabled: Bool
}

/// 健康小贴士库：根据休息类型随机返回一条中文提示
///
/// 逻辑：
/// 1. shortBreakTips 偏向眼睛放松和深呼吸
/// 2. longBreakTips 鼓励起身活动、喝水、伸展
/// 3. randomElement() + ?? 双重保障确保总有返回值
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

/// 格式化时长：将秒数转为 "MM:SS" 字符串
///
/// 逻辑：
/// 1. 输入 < 0 时取 0，确保不出现负值
/// 2. 用 String(format:) 保证两位数填充
func formatDuration(_ seconds: Int) -> String {
    let clamped = max(0, seconds)
    let minutes = clamped / 60
    let seconds = clamped % 60
    return String(format: "%02d:%02d", minutes, seconds)
}
