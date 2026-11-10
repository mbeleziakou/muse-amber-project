import Foundation
import SwiftData
import AppKit

@MainActor
final class DataStore {
    static let shared = DataStore()
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    private init() {
        let url = Storage.root.appendingPathComponent("Ostrovok.store")
        let config = ModelConfiguration(url: url)
        do {
            container = try ModelContainer(for: Thought.self, FocusSession.self, Attachment.self, configurations: config)
        } catch {
            NSLog("Ostrovok store error: \(error)")
            container = try! ModelContainer(for: Thought.self, FocusSession.self, Attachment.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        container.mainContext.autosaveEnabled = true
    }

    func save() {
        do { try context.save() } catch { NSLog("Ostrovok save error: \(error)") }
    }

    // MARK: Thoughts

    @discardableResult
    func addThought(text: String, source: ThoughtSource, images: [Data] = [], session: FocusSession?) -> Thought {
        let t = Thought(text: text, source: source)
        t.focusSession = session
        context.insert(t)
        for data in images {
            if let rel = try? Storage.saveImage(data) {
                let a = Attachment(path: rel)
                context.insert(a)
                a.thought = t
            }
        }
        save()
        return t
    }

    func addImages(_ images: [Data], to t: Thought) {
        for data in images {
            if let rel = try? Storage.saveImage(data) {
                let a = Attachment(path: rel)
                context.insert(a)
                a.thought = t
            }
        }
        t.updatedAt = .now
        save()
    }

    func delete(_ t: Thought) {
        var files = t.attachments.map(\.url)
        if let a = t.audioURL { files.append(a) }
        context.delete(t)
        save()
        for f in files { try? FileManager.default.removeItem(at: f) }
    }

    func thought(id: UUID) -> Thought? {
        var d = FetchDescriptor<Thought>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    func recent(limit: Int) -> [Thought] {
        var d = FetchDescriptor<Thought>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        d.fetchLimit = limit
        return (try? context.fetch(d)) ?? []
    }

    // MARK: Focus sessions

    func session(id: UUID) -> FocusSession? {
        var d = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    func ensureSession(for s: TimerState) -> FocusSession {
        if let existing = session(id: s.sessionID) { return existing }
        let fs = FocusSession(id: s.sessionID, kind: s.kind, plannedSeconds: s.plannedSeconds,
                              startedAt: s.startedAt, untilEventTitle: s.untilEventTitle)
        context.insert(fs)
        save()
        return fs
    }

    struct DayStats { var focusCount: Int; var focusSeconds: Int; var thoughtsInFocus: Int }

    func todayStats(now: Date = .now) -> DayStats {
        let start = Calendar.current.startOfDay(for: now)
        let focus = SessionKind.focus.rawValue
        let d = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.startedAt >= start && $0.kindRaw == focus && $0.completed })
        let sessions = (try? context.fetch(d)) ?? []
        let secs = sessions.reduce(0) { acc, s in
            let end = s.endedAt ?? now
            return acc + max(0, Int(end.timeIntervalSince(s.startedAt)) - s.pausedSeconds)
        }
        let tq = FetchDescriptor<Thought>(predicate: #Predicate { $0.createdAt >= start && $0.focusSession != nil })
        let n = (try? context.fetchCount(tq)) ?? 0
        return DayStats(focusCount: sessions.count, focusSeconds: secs, thoughtsInFocus: n)
    }

    // MARK: Export

    static func markdown(for t: Thought) -> String {
        let iso = ISO8601DateFormatter()
        var out = "---\ncreated: \(iso.string(from: t.createdAt))\n"
        if t.isStarred { out += "starred: true\n" }
        if t.duringFocus { out += "focus: true\n" }
        if let d = t.audioDuration { out += "audio_duration: \(Int(d))\n" }
        out += "---\n\n"
        out += t.text.isEmpty ? "# \(t.title)\n" : t.text + "\n"
        if let a = t.audioURL { out += "\n![audio](\(a.path))\n" }
        for att in t.attachments { out += "\n![](\(att.url.path))\n" }
        return out
    }

    static func fileName(for t: Thought) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let title = t.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return "\(f.string(from: t.createdAt)) \(title.prefix(40)).md"
    }

    func exportAll(to folder: URL) throws -> Int {
        let all = (try? context.fetch(FetchDescriptor<Thought>())) ?? []
        for t in all {
            try Self.markdown(for: t).write(to: folder.appendingPathComponent(Self.fileName(for: t)), atomically: true, encoding: .utf8)
        }
        return all.count
    }

    func export(_ t: Thought) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Self.fileName(for: t)
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            try? Self.markdown(for: t).write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
