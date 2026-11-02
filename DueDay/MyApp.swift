import SwiftUI
import SwiftData
import AppIntents
import UserNotifications

@main struct MyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system.rawValue

    init() {
        FontRegistrar.registerAll()

        // Soften the tabs that aren't selected, so the selected one stands out.
        UITabBar.appearance().unselectedItemTintColor = UIColor(Theme.ink).withAlphaComponent(0.4)

        // Reminders: show them while the app is open, and handle the "Mark paid" button.
        NotificationDelegate.shared.container = container
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        ReminderScheduler.registerCategories()

        // Start listening for tip purchases right away, so none are missed.
        _ = TipJar.shared
    }

    let container = AppContainer.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(AppearanceMode(rawValue: appearance)?.colorScheme)
        }
        .modelContainer(container)
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                // Keep a few months of instances ahead of today, and the reminders up to date.
                ProfileSeeder.ensureDefault(in: container.mainContext)
                InstanceGenerator.generateAll(in: container.mainContext)
                Task { await ReminderScheduler.reschedule(in: container.mainContext) }
                DueDayShortcuts.updateAppShortcutParameters()
            case .background:
                // Changes made while the app was open become reminders as the person leaves.
                try? container.mainContext.save()
                Task { await ReminderScheduler.reschedule(in: container.mainContext) }
                // Bills may have been added or removed, so let Siri learn the current names.
                DueDayShortcuts.updateAppShortcutParameters()
            default:
                break
            }
        }
    }
}
