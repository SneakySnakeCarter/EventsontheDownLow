import Foundation

/// Expands CalendarEvent + RecurrenceRule into concrete EventOccurrence
/// instances that fall within a given date window. Kept separate from
/// storage so the same logic can run in the UI layer and in a background task.
enum RecurrenceEngine {

    static func occurrences(
        for event: CalendarEvent,
        in windowStart: Date,
        _ windowEnd: Date,
        calendar: Calendar = .current
    ) -> [EventOccurrence] {
        let duration = event.endDate.timeIntervalSince(event.startDate)
        guard event.recurrence.isRecurring else {
            // Non-recurring: include only if it overlaps the window at all.
            if event.endDate >= windowStart && event.startDate <= windowEnd {
                return [EventOccurrence(event: event, occurrenceStart: event.startDate, occurrenceEnd: event.endDate)]
            }
            return []
        }

        var results: [EventOccurrence] = []
        var occurrenceCount = 0
        var cursor = event.startDate
        let hardStop = event.recurrence.until.map { min($0, windowEnd) } ?? windowEnd
        let maxIterations = 10_000 // safety valve against malformed rules

        var iterations = 0
        while cursor <= hardStop && iterations < maxIterations {
            iterations += 1

            if let count = event.recurrence.count, occurrenceCount >= count {
                break
            }

            let candidates = weekdayCandidates(for: cursor, rule: event.recurrence, calendar: calendar)
            for candidateStart in candidates {
                if let count = event.recurrence.count, occurrenceCount >= count { break }
                guard candidateStart >= event.startDate, candidateStart <= hardStop else { continue }

                let candidateEnd = candidateStart.addingTimeInterval(duration)
                if candidateEnd >= windowStart && candidateStart <= windowEnd {
                    results.append(EventOccurrence(event: event, occurrenceStart: candidateStart, occurrenceEnd: candidateEnd))
                }
                occurrenceCount += 1
            }

            guard let next = advance(cursor, rule: event.recurrence, calendar: calendar) else { break }
            cursor = next
        }

        return results
    }

    /// Expands and merges occurrences for a whole list of events (e.g. all events
    /// loaded from the repository) within a window, sorted by start time.
    static func occurrences(
        for events: [CalendarEvent],
        in windowStart: Date,
        _ windowEnd: Date,
        calendar: Calendar = .current
    ) -> [EventOccurrence] {
        events
            .flatMap { occurrences(for: $0, in: windowStart, windowEnd, calendar: calendar) }
            .sorted { $0.occurrenceStart < $1.occurrenceStart }
    }

    // MARK: - Private stepping helpers

    /// For weekly rules with specific weekdays, returns each matching weekday
    /// within the current period anchored at `date`. For all other frequencies,
    /// returns just [date].
    private static func weekdayCandidates(for date: Date, rule: RecurrenceRule, calendar: Calendar) -> [Date] {
        guard rule.frequency == .weekly, !rule.byWeekday.isEmpty else { return [date] }

        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [date] }
        let timeOfDay = calendar.dateComponents([.hour, .minute, .second], from: date)

        return rule.byWeekday.compactMap { weekday -> Date? in
            var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekInterval.start)
            comps.weekday = weekday
            comps.hour = timeOfDay.hour
            comps.minute = timeOfDay.minute
            comps.second = timeOfDay.second
            return calendar.date(from: comps)
        }.sorted()
    }

    /// Advances the cursor by one recurrence period (respecting `interval`).
    private static func advance(_ date: Date, rule: RecurrenceRule, calendar: Calendar) -> Date? {
        switch rule.frequency {
        case .none:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: rule.interval, to: date)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: rule.interval, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: rule.interval, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: rule.interval, to: date)
        }
    }
}
