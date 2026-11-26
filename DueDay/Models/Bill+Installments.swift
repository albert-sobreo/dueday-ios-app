import Foundation
import SwiftData

/// Installment plans: a fixed bill with a set number of payments, such as a phone paid over 24
/// months. Each generated bill carries its payment number, and the plan closes after the last one.
extension Bill {
    /// Largest plan the forms allow.
    static let maxInstallments = 120

    /// True for a fixed, repeating bill with a payment count.
    var isInstallment: Bool {
        guard let installmentCount, installmentCount > 0 else { return false }
        return amountType == .fixed && recurrence != .once
    }

    /// Payments still to be generated from `startDate`: the plan's count less those paid before it
    /// was added. The first due date is payment `installmentsPaidBefore + 1`.
    var installmentOccurrences: Int {
        guard isInstallment, let installmentCount else { return 0 }
        return max(installmentCount - installmentsPaidBefore, 0)
    }

    /// The payment number of the occurrence `index` steps after `startDate` (0 is the first).
    func installmentNumber(forOccurrence index: Int) -> Int {
        installmentsPaidBefore + index + 1
    }

    /// What one payment of a total costs: the total split evenly and rounded down to the centavo.
    /// The last payment makes up the difference.
    static func perPaymentAmount(total: Decimal, count: Int) -> Decimal {
        guard count > 0 else { return total }
        var share = total / Decimal(count)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &share, 2, .down)
        return rounded
    }

    /// The amount of payment `number`. Every payment is `defaultAmount`, except the last of a plan
    /// entered as a total, which takes whatever rounding left over.
    func installmentAmount(forNumber number: Int) -> Decimal? {
        guard isInstallment, let count = installmentCount, let per = defaultAmount else { return defaultAmount }
        if number == count, let total = installmentTotal {
            return total - per * Decimal(count - 1)
        }
        return per
    }

    /// This plan's generated bills that carry a payment number.
    private var numberedInstances: [BillInstance] {
        (instances ?? []).filter { $0.installmentNumber != nil }
    }

    /// True once every payment of the plan is paid: the last one is paid and none before it is
    /// still open.
    var isPaidOff: Bool {
        guard isInstallment, let count = installmentCount else { return false }
        if installmentsPaidBefore >= count { return true }
        let numbered = numberedInstances
        guard numbered.contains(where: { $0.installmentNumber == count && $0.isPaid }) else { return false }
        return !numbered.contains { !$0.isPaid }
    }

    /// Payments made so far, counting those made before the plan was added.
    var installmentsPaid: Int {
        guard isInstallment, let count = installmentCount else { return 0 }
        if isPaidOff { return count }
        let paidInApp = numberedInstances.filter(\.isPaid).count
        return min(installmentsPaidBefore + paidInApp, count)
    }

    /// Payments still to make.
    var installmentsLeft: Int {
        guard let installmentCount, isInstallment else { return 0 }
        return max(installmentCount - installmentsPaid, 0)
    }

    /// Share of the plan paid, from 0 to 1.
    var installmentProgress: Double {
        guard let installmentCount, isInstallment, installmentCount > 0 else { return 0 }
        return Double(installmentsPaid) / Double(installmentCount)
    }

    /// What's left to pay: open bills at their own amounts (one may have been edited), plus the
    /// scheduled amount for payments not generated yet.
    var remainingBalance: Decimal {
        guard isInstallment, let count = installmentCount, !isPaidOff else { return 0 }
        let numbered = numberedInstances
        let paidNumbers = Set(numbered.filter(\.isPaid).compactMap(\.installmentNumber))
        let openByNumber = Dictionary(
            numbered.filter { !$0.isPaid }.compactMap { instance in instance.installmentNumber.map { ($0, instance) } },
            uniquingKeysWith: { first, _ in first }
        )
        let first = installmentsPaidBefore + 1
        guard first <= count else { return 0 }
        var total: Decimal = 0
        for number in first...count where !paidNumbers.contains(number) {
            total += openByNumber[number]?.amount ?? installmentAmount(forNumber: number) ?? 0
        }
        return total
    }

    /// The whole plan: payments made before it was added, what was paid in the app, and what's left.
    var installmentPlanTotal: Decimal {
        guard isInstallment else { return 0 }
        let before = (defaultAmount ?? 0) * Decimal(installmentsPaidBefore)
        let paid = numberedInstances.filter(\.isPaid).reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }
        return before + paid + remainingBalance
    }

    /// The due date of payment `number`, worked out from the first due date and the schedule.
    func installmentDueDate(number: Int, calendar: Calendar = .current) -> Date? {
        guard isInstallment else { return nil }
        return Self.occurrenceDueDate(
            number - installmentsPaidBefore - 1, startDate: startDate, recurrence: recurrence,
            interval: recurrenceInterval, dueDay: dueDay, weekendRule: weekendRule, calendar: calendar
        )
    }

    /// The due date `index` steps after the first one (0 is the first), the way the generator
    /// steps it. Static so forms can preview a schedule before a bill exists.
    static func occurrenceDueDate(
        _ index: Int,
        startDate: Date,
        recurrence: RecurrenceKind,
        interval: Int,
        dueDay: Int,
        weekendRule: WeekendRule,
        calendar: Calendar = .current
    ) -> Date? {
        guard index >= 0 else { return nil }
        if recurrence.isWeekly {
            let anchor = calendar.startOfDay(for: startDate)
            guard let due = calendar.date(byAdding: .day, value: index * recurrence.dayStep, to: anchor) else { return nil }
            return DueDateCalculator.applyWeekendRule(weekendRule, to: due, calendar: calendar)
        }
        let step: Int
        switch recurrence {
        case .everyNMonths: step = max(interval, 1)
        case .yearly: step = 12
        default: step = 1
        }
        let start = calendar.dateComponents([.year, .month], from: startDate)
        guard let year = start.year, let month = start.month else { return nil }
        let monthIndex = year * 12 + (month - 1) + index * step
        return DueDateCalculator.dueDate(
            year: monthIndex / 12, month: monthIndex % 12 + 1, dueDay: dueDay,
            weekendRule: weekendRule, calendar: calendar
        )
    }

    /// When the last payment is due.
    func finalInstallmentDueDate(calendar: Calendar = .current) -> Date? {
        guard let installmentCount else { return nil }
        return installmentDueDate(number: installmentCount, calendar: calendar)
    }

    /// Archives a plan whose last payment was just paid, so it moves to "Paid off" on the Bills tab
    /// and leaves Home and the reminders. Returns true when it did.
    @discardableResult
    func closeIfPaidOff() -> Bool {
        guard isInstallment, !isArchived, isPaidOff else { return false }
        isArchived = true
        return true
    }

    /// Pays everything that's left in one payment, e.g. when settling a phone plan early. Open bills
    /// are removed and replaced by one paid bill for the last payment, then the plan closes.
    @discardableResult
    func payOffRemaining(
        amount: Decimal,
        method: PaymentChoice?,
        date: Date = .now,
        calendar: Calendar = .current,
        in context: ModelContext
    ) -> BillInstance? {
        guard isInstallment, let count = installmentCount, !isPaidOff else { return nil }
        for instance in instances ?? [] where !instance.isPaid {
            context.delete(instance)
        }
        // Deleted objects can still show up in the relationship until saved.
        try? context.save()
        let day = calendar.startOfDay(for: date)
        let instance = BillInstance(bill: self, dueDate: day, periodKey: periodKey(for: day, calendar: calendar), amount: amount)
        instance.installmentNumber = count
        instance.billingPeriod = String(localized: "Paid off early")
        context.insert(instance)
        instance.markPaid(amount: amount, method: method, date: date, in: context)
        return instance
    }
}
