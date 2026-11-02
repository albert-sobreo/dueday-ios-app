import Foundation
import SwiftData

/// One occurrence of a `Bill`, e.g. "Meralco, November 2026".
@Model
final class BillInstance {
    var id: UUID = UUID()
    var bill: Bill?
    var dueDate: Date = Date()
    /// When this bill was added to the app.
    var createdAt: Date = Date()
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

    /// The most recent payment, if any.
    var latestPayment: Payment? {
        (payments ?? []).max { $0.paidDate < $1.paidDate }
    }

    /// True when the bill was paid after its due date.
    func wasPaidLate(calendar: Calendar = .current) -> Bool {
        guard isPaid, let paidDate = latestPayment?.paidDate else { return false }
        return calendar.startOfDay(for: paidDate) > calendar.startOfDay(for: dueDate)
    }

    /// Whole days past the due date for an unpaid bill, or 0 if it isn't overdue.
    func daysOverdue(now: Date = .now, calendar: Calendar = .current) -> Int {
        guard !isPaid else { return 0 }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: dueDate), to: calendar.startOfDay(for: now)
        ).day ?? 0
        return max(days, 0)
    }

    /// Records a payment and marks the instance as paid.
    @discardableResult
    func markPaid(
        amount: Decimal,
        method: PaymentChoice?,
        date: Date = .now,
        referenceNumber: String? = nil,
        note: String? = nil,
        in context: ModelContext
    ) -> Payment {
        let payment = Payment(instance: self, paidDate: date, amountPaid: amount, method: nil)
        payment.choice = method
        payment.referenceNumber = referenceNumber
        payment.note = note
        context.insert(payment)
        self.amount = amount
        isPaid = true
        return payment
    }

    /// Pays the bill in one step using its known amount and default method.
    /// Returns false when the amount is unknown, so the caller should ask for it.
    @discardableResult
    func quickPay(in context: ModelContext) -> Bool {
        guard let amount, amount > 0 else { return false }
        markPaid(amount: amount, method: bill?.paymentChoice, in: context)
        return true
    }

    /// Reverts a paid instance, e.g. after a mistaken tap.
    func markUnpaid(in context: ModelContext) {
        for payment in payments ?? [] {
            context.delete(payment)
        }
        isPaid = false
    }
}
