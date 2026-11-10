import XCTest
@testable import Ostrovok

final class TimerEngineTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testRemainingUsesEndDateAcrossSleep() {
        let s = TimerState.start(kind: .focus, seconds: 25 * 60, now: t0)
        XCTAssertEqual(s.remaining(at: t0), 1500)
        // «Сон» на 10 минут — время считается по endDate.
        XCTAssertEqual(s.remaining(at: t0.addingTimeInterval(600)), 900)
        XCTAssertTrue(s.isFinished(at: t0.addingTimeInterval(1500)))
        XCTAssertEqual(s.remaining(at: t0.addingTimeInterval(9999)), 0)
    }

    func testPauseResumeKeepsRemaining() {
        var s = TimerState.start(kind: .focus, seconds: 600, now: t0)
        s.pause(at: t0.addingTimeInterval(100))
        XCTAssertEqual(s.remaining(at: t0.addingTimeInterval(1000)), 500)
        XCTAssertFalse(s.isFinished(at: t0.addingTimeInterval(5000)))
        s.resume(at: t0.addingTimeInterval(1000))
        XCTAssertEqual(s.remaining(at: t0.addingTimeInterval(1100)), 400)
        XCTAssertEqual(s.pausedSeconds(at: t0.addingTimeInterval(1100)), 900)
    }

    func testAddFiveShiftsEndDate() {
        var s = TimerState.start(kind: .focus, seconds: 600, now: t0)
        s.add(seconds: 300)
        XCTAssertEqual(s.remaining(at: t0), 900)
        XCTAssertEqual(s.plannedSeconds, 900)
        s.pause(at: t0.addingTimeInterval(100))
        s.add(seconds: 300)
        XCTAssertEqual(s.remaining(at: t0.addingTimeInterval(500)), 1100)
    }

    func testProgress() {
        let s = TimerState.start(kind: .focus, seconds: 100, now: t0)
        XCTAssertEqual(s.progress(at: t0), 0, accuracy: 0.001)
        XCTAssertEqual(s.progress(at: t0.addingTimeInterval(50)), 0.5, accuracy: 0.001)
        XCTAssertEqual(s.progress(at: t0.addingTimeInterval(200)), 1, accuracy: 0.001)
    }

    func testCodableRoundTripSurvivesRestart() throws {
        var s = TimerState.start(kind: .shortBreak, seconds: 300, now: t0, untilEventTitle: "Синк", meetingStart: t0.addingTimeInterval(300))
        s.pause(at: t0.addingTimeInterval(10))
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(TimerState.self, from: data)
        XCTAssertEqual(back, s)
        XCTAssertEqual(back.remaining(at: t0.addingTimeInterval(99999)), 290)
    }

    func testCycle() {
        XCTAssertEqual(Cycle.nextBreak(completedFocusInCycle: 1, longEvery: 4), .shortBreak)
        XCTAssertEqual(Cycle.nextBreak(completedFocusInCycle: 4, longEvery: 4), .longBreak)
        XCTAssertEqual(Cycle.nextBreak(completedFocusInCycle: 8, longEvery: 4), .longBreak)
        XCTAssertEqual(Cycle.nextBreak(completedFocusInCycle: 5, longEvery: 4), .shortBreak)
    }

    func testMinutesUntilMeeting() {
        XCTAssertEqual(Cycle.minutesUntil(t0.addingTimeInterval(47 * 60 + 30), now: t0), 47)
        XCTAssertNil(Cycle.minutesUntil(t0.addingTimeInterval(9 * 60), now: t0))
    }
}

final class ThoughtTextTests: XCTestCase {
    func testTitleIsFirstLine() {
        XCTAssertEqual(ThoughtText.title(text: "Купить молоко\nи хлеб", isVoice: false, duration: nil, status: .none), "Купить молоко")
        XCTAssertEqual(ThoughtText.preview(text: "Купить молоко\nи хлеб"), "и хлеб")
    }

    func testLongTitleTruncatedAt60() {
        let long = String(repeating: "а", count: 100)
        let title = ThoughtText.title(text: long, isVoice: false, duration: nil, status: .none)
        XCTAssertEqual(title.count, 61)
        XCTAssertTrue(title.hasSuffix("…"))
        XCTAssertEqual(ThoughtText.preview(text: long).count, 40)
    }

    func testBlank() {
        XCTAssertTrue(ThoughtText.isBlank("  \n\t "))
        XCTAssertFalse(ThoughtText.isBlank(" 😀 "))
    }

    func testCardColorsDeterministicAndNoAdjacentRepeats() {
        let ids = (0..<200).map { _ in UUID() }
        let a = Theme.cardIndices(for: ids), b = Theme.cardIndices(for: ids)
        XCTAssertEqual(a, b)
        for i in 1..<a.count { XCTAssertNotEqual(a[i], a[i - 1]) }
    }

    func testPlural() {
        XCTAssertEqual(Plural.thoughts(1), "1 мысль")
        XCTAssertEqual(Plural.thoughts(3), "3 мысли")
        XCTAssertEqual(Plural.thoughts(11), "11 мыслей")
        XCTAssertEqual(Plural.focuses(22), "22 фокуса")
    }
}
