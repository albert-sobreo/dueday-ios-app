import Foundation
import SwiftData

/// A payment method the user added, such as "Cash" or "Coins.ph". It's saved so it can be picked again.
@Model
final class CustomPaymentMethod {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()

    init(name: String = "") {
        self.name = name
    }
}

/// How a bill is paid: one of the built-in methods, or a custom one by name.
enum PaymentChoice: Hashable {
    case builtIn(PaymentMethod)
    case custom(String)

    init?(method: PaymentMethod?, customName: String?) {
        if let customName, !customName.isEmpty {
            self = .custom(customName)
        } else if let method {
            self = .builtIn(method)
        } else {
            return nil
        }
    }

    var title: String {
        switch self {
        case .builtIn(let method): method.title
        case .custom(let name): name
        }
    }

    var subtitle: String {
        switch self {
        case .builtIn(let method): method.subtitle
        case .custom: "Custom"
        }
    }

    var symbol: String {
        switch self {
        case .builtIn(let method): method.symbol
        case .custom: "wallet.pass"
        }
    }

    /// The built-in method, if this is one.
    var builtInMethod: PaymentMethod? {
        if case .builtIn(let method) = self { method } else { nil }
    }

    /// The name, if this is a custom method.
    var customName: String? {
        if case .custom(let name) = self { name } else { nil }
    }
}

extension Bill {
    /// The usual way this bill is paid, built-in or custom.
    var paymentChoice: PaymentChoice? {
        get { PaymentChoice(method: defaultPaymentMethod, customName: customPaymentName) }
        set {
            defaultPaymentMethod = newValue?.builtInMethod
            customPaymentName = newValue?.customName
        }
    }
}

extension Payment {
    /// How this payment was made, built-in or custom.
    var choice: PaymentChoice? {
        get { PaymentChoice(method: method, customName: customMethodName) }
        set {
            method = newValue?.builtInMethod
            customMethodName = newValue?.customName
        }
    }
}
