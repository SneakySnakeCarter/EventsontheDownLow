import Foundation
import Combine

@MainActor
final class EventListViewModel: ObservableObject {
    @Published var occurrences: [EventOccurrence] = []

    /// How far ahead notification scheduling looks. This is separate from
    /// what the list displays (see reload() below) — notifications
    /// genuinely need *some* finite bound, since you can't schedule an
    /// unlimited number of them, and NotificationScheduler further caps
    /// the actual number sent to iOS at 60 regardless. The list itself has
    /// no such requirement and is handled without any date ceiling at all
    /// (see nextOccurrenceReload below).
    private let notificationLookaheadDays = 730 // ~2 years

    private let repository = EventRepository.shared

    init() {
        reload()
    }

    func reload() {
        // The list shows exactly one row per event — its next relevant
        // occurrence — with NO date ceiling.
        //
        // HELP DOC NOTE: HELP_DOCUMENTATION_PLAN.md (section 2) flags that
        // showing "next occurrence" rather than one row per day surprised
        // us during development — worth explicitly telling users about it,
        // rather than letting them wonder why the date keeps changing.
        let now = Date()
        let allEvents = repository.fetchAll()
        occurrences = allEvents
            .compactMap { RecurrenceEngine.nextOccurrence(for: $0, onOrAfter: now) }
            .sorted { $0.occurrenceStart < $1.occurrenceStart }

        scheduleNotificationsAcrossWideWindow(events: allEvents, now: now)
    }

    /// Notifications, unlike the list, are scheduled from a wide-but-finite
    /// window — see notificationLookaheadDays above for why that's fine
    /// here even though a hard ceiling was the wrong call for the list.
    private func scheduleNotificationsAcrossWideWindow(events: [CalendarEvent], now: Date) {
        guard let farFuture = Calendar.current.date(byAdding: .day, value: notificationLookaheadDays, to: now) else { return }
        let candidateOccurrences = RecurrenceEngine.occurrences(for: events, in: now, farFuture)
        NotificationScheduler.shared.scheduleNotifications(for: candidateOccurrences)
    }

    func addOrUpdate(_ event: CalendarEvent) {
        repository.save(event)
        reload()
    }

    func delete(_ event: CalendarEvent) {
        guard let id = event.id else { return }
        repository.delete(id: id)
        reload()
    }
}
