import Foundation
import SwiftData

/// One occurrence of a `Bill`, e.g. "Meralco, November 2026".
@Model
final class BillInstance {
    var id: UUID = UUID()
    var bill: Bill?
    var dueDate: Date = Date()
    /// Month this instance belongs to, as year * 100 + month. Used to avoid generating duplicates.
    var periodKey: Int = 0
    /// Nil for a variable bill until the user enters the amount.
    var amount: Decimal?
    var isPaid: Bool = false
    var billingPeriod: String?
    @Attribute(.externalStorage) var attachment: Data?

    @Relationship(deleteRule: .cascade, inverse: \Payment.instance)
    var payments: [Payment]? = []

    init(bill: Bill?, dueDate: Date, periodKey: Int, amount: Decimal?) {
        self.bill = bill
        self.dueDate = dueDate
        self.periodKey = periodKey
        self.amount = amount
    }

    /// Status depends on today's date, so it's computed rather than stored.
    func status(now: Date = .now, calendar: Calendar = .current) -> InstanceStatus {
        if isPaid { return .paid }
        let today = calendar.startOfDay(for: now)
        let due = calendar.startOfDay(for: dueDate)
        if due == today { return .due }
        return due > today ? .upcoming : .overdue
    }

    /// Records a payment and marks the instance as paid.
    @discardableResult
    func markPaid(
        amount: Decimal,
        method: PaymentMethod?,
        date: Date = .now,
        referenceNumber: String? = nil,
        note: String? = nil,
        in context: ModelContext
    ) -> Payment {
        let payment = Payment(instance: self, paidDate: date, amountPaid: amount, method: method)
        payment.referenceNumber = referenceNumber
        payment.note = note
        context.insert(payment)
        self.amount = amount
        isPaid = true
        return payment
    }

    /// Reverts a paid instance, e.g. after a mistaken tap.
    func markUnpaid(in context: ModelContext) {
        for payment in payments ?? [] {
            context.delete(payment)
        }
        isPaid = false
    }
}
