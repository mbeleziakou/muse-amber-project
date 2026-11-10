import Foundation
import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let capture = Self("capture", default: .init(.space, modifiers: [.control, .option]))
    static let focus = Self("focus", default: .init(.f, modifiers: [.control, .option]))
    static let library = Self("library", default: .init(.l, modifiers: [.control, .option]))
}

enum DisplayChoice: String, CaseIterable, Identifiable {
    case notch, main, mouse
    var id: String { rawValue }
    var label: String {
        switch self {
        case .notch: "With notch"
        case .main: "Main display"
        case .mouse: "Under cursor"
        }
    }
}

enum Keys {
    static let focusMinutes = "focusMinutes"
    static let shortBreakMinutes = "shortBreakMinutes"
    static let longBreakMinutes = "longBreakMinutes"
    static let longBreakEvery = "longBreakEvery"
    static let autoStartBreak = "autoStartBreak"
    static let sounds = "sounds"
    static let showTimerInWings = "showTimerInWings"
    static let display = "display"
    static let hideInFullscreen = "hideInFullscreen"
    static let excludedCalendars = "excludedCalendars"
    static let hideOnShare = "hideOnShare"
    static let emulateNotch = "emulateNotch"
    static let shortcutOnStart = "shortcutOnStart"
    static let shortcutOnEnd = "shortcutOnEnd"
    static let pinned = "pinned"
    static let timerState = "timerState"
    static let cycleCount = "cycleCount"
    static let cycleDay = "cycleDay"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            focusMinutes: 25,
            shortBreakMinutes: 5,
            longBreakMinutes: 15,
            longBreakEvery: 4,
            autoStartBreak: false,
            sounds: true,
            showTimerInWings: true,
            display: DisplayChoice.notch.rawValue,
            hideInFullscreen: true,
            hideOnShare: false,
            emulateNotch: false,
            shortcutOnStart: "",
            shortcutOnEnd: "",
        ])
    }
}

enum Prefs {
    static var d: UserDefaults { .standard }
    static var focusMinutes: Int { max(1, d.integer(forKey: Keys.focusMinutes)) }
    static var shortBreakMinutes: Int { max(1, d.integer(forKey: Keys.shortBreakMinutes)) }
    static var longBreakMinutes: Int { max(1, d.integer(forKey: Keys.longBreakMinutes)) }
    static var longBreakEvery: Int { max(1, d.integer(forKey: Keys.longBreakEvery)) }
    static var autoStartBreak: Bool { d.bool(forKey: Keys.autoStartBreak) }
    static var sounds: Bool { d.bool(forKey: Keys.sounds) }
    static var showTimerInWings: Bool { d.bool(forKey: Keys.showTimerInWings) }
    static var display: DisplayChoice { DisplayChoice(rawValue: d.string(forKey: Keys.display) ?? "") ?? .notch }
    static var hideInFullscreen: Bool { d.bool(forKey: Keys.hideInFullscreen) }
    static var excludedCalendars: Set<String> { Set(d.stringArray(forKey: Keys.excludedCalendars) ?? []) }
    static var hideOnShare: Bool { d.bool(forKey: Keys.hideOnShare) }
    static var emulateNotch: Bool { d.bool(forKey: Keys.emulateNotch) }
    static var shortcutOnStart: String { d.string(forKey: Keys.shortcutOnStart) ?? "" }
    static var shortcutOnEnd: String { d.string(forKey: Keys.shortcutOnEnd) ?? "" }
}
