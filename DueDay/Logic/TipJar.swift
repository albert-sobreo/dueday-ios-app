import Foundation
import Observation
import StoreKit

/// Optional tips through in-app purchase. Tips unlock nothing: the app stays fully free.
@MainActor
@Observable
final class TipJar {
    static let shared = TipJar()

    /// The three consumable tips, as set up in App Store Connect.
    static let productIDs = ["tip.small", "tip.medium", "tip.large"]
    private static let supporterKey = "isSupporter"

    private(set) var products: [Product] = []
    private(set) var isLoading = false
    private(set) var purchasingID: String?
    var showThankYou = false
    var errorMessage: String?

    /// Set after a first successful tip, only to show a small badge.
    private(set) var isSupporter = UserDefaults.standard.bool(forKey: TipJar.supporterKey)

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    private init() {
        // Finish any purchases that completed outside the app, such as an interrupted one.
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    self?.markSupporter()
                }
            }
        }
    }

    /// Loads the tips with their prices. Prices come from the App Store, never from code.
    func load() async {
        guard products.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            errorMessage = "Tips couldn't be loaded. Check your connection and try again."
        }
    }

    func buy(_ product: Product) async {
        purchasingID = product.id
        defer { purchasingID = nil }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    markSupporter()
                    showThankYou = true
                } else {
                    errorMessage = "The purchase couldn't be verified."
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "The tip didn't go through. You weren't charged."
        }
    }

    private func markSupporter() {
        isSupporter = true
        UserDefaults.standard.set(true, forKey: Self.supporterKey)
    }
}
