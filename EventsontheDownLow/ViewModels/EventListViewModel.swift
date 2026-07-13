import Foundation
import Combine

@MainActor
final class EventListViewModel: ObservableObject {
    @Published var occurrences: [EventOccurrence] = []
    @Published var windowStart: Date
    @Published var windowEnd: Date

    /// Deliberately much wider than the list's own display window — see
    /// NotificationScheduler's doc comment: it caps scheduling at the
    /// soonest 60 candidates across all events, so this just needs to
    /// supply a generous pool for it to pick from, not something tightly
    /// scoped to what's on screen.
    private let notificationLookaheadDays = 730 // ~2 years

    private let repository = EventRepository.shared

    init() {
        let now = Date()
        self.windowStart = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        self.windowEnd = Calendar.current.date(byAdding: .day, value: 60, to: now) ?? now
        reload()
    }

    func reload() {
        let events = repository.fetchEvents(overlapping: windowStart, windowEnd)
        let allOccurrences = RecurrenceEngine.occurrences(for: events, in: windowStart, windowEnd)

        // The list shows one row per event, not one row per day. Collapse
        // to the single most-relevant occurrence per event id.
        //
        // HELP DOC NOTE: HELP_DOCUMENTATION_PLAN.md (section 2) flags that
        // this surprised us during development — worth explicitly telling
        // users the list shows "next occurrence" for recurring events,
        // rather than letting them wonder why the date keeps changing.
        occurrences = Self.collapsedForDisplay(allOccurrences)

        scheduleNotificationsAcrossWideWindow()
    }

    /// Notifications are scheduled from a much wider window than the list
    /// displays — see notificationLookaheadDays above and
    /// NotificationScheduler's doc comment for why.
    private func scheduleNotificationsAcrossWideWindow() {
        let now = Date()
        guard let farFuture = Calendar.current.date(byAdding: .day, value: notificationLookaheadDays, to: now) else { return }
        let notifiableEvents = repository.fetchEvents(overlapping: now, farFuture)
        let candidateOccurrences = RecurrenceEngine.occurrences(for: notifiableEvents, in: now, farFuture)
        NotificationScheduler.shared.scheduleNotifications(for: candidateOccurrences)
    }

    /// Keeps only one EventOccurrence per underlying event id — preferring
    /// the soonest upcoming occurrence, or (if none are upcoming within the
    /// window) the soonest one overall, so recurring events like a daily
    /// medicine reminder show as a single row instead of one per day.
    private static func collapsedForDisplay(_ occurrences: [EventOccurrence]) -> [EventOccurrence] {
        let now = Date()
        var bestByEventId: [Int64: EventOccurrence] = [:]

        for occurrence in occurrences {
            guard let id = occurrence.event.id else { continue }
            guard let existing = bestByEventId[id] else {
                bestByEventId[id] = occurrence
                continue
            }

            let existingIsUpcoming = existing.occurrenceStart >= now
            let candidateIsUpcoming = occurrence.occurrenceStart >= now

            if candidateIsUpcoming && !existingIsUpcoming {
                bestByEventId[id] = occurrence
            } else if candidateIsUpcoming == existingIsUpcoming
                        && occurrence.occurrenceStart < existing.occurrenceStart {
                bestByEventId[id] = occurrence
            }
        }

        return bestByEventId.values.sorted { $0.occurrenceStart < $1.occurrenceStart }
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
