import Foundation
import UserNotifications

/// Schedules local notifications for expanded event occurrences.
/// Runs both from the foreground (when the user adds/edits an event) and
/// from BackgroundTaskManager's periodic refresh.
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    /// Must match UNNotificationExtensionCategory in the
    /// NotificationContentExtension target's Info.plist exactly.
    static let photoCategoryIdentifier = "EVENT_WITH_PHOTO"

    private init() {}

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            completion?(granted)
        }
        registerCategories()
    }

    /// Registers the category used to route photo notifications to the
    /// custom NotificationContentExtension UI. No actions/buttons needed —
    /// this category exists purely to opt into the custom expanded layout.
    private func registerCategories() {
        let photoCategory = UNNotificationCategory(
            identifier: Self.photoCategoryIdentifier,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([photoCategory])
    }

    /// Schedules a notification for every reminder configured on each event
    /// (event.reminderOffsets — minutes before start; 0 = at start time).
    /// A user can add as many reminders as they want, at any interval, so
    /// this fires one independent notification per (occurrence, offset)
    /// pair. Existing pending requests for the same events are cleared
    /// first so re-running this doesn't create duplicates.
    ///
    /// HELP DOC NOTE: HELP_DOCUMENTATION_PLAN.md (section 4) should mention
    /// that reminders are fully user-configurable per event now, rather
    /// than the previous fixed "always at start time" behavior.
    ///
    /// STAYING UNDER iOS'S 64-PENDING-NOTIFICATION CAP:
    /// Rather than trying to schedule everything within some fixed lookahead
    /// window (which many reminders × many recurring occurrences could
    /// easily exceed), this only ever schedules the soonest
    /// `maxPendingNotifications` candidates across *all* events combined,
    /// leaving headroom under Apple's actual limit. As the soonest ones
    /// fire and drop off the pending list, they aren't "refilled" by any
    /// special bookkeeping here — instead, the next time this function runs
    /// (on app open via EventListViewModel.reload(), or via
    /// BackgroundTaskManager's periodic refresh task), it recomputes the
    /// full candidate list fresh and naturally pulls in whatever's now
    /// soonest to fill the gap. This only works if callers pass in a wide
    /// enough candidate window that there's always something to pull in —
    /// see BackgroundTaskManager/EventListViewModel, which both fetch
    /// occurrences far into the future (not just the ~60 days the on-screen
    /// list itself displays) specifically to feed this function generously.
    func scheduleNotifications(for occurrences: [EventOccurrence]) {
        let center = UNUserNotificationCenter.current()
        let eventIds = Set(occurrences.compactMap { $0.event.id })

        center.getPendingNotificationRequests { requests in
            let idsToRemove = requests
                .map(\.identifier)
                .filter { identifier in eventIds.contains { "event-\($0)-" == String(identifier.prefix("event-\($0)-".count)) } }
            center.removePendingNotificationRequests(withIdentifiers: idsToRemove)

            let now = Date()
            let candidates: [ReminderCandidate] = occurrences.flatMap { occurrence -> [ReminderCandidate] in
                guard let eventId = occurrence.event.id else { return [] }
                return occurrence.event.reminderOffsets.compactMap { offsetMinutes -> ReminderCandidate? in
                    let fireDate = occurrence.occurrenceStart.addingTimeInterval(-Double(offsetMinutes) * 60)
                    guard fireDate > now else { return nil }
                    return ReminderCandidate(occurrence: occurrence, eventId: eventId, offsetMinutes: offsetMinutes, fireDate: fireDate)
                }
            }

            let toSchedule = candidates
                .sorted { $0.fireDate < $1.fireDate }
                .prefix(Self.maxPendingNotifications)

            for candidate in toSchedule {
                self.schedule(candidate, center: center)
            }

            #if DEBUG
            if candidates.count > Self.maxPendingNotifications {
                print("NotificationScheduler: \(candidates.count) reminder(s) were due in the future; only scheduling the soonest \(Self.maxPendingNotifications) to stay under iOS's cap. The rest will be picked up on the next scheduling pass as these fire.")
            }
            #endif
        }
    }

    /// One (occurrence, reminder offset) pair with its computed fire date —
    /// the unit this scheduler sorts and caps by.
    private struct ReminderCandidate {
        let occurrence: EventOccurrence
        let eventId: Int64
        let offsetMinutes: Int
        let fireDate: Date
    }

    /// Leaves a small buffer under Apple's actual 64-pending-notification
    /// limit, in case something else in the system (or a future feature in
    /// this app) also schedules local notifications.
    private static let maxPendingNotifications = 60

    private func schedule(_ candidate: ReminderCandidate, center: UNUserNotificationCenter) {
        let occurrence = candidate.occurrence
        let eventId = candidate.eventId
        let offsetMinutes = candidate.offsetMinutes

        let content = UNMutableNotificationContent()
        content.title = occurrence.event.title
        // "Starting at [time]" is only informative when the reminder fires
        // *before* the event — if it fires exactly at start time, "Starting
        // now" already says everything, and appending the time again reads
        // redundantly (e.g. "Starting now — starting at 3:49 PM").
        var body: String
        if offsetMinutes <= 0 {
            body = Self.timingPhrase(forOffsetMinutes: offsetMinutes)
        } else {
            body = "\(Self.timingPhrase(forOffsetMinutes: offsetMinutes)) — starting at \(Self.formatter.string(from: occurrence.occurrenceStart))"
        }
        if let notes = occurrence.event.notes,
           !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body += "\n\n\(notes)"
        }
        content.body = body
        content.sound = .default

        if let imageURL = EventImageStore.url(for: occurrence.event.imageFileName) {
            do {
                // IMPORTANT: never hand UNNotificationAttachment the permanent
                // file directly — the system can take ownership of (move/
                // consume) the source URL, which would silently delete our
                // real copy out from under EventImageStore. Always attach a
                // fresh disposable temp copy — one per notification, since a
                // single temp file shared across multiple reminders could be
                // consumed by the first attachment and missing for the rest.
                let tempURL = try Self.makeDisposableCopy(of: imageURL, identifier: "event-image-\(eventId)-\(offsetMinutes)")
                let attachment = try UNNotificationAttachment(
                    identifier: "event-image-\(eventId)-\(offsetMinutes)",
                    url: tempURL,
                    options: nil
                )
                content.attachments = [attachment]
                // Routes this notification to the NotificationContentExtension
                // (see Xcode setup steps) for a full-size expanded image
                // instead of the OS's default modest-sized preview.
                content.categoryIdentifier = Self.photoCategoryIdentifier
            } catch {
                #if DEBUG
                print("Failed to attach event image to notification: \(error)")
                #endif
            }
        }

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: candidate.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        // Includes the offset so each reminder for the same occurrence gets
        // its own distinct identifier.
        let identifier = "event-\(eventId)-\(Int(occurrence.occurrenceStart.timeIntervalSince1970))-\(offsetMinutes)"

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }

    /// Human-readable description of a reminder's timing relative to the
    /// event, e.g. "Starting now", "15 minutes before", "2 hours before",
    /// "1 day before".
    private static func timingPhrase(forOffsetMinutes offsetMinutes: Int) -> String {
        if offsetMinutes <= 0 {
            return "Starting now"
        }
        if offsetMinutes % 1440 == 0 {
            let days = offsetMinutes / 1440
            return "\(days) day\(days == 1 ? "" : "s") before"
        }
        if offsetMinutes % 60 == 0 {
            let hours = offsetMinutes / 60
            return "\(hours) hour\(hours == 1 ? "" : "s") before"
        }
        return "\(offsetMinutes) minute\(offsetMinutes == 1 ? "" : "s") before"
    }

    /// Copies a file into the system temp directory under a fresh unique
    /// name, so a UNNotificationAttachment never points at (and can never
    /// consume) our permanent EventImageStore copy.
    private static func makeDisposableCopy(of sourceURL: URL, identifier: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let destURL = tempDir.appendingPathComponent("\(identifier)-\(UUID().uuidString).\(sourceURL.pathExtension)")
        try? FileManager.default.removeItem(at: destURL) // just in case; shouldn't normally exist
        try FileManager.default.copyItem(at: sourceURL, to: destURL)
        #if DEBUG
        print("NotificationScheduler: made disposable temp copy at \(destURL.path) (source untouched: \(sourceURL.path))")
        #endif
        return destURL
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.calendar = .autoupdatingCurrent
        f.timeZone = .autoupdatingCurrent
        // Deliberately plain .dateStyle/.timeStyle — see the matching
        // comment on EventRowView's singleFormatter for why the
        // template-based "j" approach was reverted (confirmed Apple bug
        // where it ignores the Language & Region "Date Format" setting).
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}
