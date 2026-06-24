//
//  BreakTimerEngineTests.swift
//  Eye Break
//
//  职责：BreakTimerEngine 状态机的完整行为测试，覆盖阶段转换、暂停/恢复、跳过、系统离场/返回、活跃时间段边界
//  依赖：TestClock（可变日期桩）、BreakSettings.testDefaults（标准测试配置）
//  被使用：仅由 XCTest 框架自动执行
//

import XCTest
@testable import Eye_Break

@MainActor
final class BreakTimerEngineTests: XCTestCase {
    /// 基准时间：2026-06-22（周一）09:00，标准测试配置的活跃时段起点
    private let mondayMorning = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(identifier: "Asia/Shanghai"), year: 2026, month: 6, day: 22, hour: 9, minute: 0))!

    // MARK: - 阶段转换

    /// 工作阶段 → preBreak 转换
    ///
    /// 逻辑：
    /// 1. 工作时长 20min，当剩余 ≤ 30s 时进入 preBreak 预提醒阶段
    /// 预期：phase == .preBreak，remainingSeconds == 30
    func testTransitionsFromWorkingToPreBreakAtThirtySecondsRemaining() {
        var clock = TestClock(now: mondayMorning)
        var engine = BreakTimerEngine(settings: .testDefaults, now: { clock.now })

        engine.startIfAllowed()
        clock.advance(by: 19 * 60 + 30)
        engine.tick()

        XCTAssertEqual(engine.phase, .preBreak)
        XCTAssertEqual(engine.remainingSeconds, 30)
    }

    /// preBreak → resting 转换，首次为短休息
    ///
    /// 逻辑：
    /// 1. 工作时长归零，自动进入休息
    /// 预期：phase == .resting(.short)，remainingSeconds == 20（短休时长），
    ///       休息触发历史记录 short，但今日完整短休计数仍为 0
    func testTransitionsFromPreBreakToRestingAtZero() {
        var clock = TestClock(now: mondayMorning)
        var engine = BreakTimerEngine(settings: .testDefaults, now: { clock.now })

        engine.startIfAllowed()
        clock.advance(by: 20 * 60)
        engine.tick()

        XCTAssertEqual(engine.phase, .resting(.short))
        XCTAssertEqual(engine.remainingSeconds, 20)
        XCTAssertEqual(engine.todayShortBreaks, 0)
        XCTAssertEqual(engine.stats.restHistory, [.short])
        XCTAssertTrue(engine.shouldShowOverlay)
        XCTAssertTrue(engine.shouldSendPreBreakNotification)
    }

    /// 短休息完成 → 自动进入下一轮工作，并增加完整短休计数
    ///
    /// 逻辑：
    /// 1. 休息倒计时归零，工作周期重启
    /// 预期：phase == .working，remainingSeconds == 20min，shouldShowOverlay == false，
    ///       todayShortBreaks == 1
    func testShortRestCompletionIncrementsCompletedCountAndStartsWork() {
        var clock = TestClock(now: mondayMorning)
        var engine = BreakTimerEngine(settings: .testDefaults, now: { clock.now })

        engine.startIfAllowed()
        clock.advance(by: 20 * 60)
        engine.tick()
        clock.advance(by: 20)
        engine.tick()

        XCTAssertEqual(engine.phase, .working)
        XCTAssertEqual(engine.todayShortBreaks, 1)
        XCTAssertEqual(engine.stats.restHistory, [.short])
        XCTAssertEqual(engine.remainingSeconds, 20 * 60)
        XCTAssertFalse(engine.shouldShowOverlay)
    }

    // MARK: - 休息周期切换

    /// 完成配置的短休息次数后，下一次休息为长休息
    ///
    /// 逻辑：
    /// 1. breakCycleEnabled == true，longBreakFrequency == 3
    /// 2. 完成 3 次短休后，下一轮工作结束触发长休息
    /// 预期：phase == .resting(.long)，时长 3min，长休息只记录到触发历史，完整长休计数仍为 0
    func testLongRestTriggersAfterCompletingConfiguredShortBreaks() {
        var clock = TestClock(now: mondayMorning)
        var engine = BreakTimerEngine(settings: .testDefaults, now: { clock.now })

        for _ in 0..<3 {
            engine.startIfAllowed()
            clock.advance(by: 20 * 60)
            engine.tick()
            clock.advance(by: 20)
            engine.tick()
        }

        clock.advance(by: 20 * 60)
        engine.tick()

        XCTAssertEqual(engine.phase, .resting(.long))
        XCTAssertEqual(engine.remainingSeconds, 3 * 60)
        XCTAssertEqual(engine.todayShortBreaks, 3)
        XCTAssertEqual(engine.todayLongBreaks, 0)
        XCTAssertEqual(engine.stats.restHistory, [.short, .short, .short, .long])
    }

    /// 关闭休息周期开关后所有休息均为短休息
    ///
    /// 逻辑：
    /// 1. breakCycleEnabled == false
    /// 2. 无论执行多少次工作循环
    /// 预期：每次休息类型始终为 .short
    func testDisabledBreakCycleKeepsBreaksShort() {
        var clock = TestClock(now: mondayMorning)
        var settings = BreakSettings.testDefaults
        settings.breakCycleEnabled = false
        var engine = BreakTimerEngine(settings: settings, now: { clock.now })

        for _ in 0..<3 {
            engine.startIfAllowed()
            clock.advance(by: 20 * 60)
            engine.tick()
            clock.advance(by: 20)
            engine.tick()
        }

        clock.advance(by: 20 * 60)
        engine.tick()

        XCTAssertEqual(engine.phase, .resting(.short))
    }

    // MARK: - 暂停 / 恢复

    /// 工作阶段暂停后恢复，剩余时间保持不变
    ///
    /// 逻辑：
    /// 1. 工作 5min 后暂停
    /// 2. 等待 10min（暂停期间不计时）
    /// 3. 恢复后续续工作
    /// 预期：remainingSeconds == 15min（= 20 - 5），totalPausedSeconds == 0
    func testManualPauseAndResumePreservesRemainingTime() {
        var clock = TestClock(now: mondayMorning)
        var engine = BreakTimerEngine(settings: .testDefaults, now: { clock.now })

        engine.startIfAllowed()
        clock.advance(by: 5 * 60)
        engine.tick()
        engine.pause()
        clock.advance(by: 10 * 60)
        engine.tick()
        engine.resume()

        XCTAssertEqual(engine.phase, .working)
        XCTAssertEqual(engine.remainingSeconds, 15 * 60)
        XCTAssertEqual(engine.totalPausedSeconds, 0)
    }

    /// 休息阶段暂停后恢复，倒计时保持不变
    ///
    /// 逻辑：
    /// 1. 进入休息 5s 后暂停
    /// 2. 等待 10min（暂停期间不计时）
    /// 3. 恢复后继续休息
    /// 预期：remainingSeconds == 15（= 20 - 5），shouldShowOverlay == true
    func testManualPauseAndResumePreservesRestCountdown() {
        var clock = TestClock(now: mondayMorning)
        var engine = BreakTimerEngine(settings: .testDefaults, now: { clock.now })

        engine.startIfAllowed()
        clock.advance(by: 20 * 60)
        engine.tick()
        clock.advance(by: 5)
        engine.tick()
        engine.pause()
        clock.advance(by: 10 * 60)
        engine.tick()
        engine.resume()

        XCTAssertEqual(engine.phase, .resting(.short))
        XCTAssertEqual(engine.remainingSeconds, 15)
        XCTAssertTrue(engine.shouldShowOverlay)
    }

    // MARK: - 立即休息

    /// 在工作阶段主动「现在休息一下」立即进入短休息
    ///
    /// 逻辑：
    /// 1. 工作 5min 后调用 startBreakNow
    /// 预期：phase == .resting(.short)，remainingSeconds == 20，
    ///       shouldShowOverlay == true，不触发预提醒通知
    func testStartBreakNowImmediatelyStartsShortRestAndShowsOverlay() {
        var clock = TestClock(now: mondayMorning)
        var engine = BreakTimerEngine(settings: .testDefaults, now: { clock.now })

        engine.startIfAllowed()
        clock.advance(by: 5 * 60)
        engine.tick()
        engine.startBreakNow()

        XCTAssertEqual(engine.phase, .resting(.short))
        XCTAssertEqual(engine.remainingSeconds, 20)
        XCTAssertTrue(engine.shouldShowOverlay)
        XCTAssertFalse(engine.shouldSendPreBreakNotification)
    }

    // MARK: - 跳过休息

    /// 跳过休息后进入工作阶段，累计 consecutiveSkips 并更新 Toast 文案
    ///
    /// 逻辑：
    /// 1. 连续跳过 2 次短休息
    /// 2. engine 记录跳过次数并生成中文 toast
    /// 预期：consecutiveSkips == 2，toast 文案显示"你今天已经跳过 2 次休息了"
    func testSkipStartsNextWorkCycleAndUpdatesMessagingThreshold() {
        var clock = TestClock(now: mondayMorning)
        var engine = BreakTimerEngine(settings: .testDefaults, now: { clock.now })

        engine.startIfAllowed()
        clock.advance(by: 20 * 60)
        engine.tick()
        engine.skipBreak()
        engine.startIfAllowed()
        clock.advance(by: 20 * 60)
        engine.tick()
        engine.skipBreak()

        XCTAssertEqual(engine.phase, .working)
        XCTAssertEqual(engine.todayShortBreaks, 0)
        XCTAssertEqual(engine.stats.restHistory, [.short, .short])
        XCTAssertEqual(engine.consecutiveSkips, 2)
        XCTAssertEqual(engine.lastToastMessage, "你今天已经跳过 2 次休息了")
    }

    /// 跳过的短休息仍计入 shortBreak 次数，用于判断何时触发长休息
    ///
    /// 逻辑：
    /// 1. 跳过 3 次短休息（每次短休到来时 skip，不实际休息）
    /// 2. 第 4 次到达工作周期末尾
    /// 预期：第 4 次为 .long，完整休息计数仍为 0，触发历史记录 short ×3 + long
    func testSkippedShortBreaksCountTowardLongBreakInterval() {
        var clock = TestClock(now: mondayMorning)
        var engine = BreakTimerEngine(settings: .testDefaults, now: { clock.now })

        for _ in 0..<3 {
            engine.startIfAllowed()
            clock.advance(by: 20 * 60)
            engine.tick()
            engine.skipBreak()
        }

        clock.advance(by: 20 * 60)
        engine.tick()

        XCTAssertEqual(engine.phase, .resting(.long))
        XCTAssertEqual(engine.todayShortBreaks, 0)
        XCTAssertEqual(engine.todayLongBreaks, 0)
        XCTAssertEqual(engine.stats.restHistory, [.short, .short, .short, .long])
    }

    /// 跳过长休息后，周期计数器重置，下一次休息为短休息
    ///
    /// 逻辑：
    /// 1. 跳过 3 次短休后触发长休，再跳过该长休
    /// 2. 下一轮工作结束触发休息
    /// 预期：下一轮为 .short（周期已重置），history 记录为 short ×3 + long(跳过) + short
    func testSkippedLongBreakResetsIntervalSoNextBreakIsShort() {
        var clock = TestClock(now: mondayMorning)
        var engine = BreakTimerEngine(settings: .testDefaults, now: { clock.now })

        for _ in 0..<3 {
            engine.startIfAllowed()
            clock.advance(by: 20 * 60)
            engine.tick()
            engine.skipBreak()
        }

        clock.advance(by: 20 * 60)
        engine.tick()
        engine.skipBreak()
        clock.advance(by: 20 * 60)
        engine.tick()

        XCTAssertEqual(engine.phase, .resting(.short))
        XCTAssertEqual(engine.stats.restHistory, [.short, .short, .short, .long, .short])
    }

    // MARK: - 系统离场 / 返回

    /// 工作阶段中短暂锁屏/睡眠（离开时长 < 剩余工作时间），唤醒后直接恢复
    ///
    /// 逻辑：
    /// 1. 工作 5min 后锁屏
    /// 2. 1min 后唤醒（< 15min 剩余）
    /// 预期：remainingSeconds == 15min，无变动
    func testSystemAwayShorterThanRemainingWorkTimeResumesUnchanged() {
        var clock = TestClock(now: mondayMorning)
        var engine = BreakTimerEngine(settings: .testDefaults, now: { clock.now })

        engine.startIfAllowed()
        clock.advance(by: 5 * 60)
        engine.tick()
        engine.systemWillSleepOrLock()
        clock.advance(by: 60)
        engine.systemDidWakeOrUnlock()

        XCTAssertEqual(engine.phase, .working)
        XCTAssertEqual(engine.remainingSeconds, 15 * 60)
    }

    /// 工作阶段中长时间锁屏/睡眠（离开时长 >= 剩余工作时间），重置工作周期
    ///
    /// 逻辑：
    /// 1. 工作 18min 后锁屏（仅剩 2min）
    /// 2. 10min 后唤醒（远超剩余时间）
    /// 预期：remainingSeconds == 20min（重置），shouldShowOverlay == false
    func testSystemAwayLongerThanRemainingWorkTimeResetsWorkCycle() {
        var clock = TestClock(now: mondayMorning)
        var engine = BreakTimerEngine(settings: .testDefaults, now: { clock.now })

        engine.startIfAllowed()
        clock.advance(by: 18 * 60)
        engine.tick()
        engine.systemWillSleepOrLock()
        clock.advance(by: 10 * 60)
        engine.systemDidWakeOrUnlock()

        XCTAssertEqual(engine.phase, .working)
        XCTAssertEqual(engine.remainingSeconds, 20 * 60)
        XCTAssertFalse(engine.shouldShowOverlay)
    }

    /// 休息阶段中锁屏后，离开时间 >= 剩余休息时间，自动完成休息进入工作
    ///
    /// 逻辑：
    /// 1. 进入短休息后立即锁屏
    /// 2. 离开 60s（>= 20s 短休时长）
    /// 预期：唤醒后直接进入 working，休息次数正常记录
    func testSystemAwayDuringRestCountsDownAndStartsNextWorkCycleWhenRestElapsed() {
        var clock = TestClock(now: mondayMorning)
        var engine = BreakTimerEngine(settings: .testDefaults, now: { clock.now })

        engine.startIfAllowed()
        clock.advance(by: 20 * 60)
        engine.tick()
        engine.systemWillSleepOrLock()
        clock.advance(by: 60)
        engine.systemDidWakeOrUnlock()

        XCTAssertEqual(engine.phase, .working)
        XCTAssertEqual(engine.remainingSeconds, 20 * 60)
        XCTAssertFalse(engine.shouldShowOverlay)
        XCTAssertEqual(engine.todayShortBreaks, 1)
    }

    /// 休息阶段中锁屏后，离开时间 < 剩余休息时间，恢复后继续倒计时
    ///
    /// 逻辑：
    /// 1. 进入短休息后立即锁屏
    /// 2. 离开 7s（< 20s 短休时长）
    /// 预期：唤醒后仍为 resting，remainingSeconds == 13，shouldShowOverlay == true
    func testSystemAwayDuringRestResumesRemainingRestWhenNotElapsed() {
        var clock = TestClock(now: mondayMorning)
        var engine = BreakTimerEngine(settings: .testDefaults, now: { clock.now })

        engine.startIfAllowed()
        clock.advance(by: 20 * 60)
        engine.tick()
        engine.systemWillSleepOrLock()
        clock.advance(by: 7)
        engine.systemDidWakeOrUnlock()

        XCTAssertEqual(engine.phase, .resting(.short))
        XCTAssertEqual(engine.remainingSeconds, 13)
        XCTAssertTrue(engine.shouldShowOverlay)
    }

    // MARK: - 重置

    /// 手动重置工作周期：剩余时间回到配置的工作时长
    ///
    /// 逻辑：
    /// 1. 工作 12min 43s 后手动重置
    /// 预期：remainingSeconds == 20min，phase == .working
    func testResetWorkCycleRestartsCountdownFromConfiguredDuration() {
        var clock = TestClock(now: mondayMorning)
        var engine = BreakTimerEngine(settings: .testDefaults, now: { clock.now })

        engine.startIfAllowed()
        clock.advance(by: 12 * 60 + 43)
        engine.tick()
        engine.resetWorkCycle()

        XCTAssertEqual(engine.phase, .working)
        XCTAssertEqual(engine.remainingSeconds, 20 * 60)
    }

    // MARK: - 活跃时间段边界

    /// 在活跃时间段之外引擎处于 inactive 状态，并报告下次开始时间
    ///
    /// 逻辑：
    /// 1. 当前时间 07:00（早于 09:00 开始时间）
    /// 预期：phase == .inactive，nextActiveStart == 09:00
    func testOutsideActiveHoursIsInactiveAndReportsNextStart() {
        let beforeWork = mondayMorning.addingTimeInterval(-2 * 60 * 60)
        let clock = TestClock(now: beforeWork)
        var engine = BreakTimerEngine(settings: .testDefaults, now: { clock.now })

        engine.startIfAllowed()

        XCTAssertEqual(engine.phase, .inactive)
        XCTAssertEqual(engine.nextActiveStart, mondayMorning)
    }

    /// 每天重复只控制日期范围，仍然必须遵守开始/结束时间与午休暂停。
    ///
    /// 逻辑：
    /// 1. activeDays == .everyday
    /// 2. 07:00 早于开始时间，应 inactive
    /// 3. 12:30 落在午休时间，应 inactive
    func testEverydayScheduleStillRespectsActiveWindowAndLunchPause() {
        var settings = BreakSettings.testDefaults
        settings.activeDays = .everyday
        let beforeWork = mondayMorning.addingTimeInterval(-2 * 60 * 60)
        var clock = TestClock(now: beforeWork)
        var engine = BreakTimerEngine(settings: settings, now: { clock.now })

        engine.startIfAllowed()
        XCTAssertEqual(engine.phase, .inactive)
        XCTAssertEqual(engine.nextActiveStart, mondayMorning)

        clock.now = mondayMorning.addingTimeInterval(3 * 60 * 60 + 30 * 60)
        engine.startIfAllowed()
        XCTAssertEqual(engine.phase, .inactive)
    }
}

/// 可变的日期桩，代替真实 Date 实现确定性测试
///
/// 逻辑：
/// 1. 存储当前时间 `now`
/// 2. `advance(by:)` 将 `now` 向前推进指定秒数，模拟时间流逝
/// 3. 配合 `now: { clock.now }` 注入引擎，使所有测试不依赖真实时钟
private struct TestClock {
    var now: Date

    mutating func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

/// 标准测试配置
///
/// - 工作时长：20 分钟
/// - 短休息：20 秒
/// - 长休息：3 分钟
/// - 长休息频率：每 3 次短休后
/// - 活跃时段：工作日 9:00–18:00，午休 12:00–14:00
private extension BreakSettings {
    static var testDefaults: BreakSettings {
        BreakSettings(
            workDurationSeconds: 20 * 60,
            shortBreakSeconds: 20,
            longBreakSeconds: 3 * 60,
            longBreakFrequency: 3,
            breakCycleEnabled: true,
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
}
