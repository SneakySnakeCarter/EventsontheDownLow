import Foundation

struct CalendarEvent: Identifiable, Equatable {
    var id: Int64?              // nil until inserted into SQLite (rowid becomes the id)
    var title: String
    var notes: String?
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var recurrence: RecurrenceRule
    var imageFileName: String?  // filename only; actual file lives in EventImageStore's directory
    /// Minutes before the event's start time to fire a reminder notification.
    /// 0 means "at the event's start time." Empty means no reminders at all.
    /// A user can add as many of these as they want, at any interval.
    var reminderOffsets: [Int]
    var lastModified: Date

    init(
        id: Int64? = nil,
        title: String,
        notes: String? = nil,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        recurrence: RecurrenceRule = RecurrenceRule(),
        imageFileName: String? = nil,
        reminderOffsets: [Int] = [0],
        lastModified: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.recurrence = recurrence
        self.imageFileName = imageFileName
        self.reminderOffsets = reminderOffsets
        self.lastModified = lastModified
    }
}

/// A single concrete occurrence of an event, produced by expanding a
/// recurring CalendarEvent (see RecurrenceEngine). `occurrenceStart`/`occurrenceEnd`
/// differ from the parent event's dates once expanded.
struct EventOccurrence: Identifiable, Equatable {
    var id: String { "\(event.id ?? 0)-\(occurrenceStart.timeIntervalSince1970)" }
    let event: CalendarEvent
    let occurrenceStart: Date
    let occurrenceEnd: Date
}
