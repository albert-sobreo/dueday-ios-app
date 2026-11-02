import Foundation
import SwiftData
import SwiftUI

// CloudKit sync rules: every property has a default or is optional, relationships are optional,
// and there are no unique constraints.
@Model
final class Bill {
    var id: UUID = UUID()
    var name: String = ""
    var presetID: String?
    /// Provider colour copied when the bill is created, so custom providers keep theirs.
    var colorHex: String?
    /// A logo the user uploaded for this bill, as a small square image.
    @Attribute(.externalStorage) var logoData: Data?
    var category: BillCategory = BillCategory.other
    var accountNumber: String?
    var amountType: AmountType = AmountType.fixed
    var defaultAmount: Decimal?
    var recurrence: RecurrenceKind = RecurrenceKind.monthly
    /// Months between bills when `recurrence` is `.everyNMonths`.
    var recurrenceInterval: Int = 1
    /// Any date in the first month the bill is due. Later months are stepped from here.
    var startDate: Date = Date()
    var dueDay: Int = 1
    var weekendRule: WeekendRule = WeekendRule.none
    /// Days before the due date to remind. 0 means on the due date.
    var reminderOffsets: [Int] = [3, 0]
    var defaultPaymentMethod: PaymentMethod?
    /// Name of a custom payment method. When set, it's used instead of `defaultPaymentMethod`.
    var customPaymentName: String?
    /// For variable accounts: the day of the month the bill usually arrives. Nil means no nudge.
    var expectedDay: Int?
    /// Show a Live Activity on the lock screen on the due date until the bill is paid.
    var liveActivityEnabled: Bool = false
    var isArchived: Bool = false
    var profile: Profile?

    @Relationship(deleteRule: .cascade, inverse: \BillInstance.bill)
    var instances: [BillInstance]? = []

    init(name: String = "") {
        self.name = name
    }

    /// Adds one bill to this account, e.g. when a Meralco bill arrives. Used for variable accounts,
    /// whose amount and due date are only known once the bill is in hand.
    @discardableResult
    func addInstance(
        dueDate: Date,
        amount: Decimal,
        billingPeriod: String? = nil,
        calendar: Calendar = .current,
        in context: ModelContext
    ) -> BillInstance {
        let key = calendar.component(.year, from: dueDate) * 100 + calendar.component(.month, from: dueDate)
        let instance = BillInstance(bill: self, dueDate: calendar.startOfDay(for: dueDate), periodKey: key, amount: amount)
        instance.billingPeriod = billingPeriod
        context.insert(instance)
        return instance
    }

    /// True when a variable account is past its usual arrival day and no bill was added this month.
    func isAwaitingBill(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard amountType == .variable, !isArchived, let expectedDay else { return false }
        guard calendar.component(.day, from: now) >= expectedDay else { return false }
        let addedThisMonth = (instances ?? []).contains {
            calendar.isDate($0.createdAt, equalTo: now, toGranularity: .month)
        }
        return !addedThisMonth
    }

    /// The bill's own colour as hex: the one the user picked, else the biller's. Nil for plain
    /// category colours.
    var accentHex: String? {
        colorHex ?? PresetStore.preset(withID: presetID)?.colorHex
    }

    /// Icon for lists: the bundled preset's, otherwise the category's.
    var displayIcon: String {
        PresetStore.preset(withID: presetID)?.icon ?? category.symbol
    }

    /// Colour for lists: the stored provider colour, then the preset's, then the category's.
    var displayColor: Color {
        if let colorHex { return Color.adaptive(hex: colorHex) }
        return PresetStore.preset(withID: presetID)?.color ?? category.color
    }

    /// Paid instances, newest first. Feeds payment history and the trend chart.
    var paidInstances: [BillInstance] {
        (instances ?? []).filter(\.isPaid).sorted { $0.dueDate > $1.dueDate }
    }

    /// Percent change of an instance's amount against the previous paid one, e.g. 9.5 for +9.5%.
    func percentChange(for instance: BillInstance) -> Double? {
        guard let amount = instance.amount,
              let previous = paidInstances.first(where: { $0.dueDate < instance.dueDate }),
              let previousAmount = previous.amount, previousAmount > 0
        else { return nil }
        return ((amount - previousAmount) / previousAmount as NSDecimalNumber).doubleValue * 100
    }

    /// Account number with all but the last 4 characters hidden, e.g. "•••• 4589".
    var maskedAccountNumber: String? {
        guard let accountNumber, !accountNumber.isEmpty else { return nil }
        return "•••• " + accountNumber.suffix(4)
    }

    /// Months between two consecutive bills.
    var monthStep: Int {
        switch recurrence {
        case .monthly, .once: 1
        case .everyNMonths: max(recurrenceInterval, 1)
        case .yearly: 12
        }
    }
}
