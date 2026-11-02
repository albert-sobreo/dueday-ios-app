import SwiftUI
import SwiftData

@main struct MyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system.rawValue

    init() {
        FontRegistrar.registerAll()

        // Soften the tabs that aren't selected, so the selected one stands out.
        UITabBar.appearance().unselectedItemTintColor = UIColor(Theme.ink).withAlphaComponent(0.4)
    }

    let container: ModelContainer = {
        do {
            return try ModelContainer(for: Profile.self, CustomProvider.self, CustomPaymentMethod.self, Bill.self, BillInstance.self, Payment.self)
        } catch {
            fatalError("Could not create the model container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(AppearanceMode(rawValue: appearance)?.colorScheme)
        }
        .modelContainer(container)
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Keep a few months of instances ahead of today.
            if phase == .active {
                ProfileSeeder.ensureDefault(in: container.mainContext)
                InstanceGenerator.generateAll(in: container.mainContext)
            }
        }
    }
}
