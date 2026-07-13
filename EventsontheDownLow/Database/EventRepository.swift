import Foundation

/// Repository exposing typed CRUD operations for CalendarEvent, backed by SQLiteDatabase.
final class EventRepository {
    static let shared = EventRepository()
    private let db = SQLiteDatabase.shared

    // MARK: - Create / Update

    @discardableResult
    func save(_ event: CalendarEvent) -> Int64 {
        var event = event
        event.lastModified = Date()

        if let id = event.id {
            if let existing = fetchEvent(id: id) {
                #if DEBUG
                print("EventRepository.save: updating id \(id) — existing.imageFileName='\(existing.imageFileName ?? "nil")' vs new.imageFileName='\(event.imageFileName ?? "nil")'")
                #endif
                if existing.imageFileName != event.imageFileName {
                    EventImageStore.delete(fileName: existing.imageFileName)
                }
            }
            db.run("""
                UPDATE events
                SET title = ?, notes = ?, start_date = ?, end_date = ?,
                    is_all_day = ?, recurrence_rule = ?, image_file_name = ?,
                    reminder_offsets = ?, last_modified = ?
                WHERE id = ?
                """,
                bindings: [
                    event.title, event.notes,
                    event.startDate.timeIntervalSince1970,
                    event.endDate.timeIntervalSince1970,
                    event.isAllDay ? 1 : 0,
                    event.recurrence.toStorageString(),
                    event.imageFileName,
                    Self.encodeReminderOffsets(event.reminderOffsets),
                    event.lastModified.timeIntervalSince1970,
                    id
                ])
            return id
        } else {
            let newId = db.run("""
                INSERT INTO events (title, notes, start_date, end_date, is_all_day, recurrence_rule, image_file_name, reminder_offsets, last_modified)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: [
                    event.title, event.notes,
                    event.startDate.timeIntervalSince1970,
                    event.endDate.timeIntervalSince1970,
                    event.isAllDay ? 1 : 0,
                    event.recurrence.toStorageString(),
                    event.imageFileName,
                    Self.encodeReminderOffsets(event.reminderOffsets),
                    event.lastModified.timeIntervalSince1970
                ])
            return newId
        }
    }

    // MARK: - Read

    /// Fetch all *base* events whose recurrence could plausibly produce an
    /// occurrence inside [rangeStart, rangeEnd]. Non-recurring events are
    /// filtered exactly; recurring events are returned if they could start
    /// on/before rangeEnd (expansion happens in RecurrenceEngine).
    func fetchEvents(overlapping rangeStart: Date, _ rangeEnd: Date) -> [CalendarEvent] {
        let rows = db.query("""
            SELECT * FROM events
            WHERE start_date <= ?
              AND (recurrence_rule != '' OR end_date >= ?)
            ORDER BY start_date ASC
            """,
            bindings: [rangeEnd.timeIntervalSince1970, rangeStart.timeIntervalSince1970])
        return rows.map(Self.mapRow)
    }

    func fetchAll() -> [CalendarEvent] {
        db.query("SELECT * FROM events ORDER BY start_date ASC").map(Self.mapRow)
    }

    func fetchEvent(id: Int64) -> CalendarEvent? {
        db.query("SELECT * FROM events WHERE id = ? LIMIT 1", bindings: [id]).first.map(Self.mapRow)
    }

    // MARK: - Delete

    /// Deletes the entire event, including every future occurrence if it's
    /// recurring — there's no "this occurrence only" option in this app.
    ///
    /// HELP DOC NOTE: HELP_DOCUMENTATION_PLAN.md (section 5) flags this as
    /// something to state explicitly in user-facing help, since some
    /// calendar apps prompt "this event only / all future events" on
    /// delete, and a user coming from one of those could reasonably assume
    /// the same choice exists here.
    func delete(id: Int64) {
        if let existing = fetchEvent(id: id) {
            EventImageStore.delete(fileName: existing.imageFileName)
        }
        db.run("DELETE FROM events WHERE id = ?", bindings: [id])
    }

    // MARK: - Mapping

    private static func mapRow(_ row: [String: Any]) -> CalendarEvent {
        CalendarEvent(
            id: row["id"] as? Int64,
            title: row["title"] as? String ?? "",
            notes: row["notes"] as? String,
            startDate: Date(timeIntervalSince1970: row["start_date"] as? Double ?? 0),
            endDate: Date(timeIntervalSince1970: row["end_date"] as? Double ?? 0),
            isAllDay: (row["is_all_day"] as? Int64 ?? 0) == 1,
            recurrence: RecurrenceRule.fromStorageString(row["recurrence_rule"] as? String ?? ""),
            imageFileName: row["image_file_name"] as? String,
            reminderOffsets: Self.decodeReminderOffsets(row["reminder_offsets"] as? String),
            lastModified: Date(timeIntervalSince1970: row["last_modified"] as? Double ?? 0)
        )
    }

    /// Stores reminder offsets (minutes before start) as a comma-separated
    /// string, e.g. "0,15,1440" for "at start time, 15 min before, and 1
    /// day before." Mirrors the pattern RecurrenceRule uses for its own
    /// single-column string encoding.
    private static func encodeReminderOffsets(_ offsets: [Int]) -> String {
        offsets.map(String.init).joined(separator: ",")
    }

    /// Defaults to [0] (a single "at start time" reminder) both for a
    /// genuinely empty string and for rows from before this column existed
    /// (migrateAddColumnIfNeeded backfills those rows with '0' already, but
    /// this guards against any unexpected empty/malformed value too).
    private static func decodeReminderOffsets(_ stored: String?) -> [Int] {
        guard let stored, !stored.isEmpty else { return [0] }
        let values = stored.split(separator: ",").compactMap { Int($0) }
        return values.isEmpty ? [0] : values
    }
}
