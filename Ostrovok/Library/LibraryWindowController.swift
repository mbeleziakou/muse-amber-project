import AppKit
import SwiftUI
import Observation

@MainActor
@Observable
final class LibraryState {
    static let shared = LibraryState()
    var focusID: UUID?
    var expandedID: UUID?
    var searchFocus = 0
    var newThoughtRequest = 0
}

@MainActor
final class LibraryWindowController: NSObject, NSWindowDelegate {
    static let shared = LibraryWindowController()
    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible ?? false }

    func show(focus id: UUID? = nil) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 760),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Островок"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 520, height: 420)
            w.backgroundColor = .black
            w.appearance = NSAppearance(named: .darkAqua)
            w.contentView = NSHostingView(rootView: LibraryView().modelContainer(DataStore.shared.container))
            w.delegate = self
            w.setFrameAutosaveName("OstrovokLibrary")
            if !w.setFrameUsingName("OstrovokLibrary") { w.center() }
            window = w
        }
        if let id {
            LibraryState.shared.focusID = id
            LibraryState.shared.expandedID = id
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if NotchController.shared.mode == .expanded && !NotchController.shared.pinned {
            NotchController.shared.collapse()
        }
    }

    func toggle() {
        if let w = window, w.isVisible, NSApp.isActive { w.close() } else { show() }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Настройки"
            w.isReleasedWhenClosed = false
            w.appearance = NSAppearance(named: .darkAqua)
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            w.delegate = self
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if !LibraryWindowController.shared.isVisible { NSApp.setActivationPolicy(.accessory) }
    }
}
