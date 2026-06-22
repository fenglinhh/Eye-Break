import XCTest
@testable import Eye_Break

@MainActor
final class BreakTimerEngineTests: XCTestCase {
    private let mondayMorning = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(identifier: "Asia/Shanghai"), year: 2026, month: 6, day: 22, hour: 9, minute: 0))!

    func testTransitionsFromWorkingToPreBreakAtThirtySecondsRemaining() {
        var clock = TestClock(now: mondayMorning)
        var engine = BreakTimerEngine(settings: .testDefaults, now: { clock.now })

        engine.startIfAllowed()
        clock.advance(by: 19 * 60 + 30)
        engine.tick()

        XCTAssertEqual(engine.phase, .preBreak)
        XCTAssertEqual(engine.remainingSeconds, 30)
    }

    func testTransitionsFromPreBreakToRestingAtZero() {
        var clock = TestClock(now: mondayMorning)
        var engine = BreakTimerEngine(settings: .testDefaults, now: { clock.now })

        engine.startIfAllowed()
        clock.advance(by: 20 * 60)
        engine.tick()

        XCTAssertEqual(engine.phase, .resting(.short))
        XCTAssertEqual(engine.remainingSeconds, 20)
        XCTAssertTrue(engine.shouldShowOverlay)
        XCTAssertTrue(engine.shouldSendPreBreakNotification)
    }

    func testShortRestCompletionIncrementsCountAndStartsWork() {
        var clock = TestClock(now: mondayMorning)
        var engine = BreakTimerEngine(settings: .testDefaults, now: { clock.now })

        engine.startIfAllowed()
        clock.advance(by: 20 * 60)
        engine.tick()
        clock.advance(by: 20)
        engine.tick()

        XCTAssertEqual(engine.phase, .working)
        XCTAssertEqual(engine.todayShortBreaks, 1)
        XCTAssertEqual(engine.remainingSeconds, 20 * 60)
        XCTAssertFalse(engine.shouldShowOverlay)
    }

    func testEveryThirdShortBreakTriggersLongRest() {
        var clock = TestClock(now: mondayMorning)
        var engine = BreakTimerEngine(settings: .testDefaults, now: { clock.now })

        for _ in 0..<2 {
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
    }

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
        XCTAssertEqual(engine.consecutiveSkips, 2)
        XCTAssertEqual(engine.lastToastMessage, "你今天已经跳过 2 次休息了")
    }

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

    func testSystemAwayLongerThanRemainingWorkTimeResumesUnchanged() {
        var clock = TestClock(now: mondayMorning)
        var engine = BreakTimerEngine(settings: .testDefaults, now: { clock.now })

        engine.startIfAllowed()
        clock.advance(by: 18 * 60)
        engine.tick()
        engine.systemWillSleepOrLock()
        clock.advance(by: 10 * 60)
        engine.systemDidWakeOrUnlock()

        XCTAssertEqual(engine.phase, .working)
        XCTAssertEqual(engine.remainingSeconds, 2 * 60)
        XCTAssertFalse(engine.shouldShowOverlay)
    }

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

    func testOutsideActiveHoursIsInactiveAndReportsNextStart() {
        let beforeWork = mondayMorning.addingTimeInterval(-2 * 60 * 60)
        let clock = TestClock(now: beforeWork)
        var engine = BreakTimerEngine(settings: .testDefaults, now: { clock.now })

        engine.startIfAllowed()

        XCTAssertEqual(engine.phase, .inactive)
        XCTAssertEqual(engine.nextActiveStart, mondayMorning)
    }
}

private struct TestClock {
    var now: Date

    mutating func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

private extension BreakSettings {
    static var testDefaults: BreakSettings {
        BreakSettings(
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
}
