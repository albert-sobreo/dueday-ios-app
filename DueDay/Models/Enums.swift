import SwiftUI

// Raw values are persisted by SwiftData (and synced through CloudKit), so never rename or reorder them.

enum BillCategory: String, Codable, CaseIterable, Identifiable {
    case electricity, water, internetPhone, government, creditCard
    case insurance, housing, subscription, education, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .electricity: "Electricity"
        case .water: "Water"
        case .internetPhone: "Internet & Phone"
        case .government: "Government"
        case .creditCard: "Credit Card"
        case .insurance: "Insurance"
        case .housing: "Housing"
        case .subscription: "Subscription"
        case .education: "Education"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .electricity: "bolt.fill"
        case .water: "drop.fill"
        case .internetPhone: "wifi"
        case .government: "building.columns.fill"
        case .creditCard: "creditcard.fill"
        case .insurance: "shield.fill"
        case .housing: "house.fill"
        case .subscription: "play.rectangle.fill"
        case .education: "graduationcap.fill"
        case .other: "doc.text.fill"
        }
    }

    var color: Color {
        switch self {
        case .electricity: .orange
        case .water: .blue
        case .internetPhone: .indigo
        case .government: .red
        case .creditCard: .purple
        case .insurance: .teal
        case .housing: .brown
        case .subscription: .pink
        case .education: .green
        case .other: .gray
        }
    }
}

enum ProfileKind: String, Codable, CaseIterable, Identifiable {
    case personal, business, someoneElse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal: "Personal"
        case .business: "Business"
        case .someoneElse: "Someone else"
        }
    }

    var symbol: String {
        switch self {
        case .personal: "person.fill"
        case .business: "briefcase.fill"
        case .someoneElse: "person.2.fill"
        }
    }
}

enum AmountType: String, Codable, CaseIterable, Identifiable {
    case fixed, variable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fixed: "Fixed"
        case .variable: "Variable"
        }
    }
}

enum RecurrenceKind: String, Codable, CaseIterable, Identifiable {
    case monthly, everyNMonths, yearly, once

    var id: String { rawValue }

    var title: String {
        switch self {
        case .once: "Does not repeat"
        case .monthly: "Monthly"
        case .everyNMonths: "Every N months"
        case .yearly: "Yearly"
        }
    }
}

enum WeekendRule: String, Codable, CaseIterable, Identifiable {
    case none, previousBusinessDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Keep the due date"
        case .previousBusinessDay: "Shift to previous business day"
        }
    }
}

enum InstanceStatus: String {
    case upcoming, due, overdue, paid

    var title: String {
        switch self {
        case .upcoming: "Upcoming"
        case .due: "Due today"
        case .overdue: "Overdue"
        case .paid: "Paid"
        }
    }

    var color: Color {
        switch self {
        case .upcoming: .secondary
        case .due: .orange
        case .overdue: .red
        case .paid: .green
        }
    }
}

enum PaymentMethod: String, Codable, CaseIterable, Identifiable {
    case gcash, maya, bankTransfer, overTheCounter, autoDebit, creditCard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gcash: "GCash"
        case .maya: "Maya"
        case .bankTransfer: "Bank transfer"
        case .overTheCounter: "Over-the-counter"
        case .autoDebit: "Auto-debit"
        case .creditCard: "Credit card"
        }
    }

    /// Short description shown under the name, as in the design.
    var subtitle: String {
        switch self {
        case .gcash, .maya: "E-wallet"
        case .bankTransfer: "InstaPay / PESONet"
        case .overTheCounter: "Bayad, 7-Eleven"
        case .autoDebit: "From account"
        case .creditCard: "Online"
        }
    }

    var symbol: String {
        switch self {
        case .gcash, .maya: "iphone"
        case .bankTransfer: "building.columns"
        case .overTheCounter: "storefront"
        case .autoDebit: "arrow.triangle.2.circlepath"
        case .creditCard: "creditcard"
        }
    }
}
