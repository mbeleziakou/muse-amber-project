import Foundation

/// Чистая модель таймера. Хранит `endDate`, а не оставшиеся секунды,
/// поэтому корректна после сна, смены времени и перезапуска.
struct TimerState: Codable, Equatable {
    enum Phase: Codable, Equatable {
        case running(endDate: Date)
        case paused(remaining: TimeInterval)
    }

    var sessionID: UUID
    var kind: SessionKind
    var plannedSeconds: Int
    var startedAt: Date
    var phase: Phase
    var pausedAccumulated: TimeInterval = 0
    var pausedAt: Date?
    var untilEventTitle: String?
    var meetingStart: Date?
    var meetingWarned: Bool = false

    static func start(kind: SessionKind, seconds: Int, now: Date,
                      untilEventTitle: String? = nil, meetingStart: Date? = nil) -> TimerState {
        TimerState(sessionID: UUID(), kind: kind, plannedSeconds: seconds, startedAt: now,
                   phase: .running(endDate: now.addingTimeInterval(TimeInterval(seconds))),
                   untilEventTitle: untilEventTitle, meetingStart: meetingStart)
    }

    var isRunning: Bool { if case .running = phase { return true } else { return false } }
    var isPaused: Bool { !isRunning }

    func remaining(at now: Date) -> TimeInterval {
        switch phase {
        case .running(let end): return max(0, end.timeIntervalSince(now))
        case .paused(let r): return max(0, r)
        }
    }

    func isFinished(at now: Date) -> Bool { isRunning && remaining(at: now) <= 0 }

    /// Доля прошедшего (0…1) относительно запланированного + добавленного времени.
    func progress(at now: Date) -> Double {
        let total = TimeInterval(plannedSeconds)
        guard total > 0 else { return 1 }
        return min(1, max(0, 1 - remaining(at: now) / total))
    }

    mutating func pause(at now: Date) {
        guard case .running = phase else { return }
        phase = .paused(remaining: remaining(at: now))
        pausedAt = now
    }

    mutating func resume(at now: Date) {
        guard case .paused(let r) = phase else { return }
        if let p = pausedAt { pausedAccumulated += now.timeIntervalSince(p) }
        pausedAt = nil
        phase = .running(endDate: now.addingTimeInterval(r))
    }

    mutating func add(seconds: Int) {
        plannedSeconds += seconds
        switch phase {
        case .running(let end): phase = .running(endDate: end.addingTimeInterval(TimeInterval(seconds)))
        case .paused(let r): phase = .paused(remaining: r + TimeInterval(seconds))
        }
    }

    func pausedSeconds(at now: Date) -> Int {
        var total = pausedAccumulated
        if let p = pausedAt { total += now.timeIntervalSince(p) }
        return Int(total)
    }
}

/// Что запускать после завершения фокуса.
enum Cycle {
    static func nextBreak(completedFocusInCycle: Int, longEvery: Int) -> SessionKind {
        guard longEvery > 0 else { return .shortBreak }
        return completedFocusInCycle > 0 && completedFocusInCycle % longEvery == 0 ? .longBreak : .shortBreak
    }

    /// Минуты «фокуса до встречи». nil — встреча слишком скоро (< 10 мин).
    static func minutesUntil(_ start: Date, now: Date) -> Int? {
        let m = Int(start.timeIntervalSince(now) / 60)
        return m >= 10 ? m : nil
    }
}
