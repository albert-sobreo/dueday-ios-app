import SwiftData

/// The app's one database. The app and its Shortcuts/Siri actions share it, so they always see the
/// same bills.
enum AppContainer {
    nonisolated static let shared: ModelContainer = {
        do {
            return try ModelContainer(
                for: Profile.self, CustomProvider.self, CustomPaymentMethod.self,
                Bill.self, BillInstance.self, Payment.self
            )
        } catch {
            fatalError("Could not create the model container: \(error)")
        }
    }()
}
