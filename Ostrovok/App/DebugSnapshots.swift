#if DEBUG
import AppKit
import SwiftUI

/// Renders the notch window in every state to PNG (self-check without screen recording).
@MainActor
enum DebugSnapshots {
    static func run(into dir: String) {
        let c = NotchController.shared
        let f = FocusController.shared
        let store = DataStore.shared
        if store.recent(limit: 1).isEmpty {
            let samples = [
                "Make the backdrop white and add a divider between blocks\nMove the progress bar above the sidebar",
                "Pick 1 / 2 / 3 features that prove the value",
                "Denis needs a title here",
                "Brief for the broker\nSend before Friday, attach the numbers",
                "Buy a gift for mom 🎁",
            ]
            for (i, t) in samples.enumerated() {
                let th = store.addThought(text: t, source: .typed, session: nil)
                th.createdAt = Date.now.addingTimeInterval(-Double(i) * 86400)
            }
            store.save()
        }
        let steps: [(String, () -> Void)] = [
            ("s0-idle", { f.stop(); c.collapse() }),
            ("s1-focus", { f.startFocus(minutes: 25); f.tick() }),
            ("s2-peek", { c.open(.peek); c.draft = "" }),
            ("s2-peek-text", { c.draft = "Call the bank about the card" }),
            ("s3-expanded", { c.draft = ""; c.pinned = true; c.open(.expanded) }),
            ("s3-calendar", { c.tab = .calendar }),
            ("s5-saved", { c.pinned = false; c.tab = .recents; c.mode = .saved(UUID()) }),
            ("s6-done", { c.mode = .focusDone }),
            ("s7-break", { c.mode = .idle; f.startBreak(.shortBreak); f.tick() }),
            ("s7-break-prompt", { f.stop(); c.mode = .breakPrompt }),
            ("library", { c.mode = .idle; LibraryWindowController.shared.show() }),
        ]
        var i = 0
        func next() {
            guard i < steps.count else { f.stop(); NSApp.terminate(nil); return }
            let (name, action) = steps[i]; i += 1
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                let target = name == "library" ? NSApp.windows.first(where: { $0.title == "Ostrovok" && !($0 is NotchPanel) })?.contentView : c.panel?.contentView
                if let view = target, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
                    try? rep.representation(using: .png, properties: [:])?.write(to: url)
                }
                next()
            }
        }
        next()
    }
}
#endif
