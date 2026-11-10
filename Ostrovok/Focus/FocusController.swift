import Foundation
import AppKit
import Observation

@MainActor
@Observable
final class FocusController {
    static let shared = FocusController()

    private(set) var state: TimerState?
    var now: Date = .now
    /// Последняя завершённая сессия (для S6 / «Перерыв окончен»).
    var finished: TimerState?
    var meetingSoon = false

    @ObservationIgnored var onFinished: ((TimerState) -> Void)?
    @ObservationIgnored var onMeetingSoon: (() -> Void)?
    @ObservationIgnored private var ticker: Timer?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Keys.timerState),
           let s = try? JSONDecoder().decode(TimerState.self, from: data) {
            state = s
        }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(ticker!, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    var isActive: Bool { state != nil }
    var remaining: TimeInterval { state?.remaining(at: now) ?? 0 }
    var progress: Double { state?.progress(at: now) ?? 0 }
    var kind: SessionKind { state?.kind ?? .focus }

    private func persist() {
        if let s = state, let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: Keys.timerState)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.timerState)
        }
    }

    var currentSession: FocusSession? {
        guard let s = state, s.kind == .focus else { return nil }
        return DataStore.shared.ensureSession(for: s)
    }

    // MARK: Actions

    func startFocus(minutes: Int? = nil, untilEvent: (title: String, start: Date)? = nil) {
        let mins = minutes ?? Prefs.focusMinutes
        var seconds = mins * 60
        if let ev = untilEvent { seconds = max(60, Int(ev.start.timeIntervalSinceNow)) }
        finishCurrent(completed: false)
        state = .start(kind: .focus, seconds: seconds, now: .now,
                       untilEventTitle: untilEvent?.title, meetingStart: untilEvent?.start)
        finished = nil
        _ = DataStore.shared.ensureSession(for: state!)
        persist()
        runShortcut(Prefs.shortcutOnStart)
    }

    func startBreak(_ kind: SessionKind? = nil) {
        let k = kind ?? Cycle.nextBreak(completedFocusInCycle: cycleCount, longEvery: Prefs.longBreakEvery)
        let mins = k == .longBreak ? Prefs.longBreakMinutes : Prefs.shortBreakMinutes
        finishCurrent(completed: false)
        state = .start(kind: k, seconds: mins * 60, now: .now)
        finished = nil
        _ = DataStore.shared.ensureSession(for: state!)
        persist()
    }

    func toggle() {
        guard var s = state else { startFocus(); return }
        if s.isRunning { s.pause(at: .now) } else { s.resume(at: .now) }
        state = s
        persist()
    }

    func addFive() {
        guard var s = state else { return }
        s.add(seconds: 300)
        state = s
        if let fs = DataStore.shared.session(id: s.sessionID) { fs.plannedSeconds = s.plannedSeconds }
        persist()
    }

    func stop() {
        let wasFocus = state?.kind == .focus
        finishCurrent(completed: false)
        state = nil
        persist()
        if wasFocus { runShortcut(Prefs.shortcutOnEnd) }
    }

    func dismissFinished() { finished = nil }

    private func finishCurrent(completed: Bool) {
        guard let s = state else { return }
        let fs = DataStore.shared.ensureSession(for: s)
        fs.endedAt = .now
        fs.completed = completed
        fs.pausedSeconds = s.pausedSeconds(at: .now)
        DataStore.shared.save()
    }

    // MARK: Cycle counter (focus sessions in the current cycle, reset daily)

    private var cycleCount: Int {
        get {
            let day = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
            if UserDefaults.standard.double(forKey: Keys.cycleDay) != day { return 0 }
            return UserDefaults.standard.integer(forKey: Keys.cycleCount)
        }
        set {
            UserDefaults.standard.set(Calendar.current.startOfDay(for: .now).timeIntervalSince1970, forKey: Keys.cycleDay)
            UserDefaults.standard.set(newValue, forKey: Keys.cycleCount)
        }
    }

    // MARK: Tick

    func tick() {
        now = .now
        guard let s = state else { return }
        if s.kind == .focus, let m = s.meetingStart, !s.meetingWarned, m.timeIntervalSince(now) <= 120, m > now {
            state?.meetingWarned = true
            persist()
            Sounds.play(.meeting)
            onMeetingSoon?()
        }
        if s.isFinished(at: now) {
            let fs = DataStore.shared.ensureSession(for: s)
            if case .running(let end) = s.phase { fs.endedAt = min(end, now) } else { fs.endedAt = now }
            fs.completed = true
            fs.pausedSeconds = s.pausedSeconds(at: now)
            DataStore.shared.save()
            state = nil
            finished = s
            persist()
            if s.kind == .focus {
                cycleCount += 1
                Sounds.play(.focusEnd)
                runShortcut(Prefs.shortcutOnEnd)
                if Prefs.autoStartBreak { startBreak(); return }
            } else {
                Sounds.play(.breakEnd)
            }
            onFinished?(s)
        }
    }

    private func runShortcut(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["run", n]
        try? p.run()
    }
}

enum Sounds {
    enum Kind { case focusEnd, breakEnd, meeting, saved }
    static func play(_ k: Kind) {
        guard Prefs.sounds else { return }
        let name: String = switch k {
        case .focusEnd: "Glass"
        case .breakEnd: "Purr"
        case .meeting: "Tink"
        case .saved: "Pop"
        }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
