import Foundation
import SwiftData

@Model
final class Payment {
    var id: UUID = UUID()
    var instance: BillInstance?
    var paidDate: Date = Date()
    var amountPaid: Decimal = 0
    var method: PaymentMethod?
    /// Name of a custom payment method. When set, it's used instead of `method`.
    var customMethodName: String?
    var referenceNumber: String?
    var note: String?

    init(instance: BillInstance?, paidDate: Date, amountPaid: Decimal, method: PaymentMethod?) {
        self.instance = instance
        self.paidDate = paidDate
        self.amountPaid = amountPaid
        self.method = method
    }
}
