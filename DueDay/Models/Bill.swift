import Foundation
import SwiftData

// CloudKit sync rules: every property has a default or is optional, relationships are optional,
// and there are no unique constraints.
@Model
final class Bill {
    var id: UUID = UUID()
    var name: String = ""
    var presetID: String?
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
    var isArchived: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \BillInstance.bill)
    var instances: [BillInstance]? = []

    init(name: String = "") {
        self.name = name
    }

    /// Months between two consecutive bills.
    var monthStep: Int {
        switch recurrence {
        case .monthly: 1
        case .everyNMonths: max(recurrenceInterval, 1)
        case .yearly: 12
        }
    }
}
