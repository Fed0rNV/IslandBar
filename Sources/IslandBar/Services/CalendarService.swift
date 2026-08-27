import AppKit
import Combine
@preconcurrency import EventKit
import Foundation

@MainActor
final class CalendarService: ObservableObject {
    enum AccessState: Equatable {
        case unknown
        case loading
        case granted
        case denied
        case failed(String)
    }

    @Published private(set) var accessState: AccessState = .unknown
    @Published private(set) var events: [DayEvent] = []
    @Published private(set) var reminders: [DayReminder] = []

    private let store = EKEventStore()
    private var changeObserver: NSObjectProtocol?

    init() {
        let eventStatus = EKEventStore.authorizationStatus(for: .event)
        let reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
        if eventStatus == .fullAccess || reminderStatus == .fullAccess {
            accessState = .granted
            load()
        } else if eventStatus == .denied && reminderStatus == .denied {
            accessState = .denied
        }

        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.load() }
        }
    }

    func requestAccess() {
        guard accessState != .loading else { return }
        accessState = .loading

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let eventGranted = try await store.requestFullAccessToEvents()
                let reminderGranted = try await store.requestFullAccessToReminders()
                if eventGranted || reminderGranted {
                    accessState = .granted
                    load()
                } else {
                    accessState = .denied
                }
            } catch {
                accessState = .failed(error.localizedDescription)
            }
        }
    }

    func load() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? Date().addingTimeInterval(604_800)

        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            events = store.events(matching: predicate)
                .sorted { $0.startDate < $1.startDate }
                .prefix(24)
                .map { event in
                    DayEvent(
                        id: event.eventIdentifier ?? UUID().uuidString,
                        title: event.title ?? "Без названия",
                        startDate: event.startDate,
                        endDate: event.endDate,
                        location: event.location,
                        calendarTitle: event.calendar.title,
                        color: NSColor(cgColor: event.calendar.cgColor) ?? .systemBlue,
                        isAllDay: event.isAllDay
                    )
                }
        }

        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: start,
                ending: end,
                calendars: nil
            )
            store.fetchReminders(matching: predicate) { [weak self] values in
                let mapped = (values ?? [])
                    .sorted {
                        ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture)
                    }
                    .prefix(24)
                    .map {
                        DayReminder(
                            id: $0.calendarItemIdentifier,
                            title: $0.title,
                            dueDate: $0.dueDateComponents?.date,
                            calendarTitle: $0.calendar.title,
                            isCompleted: $0.isCompleted
                        )
                    }
                Task { @MainActor in self?.reminders = Array(mapped) }
            }
        }
    }

    func complete(_ item: DayReminder) {
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            load()
        } catch {
            accessState = .failed(error.localizedDescription)
        }
    }

    func addReminder(title: String, dueDate: Date?) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let calendar = store.defaultCalendarForNewReminders() else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = clean
        reminder.calendar = calendar
        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }
        do {
            try store.save(reminder, commit: true)
            load()
        } catch {
            accessState = .failed(error.localizedDescription)
        }
    }
}
