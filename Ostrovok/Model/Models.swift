import Foundation
import SwiftData

enum ThoughtSource: String, Codable, CaseIterable { case typed, voice, paste }
enum TranscriptStatus: String, Codable, CaseIterable { case none, queued, transcribing, done, empty, failed }
enum SessionKind: String, Codable, CaseIterable { case focus, shortBreak, longBreak
    var isBreak: Bool { self != .focus }
}

@Model final class Thought {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var text: String
    var rawTranscript: String?
    var isStarred: Bool
    var sourceRaw: String
    var audioPath: String?
    var audioDuration: Double?
    var transcriptStatusRaw: String
    var focusSession: FocusSession?
    @Relationship(deleteRule: .cascade, inverse: \Attachment.thought) var attachments: [Attachment] = []
    var searchText: String

    init(text: String, source: ThoughtSource, createdAt: Date = .now) {
        self.id = UUID()
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.text = text
        self.isStarred = false
        self.sourceRaw = source.rawValue
        self.transcriptStatusRaw = TranscriptStatus.none.rawValue
        self.searchText = text.lowercased()
    }

    var source: ThoughtSource {
        get { ThoughtSource(rawValue: sourceRaw) ?? .typed }
        set { sourceRaw = newValue.rawValue }
    }
    var transcriptStatus: TranscriptStatus {
        get { TranscriptStatus(rawValue: transcriptStatusRaw) ?? .none }
        set { transcriptStatusRaw = newValue.rawValue }
    }

    func setText(_ new: String) {
        text = new
        updatedAt = .now
        refreshSearch()
    }

    func refreshSearch() {
        searchText = (text + " " + (rawTranscript ?? "")).lowercased()
    }

    var isVoice: Bool { audioPath != nil }
    var audioURL: URL? { audioPath.map { Storage.root.appendingPathComponent($0) } }
    var duringFocus: Bool { focusSession != nil }

    var title: String { ThoughtText.title(text: text, isVoice: isVoice, duration: audioDuration, status: transcriptStatus) }
    var preview: String { ThoughtText.preview(text: text) }
}

@Model final class FocusSession {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var plannedSeconds: Int
    var startedAt: Date
    var endedAt: Date?
    var pausedSeconds: Int
    var completed: Bool
    var untilEventTitle: String?
    @Relationship(deleteRule: .nullify, inverse: \Thought.focusSession) var thoughts: [Thought] = []

    init(id: UUID, kind: SessionKind, plannedSeconds: Int, startedAt: Date, untilEventTitle: String?) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.plannedSeconds = plannedSeconds
        self.startedAt = startedAt
        self.pausedSeconds = 0
        self.completed = false
        self.untilEventTitle = untilEventTitle
    }
    var kind: SessionKind { SessionKind(rawValue: kindRaw) ?? .focus }
}

@Model final class Attachment {
    @Attribute(.unique) var id: UUID
    var path: String
    var createdAt: Date
    var thought: Thought?
    init(path: String) {
        self.id = UUID()
        self.path = path
        self.createdAt = .now
    }
    var url: URL { Storage.root.appendingPathComponent(path) }
}

enum ThoughtText {
    static func title(text: String, isVoice: Bool, duration: Double?, status: TranscriptStatus) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if isVoice { return "Voice · " + Fmt.duration(duration ?? 0) }
            return "Untitled"
        }
        let first = trimmed.components(separatedBy: .newlines).first ?? trimmed
        if first.count <= 60 { return first }
        return String(first.prefix(60)).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func preview(text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = trimmed.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return "" }
        let first = lines.removeFirst()
        var rest = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if first.count > 60 { rest = String(first.dropFirst(60)) + (rest.isEmpty ? "" : "\n" + rest) }
        return rest
    }

    static func isBlank(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum Fmt {
    static func duration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
    static let en = Locale(identifier: "en_US")
    static func shortDate(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = en; f.setLocalizedDateFormatFromTemplate("MMM d")
        return f.string(from: d)
    }
    static func time(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = en; f.dateFormat = "h:mm a"
        return f.string(from: d)
    }
    static func dayHeader(_ d: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        if cal.isDate(d, inSameDayAs: now) { return "Today" }
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(d, inSameDayAs: y) { return "Yesterday" }
        let f = DateFormatter(); f.locale = en
        f.setLocalizedDateFormatFromTemplate(cal.isDate(d, equalTo: now, toGranularity: .year) ? "EEEE, MMMM d" : "MMMM d, yyyy")
        return f.string(from: d)
    }
    static func minutes(_ seconds: Int) -> String { "\(Int((Double(seconds) / 60).rounded())) min" }
}

enum Storage {
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var url = base.appendingPathComponent("Ostrovok", isDirectory: true)
        if let custom = ProcessInfo.processInfo.environment["OSTROVOK_DATA_DIR"] { url = URL(fileURLWithPath: custom, isDirectory: true) }
        for sub in ["", "Audio", "Images", "Models"] {
            try? FileManager.default.createDirectory(at: url.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        return url
    }()
    static var models: URL { root.appendingPathComponent("Models") }

    static func newAudioRelativePath() -> String { "Audio/\(UUID().uuidString).caf" }

    static func saveImage(_ data: Data, ext: String = "png") throws -> String {
        let rel = "Images/\(UUID().uuidString).\(ext)"
        try data.write(to: root.appendingPathComponent(rel), options: .atomic)
        return rel
    }

    static func freeSpace() -> Int64 {
        let v = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage ?? .max
    }
}
