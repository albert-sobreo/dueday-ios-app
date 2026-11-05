import BackgroundTasks
import SwiftData

/// Keeps bills and reminders topped up while the app isn't opened, using iOS background app refresh.
/// iOS decides when (and whether) it runs, based on how often the app is used, battery and Low Power
/// Mode, so the "Open DueDay" reminder in `ReminderScheduler` is the safety net.
enum BackgroundRefresh {
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in Config/DueDay-Info.plist.
    static let identifier = "com.albert.dueday.refresh"

    /// Asks iOS for the next run, no sooner than 12 hours from now. A new request replaces the old one.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// What a run does: the same top-up as opening the app, then asks for the next run.
    @MainActor
    static func run(container: ModelContainer = AppContainer.shared) async {
        schedule()
        let context = container.mainContext
        InstanceGenerator.generateAll(in: context)
        try? context.save()
        await ReminderScheduler.reschedule(in: context)
    }
}
