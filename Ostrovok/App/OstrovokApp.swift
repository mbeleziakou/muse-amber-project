import AppKit
import SwiftUI
import KeyboardShortcuts

@main
enum OstrovokMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Keys.registerDefaults()
        if NSClassFromString("XCTestCase") != nil { return }
        NSApp.mainMenu = Self.makeMenu()
        _ = DataStore.shared
        FocusController.shared.tick()
        NotchController.shared.setup()

        KeyboardShortcuts.onKeyUp(for: .capture) {
            let c = NotchController.shared
            if c.mode == .peek || c.mode == .expanded { c.collapse() } else { c.open(.peek) }
        }
        KeyboardShortcuts.onKeyUp(for: .focus) { FocusController.shared.toggle() }
        KeyboardShortcuts.onKeyUp(for: .library) { LibraryWindowController.shared.toggle() }

        if CalendarService.shared.hasAccess { CalendarService.shared.reload() }
        #if DEBUG
        if let dir = ProcessInfo.processInfo.environment["OSTROVOK_SNAPSHOT_DIR"] { DebugSnapshots.run(into: dir) }
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        LibraryWindowController.shared.show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private static func makeMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let app = NSMenu()
        app.addItem(withTitle: "Настройки…", action: #selector(openSettings), keyEquivalent: ",").target = nil
        app.addItem(.separator())
        app.addItem(withTitle: "Скрыть", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Выйти из Островка", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Правка")
        edit.addItem(withTitle: "Отменить", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Повторить", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Выбрать все", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: "Окно")
        win.addItem(withTitle: "Свернуть", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Закрыть", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winItem.submenu = win
        return main
    }

    @objc func openSettings() { SettingsWindowController.shared.show() }
}
