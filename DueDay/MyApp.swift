import SwiftUI
import SwiftData

@main struct MyApp: App {
    @Environment(\.scenePhase) private var scenePhase

    let container: ModelContainer = {
        do {
            return try ModelContainer(for: Bill.self, BillInstance.self, Payment.self)
        } catch {
            fatalError("Could not create the model container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Keep a few months of instances ahead of today.
            if phase == .active {
                InstanceGenerator.generateAll(in: container.mainContext)
            }
        }
    }
}
