import Foundation
import BackgroundTasks
import UIKit

/// Registers and schedules two BGTaskScheduler tasks:
///  1. A periodic "app refresh" task that expands upcoming recurring events
///     across a wide lookahead window and hands them to NotificationScheduler,
///     which schedules only the soonest 60 to stay under iOS's pending cap
///     (see NotificationScheduler's doc comment for the full strategy).
///  2. A longer-running "processing" task (e.g. nightly) that prunes old
///     data and rebuilds any cached occurrence tables.
///
/// IMPORTANT setup steps (do these in Xcode, not code):
///  - Target > Signing & Capabilities > "+ Capability" > Background Modes
///      check "Background fetch" and "Background processing"
///  - Info.plist: add key `BGTaskSchedulerPermittedIdentifiers` (Array) with
///      the two identifier strings below.
final class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()

    static let refreshTaskIdentifier = "com.eventsonthedownlow.refresh"
    static let processingTaskIdentifier = "com.eventsonthedownlow.processing"

    /// How far ahead to generate candidate occurrences for notification
    /// scheduling — deliberately wide (not just a few weeks), since
    /// NotificationScheduler itself caps the actual number scheduled at 60
    /// (the soonest ones across all events). A wide candidate pool is what
    /// lets that count-based cap "top up" correctly on each run rather than
    /// running dry once the near-term window is exhausted for something
    /// like a never-ending daily reminder with multiple reminders per day.
    private let notificationLookaheadDays = 730 // ~2 years

    private init() {}

    /// Call once from the App's init or `didFinishLaunching`.
    func registerTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskIdentifier,
            using: nil
        ) { task in
            // Guarded rather than force-cast: in the expected case this
            // always succeeds (we registered this identifier specifically
            // as a refresh task), but a guard means a future mismatch fails
            // safely instead of crashing.
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleRefresh(task: refreshTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.processingTaskIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleProcessing(task: processingTask)
        }
    }

    /// Call from scenePhase == .background (or applicationDidEnterBackground).
    func scheduleTasks() {
        scheduleRefresh()
        scheduleProcessing()
    }

    private func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        // Ask iOS to run again no sooner than 1 hour from now; actual timing
        // is decided by the system based on usage patterns.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("Could not schedule refresh task: \(error)")
            #endif
        }
    }

    private func scheduleProcessing() {
        let request = BGProcessingTaskRequest(identifier: Self.processingTaskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60 * 24) // ~once a day
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("Could not schedule processing task: \(error)")
            #endif
        }
    }

    // MARK: - Task handlers

    private func handleRefresh(task: BGAppRefreshTask) {
        // Always schedule the next refresh before doing work, in case we're
        // interrupted or killed.
        scheduleRefresh()

        let operation = BlockOperation {
            self.expandAndScheduleNotifications()
        }

        task.expirationHandler = {
            operation.cancel()
        }

        operation.completionBlock = {
            task.setTaskCompleted(success: !operation.isCancelled)
        }

        OperationQueue().addOperation(operation)
    }

    private func handleProcessing(task: BGProcessingTask) {
        scheduleProcessing()

        let operation = BlockOperation {
            self.pruneOldEvents()
            self.cleanupOrphanedImages()
        }

        task.expirationHandler = {
            operation.cancel()
        }

        operation.completionBlock = {
            task.setTaskCompleted(success: !operation.isCancelled)
        }

        OperationQueue().addOperation(operation)
    }

    /// Runs a quick, synchronous maintenance pass immediately at app launch,
    /// rather than waiting for iOS to eventually schedule the background
    /// processing task (which could be hours or days depending on usage
    /// patterns). Call this once from the app's init.
    func runStartupMaintenance() {
        DispatchQueue.global(qos: .utility).async {
            self.cleanupOrphanedImages()
        }
    }

    // MARK: - Actual background work

    /// Expands recurring events across a wide lookahead window and hands
    /// them to NotificationScheduler, which itself picks only the soonest
    /// 60 to actually schedule (see its doc comment) — so the user gets
    /// reminders even if the app isn't opened, without exceeding iOS's
    /// pending-notification cap.
    private func expandAndScheduleNotifications() {
        let now = Date()
        guard let windowEnd = Calendar.current.date(byAdding: .day, value: notificationLookaheadDays, to: now) else { return }

        let events = EventRepository.shared.fetchEvents(overlapping: now, windowEnd)
        let occurrences = RecurrenceEngine.occurrences(for: events, in: now, windowEnd)

        NotificationScheduler.shared.scheduleNotifications(for: occurrences)
    }

    /// Example maintenance work: delete events whose recurrence has fully
    /// ended more than a year ago, keeping the local DB small.
    private func pruneOldEvents() {
        let cutoff = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let all = EventRepository.shared.fetchAll()
        for event in all {
            let ruleEnded = event.recurrence.until.map { $0 < cutoff } ?? true
            if !event.recurrence.isRecurring, event.endDate < cutoff {
                if let id = event.id { EventRepository.shared.delete(id: id) }
            } else if event.recurrence.isRecurring, ruleEnded {
                if let id = event.id { EventRepository.shared.delete(id: id) }
            }
        }
    }

    /// Deletes any photo file on disk that isn't referenced by any event —
    /// e.g. a photo picked/taken during editing, then abandoned by tapping
    /// Cancel instead of Save. See EventImageStore.deleteOrphanedFiles.
    private func cleanupOrphanedImages() {
        let referenced = Set(EventRepository.shared.fetchAll().compactMap { $0.imageFileName })
        EventImageStore.deleteOrphanedFiles(keeping: referenced)
    }
}
