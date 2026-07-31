import SwiftUI

@main
struct EventsontheDownLowApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Must be called before the app finishes launching.
        BackgroundTaskManager.shared.registerTasks()
        NotificationScheduler.shared.requestAuthorization()
        BackgroundTaskManager.shared.runStartupMaintenance()
    }
    ///test note
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                BackgroundTaskManager.shared.scheduleTasks()
            }
        }
    }
}
