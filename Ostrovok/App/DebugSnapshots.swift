#if DEBUG
import AppKit
import SwiftUI

/// Рендерит окно выреза во всех состояниях в PNG (для самопроверки без записи экрана).
@MainActor
enum DebugSnapshots {
    static func run(into dir: String) {
        let c = NotchController.shared
        let f = FocusController.shared
        let store = DataStore.shared
        if store.recent(limit: 1).isEmpty {
            let samples = [
                "Подложку сделать белой и добавить разделитель между блоками\nСайдбар поставить а прогресс бар над ним",
                "Понять 1 / 2 / 3 фичи которые помогут понять ценность",
                "должен быть тайтл денис",
                "Бриф брокеру\nОтправить до пятницы, приложить расчёт",
                "Купить подарок маме 🎁",
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
            ("s2-peek-text", { c.draft = "Позвонить в банк по поводу карты" }),
            ("s3-expanded", { c.draft = ""; c.open(.expanded) }),
            ("s3-calendar", { c.tab = .calendar }),
            ("s5-saved", { c.tab = .recents; c.mode = .saved(UUID()) }),
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
                let target = name == "library" ? NSApp.windows.first(where: { $0.title == "Островок" && !($0 is NotchPanel) })?.contentView : c.panel?.contentView
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
