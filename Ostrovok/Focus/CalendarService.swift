import Foundation
import EventKit
import AppKit
import SwiftUI
import Observation

@MainActor
@Observable
final class CalendarService {
    static let shared = CalendarService()

    struct Event: Identifiable, Equatable {
        var id: String
        var title: String
        var start: Date
        var end: Date
        var color: Color
        var isAllDay: Bool
    }

    private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private(set) var events: [Event] = []
    @ObservationIgnored private let store = EKEventStore()

    private init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    var hasAccess: Bool { status == .fullAccess || status == .authorized }

    func requestAccess() async {
        status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
        }
        status = EKEventStore.authorizationStatus(for: .event)
        reload()
    }

    func reload() {
        status = EKEventStore.authorizationStatus(for: .event)
        guard hasAccess else { events = []; return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let excluded = Prefs.excludedCalendars
        let cals = store.calendars(for: .event).filter { !excluded.contains($0.calendarIdentifier) }
        guard !cals.isEmpty else { events = []; return }
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: cals)
        events = store.events(matching: pred)
            .sorted { $0.startDate < $1.startDate }
            .map { Event(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "Untitled",
                         start: $0.startDate, end: $0.endDate, color: Color(nsColor: $0.calendar.color), isAllDay: $0.isAllDay) }
    }

    var allCalendars: [(id: String, title: String, color: Color)] {
        guard hasAccess else { return [] }
        return store.calendars(for: .event).map { ($0.calendarIdentifier, $0.title, Color(nsColor: $0.color)) }
    }

    func nextMeeting(after now: Date = .now) -> Event? {
        events.first { !$0.isAllDay && $0.start > now }
    }

    static func openPrivacySettings(_ anchor: String = "Privacy_Calendars") {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
