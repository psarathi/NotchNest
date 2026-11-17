import AppKit
@preconcurrency import EventKit
import Foundation
import Observation

public enum CalendarAuthState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

@MainActor
@Observable
public final class EventKitService {
    public private(set) var calendarAuth: CalendarAuthState = .notDetermined
    public private(set) var reminderAuth: CalendarAuthState = .notDetermined
    public private(set) var upcomingEvents: [CalendarEventItem] = []

    public var onEventsRefreshed: (([CalendarEventItem]) -> Void)?

    private let store = EKEventStore()
    private var changeObserver: NSObjectProtocol?

    public init() {
        refreshAuthorizationStates()
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshEvents()
            }
        }
    }

    public func refreshAuthorizationStates() {
        calendarAuth = mapStatus(EKEventStore.authorizationStatus(for: .event))
        reminderAuth = mapStatus(EKEventStore.authorizationStatus(for: .reminder))
    }

    public func requestCalendarAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            refreshAuthorizationStates()
            if granted {
                refreshEvents()
            }
            return granted
        } catch {
            refreshAuthorizationStates()
            return false
        }
    }

    public func requestRemindersAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToReminders()
            refreshAuthorizationStates()
            return granted
        } catch {
            refreshAuthorizationStates()
            return false
        }
    }

    public func refreshEvents(now: Date = Date()) {
        refreshAuthorizationStates()
        guard calendarAuth == .authorized else {
            upcomingEvents = []
            return
        }

        let start = Calendar.current.startOfDay(for: now).addingTimeInterval(-3600 * 6)
        let end = Calendar.current.date(byAdding: .day, value: 8, to: start) ?? now.addingTimeInterval(3600 * 24 * 8)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.endDate > start }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay {
                    return !lhs.isAllDay
                }
                return lhs.startDate < rhs.startDate
            }

        upcomingEvents = events.prefix(64).map { event in
            let meetingURL = MeetingLinkExtractor.extractMeetingURL(
                explicitURL: event.url,
                location: event.location,
                notes: event.notes
            )
            return CalendarEventItem(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "Untitled Event",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                calendarTitle: event.calendar.title,
                colorHex: hexString(for: event.calendar.cgColor),
                location: event.location,
                meetingURL: meetingURL
            )
        }
        onEventsRefreshed?(upcomingEvents)
    }

    public func updateTravelTime(minutes: Int, forLocation location: String) {
        let normalizedTarget = location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for idx in upcomingEvents.indices {
            guard let loc = upcomingEvents[idx].location?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  loc == normalizedTarget
            else { continue }
            upcomingEvents[idx].travelTimeMinutes = minutes
        }
    }

    public func fetchRemindersFromNotchNestList() async -> [TaskItem] {
        refreshAuthorizationStates()
        guard reminderAuth == .authorized,
              let list = findOrCreateRemindersList(named: "NotchNest", createIfMissing: false)
        else {
            return []
        }

        let box = EventStoreBox(store: store)
        let listIdentifier = list.calendarIdentifier
        return await Self.fetchReminders(calendarID: listIdentifier, storeBox: box)
    }

    private struct EventStoreBox: @unchecked Sendable {
        let store: EKEventStore
    }

    nonisolated private static func fetchReminders(
        calendarID: String,
        storeBox: EventStoreBox
    ) async -> [TaskItem] {
        guard let targetCalendar = storeBox.store.calendars(for: .reminder).first(where: { $0.calendarIdentifier == calendarID }) else {
            return []
        }
        let predicate = storeBox.store.predicateForReminders(in: [targetCalendar])
        return await withCheckedContinuation { continuation in
            storeBox.store.fetchReminders(matching: predicate) { result in
                let items = (result ?? []).map { reminder in
                    TaskItem(
                        title: reminder.title ?? "Untitled Reminder",
                        isCompleted: reminder.isCompleted,
                        createdAt: reminder.creationDate ?? Date(),
                        completedAt: reminder.completionDate,
                        reminderIdentifier: reminder.calendarItemIdentifier
                    )
                }
                continuation.resume(returning: items)
            }
        }
    }

    @discardableResult
    public func upsertReminder(for task: TaskItem) -> String? {
        guard reminderAuth == .authorized,
              let list = findOrCreateRemindersList(named: "NotchNest", createIfMissing: true)
        else {
            return task.reminderIdentifier
        }

        let reminder: EKReminder
        if let id = task.reminderIdentifier,
           let existing = store.calendarItem(withIdentifier: id) as? EKReminder {
            reminder = existing
        } else {
            reminder = EKReminder(eventStore: store)
            reminder.calendar = list
        }

        reminder.title = task.title
        reminder.isCompleted = task.isCompleted
        reminder.completionDate = task.isCompleted ? (task.completedAt ?? Date()) : nil

        do {
            try store.save(reminder, commit: true)
            return reminder.calendarItemIdentifier
        } catch {
            return task.reminderIdentifier
        }
    }

    public func deleteReminder(identifier: String?) {
        guard reminderAuth == .authorized,
              let identifier,
              let item = store.calendarItem(withIdentifier: identifier) as? EKReminder
        else {
            return
        }
        try? store.remove(item, commit: true)
    }

    private func findOrCreateRemindersList(named title: String, createIfMissing: Bool) -> EKCalendar? {
        let calendars = store.calendars(for: .reminder)
        if let existing = calendars.first(where: { $0.title == title }) {
            return existing
        }
        guard createIfMissing else { return nil }

        let newList = EKCalendar(for: .reminder, eventStore: store)
        newList.title = title
        newList.source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { $0.sourceType == .local || $0.sourceType == .calDAV })
        guard newList.source != nil else { return nil }

        do {
            try store.saveCalendar(newList, commit: true)
            return newList
        } catch {
            return nil
        }
    }

    private func mapStatus(_ status: EKAuthorizationStatus) -> CalendarAuthState {
        switch status {
        case .fullAccess, .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted, .writeOnly:
            return .denied
        @unknown default:
            return .denied
        }
    }

    private func hexString(for cgColor: CGColor?) -> String {
        guard let cgColor,
              let rgb = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB)
        else {
            return "#3B82F6"
        }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
