import Foundation
import SwiftData

enum DueDateCalculator {
    /// The due date in a given month. A due day past the end of the month (29th–31st) falls on the
    /// last day, then the weekend rule is applied.
    static func dueDate(
        year: Int,
        month: Int,
        dueDay: Int,
        weekendRule: WeekendRule,
        calendar: Calendar = .current
    ) -> Date? {
        var components = DateComponents(year: year, month: month, day: 1)
        guard let firstOfMonth = calendar.date(from: components),
              let dayRange = calendar.range(of: .day, in: .month, for: firstOfMonth)
        else { return nil }

        components.day = min(max(dueDay, 1), dayRange.count)
        guard let date = calendar.date(from: components) else { return nil }
        return applyWeekendRule(weekendRule, to: date, calendar: calendar)
    }

    /// Moves a weekend date back to the Friday before, if the rule says so.
    static func applyWeekendRule(_ rule: WeekendRule, to date: Date, calendar: Calendar = .current) -> Date {
        guard rule == .previousBusinessDay else { return date }
        // Saturday goes back one day, Sunday goes back two.
        switch calendar.component(.weekday, from: date) {
        case 7: return calendar.date(byAdding: .day, value: -1, to: date) ?? date
        case 1: return calendar.date(byAdding: .day, value: -2, to: date) ?? date
        default: return date
        }
    }
}

enum InstanceGenerator {
    /// Creates missing instances from the current month through `monthsAhead` months out.
    /// Existing instances (paid or not) are left alone.
    static func generate(
        for bill: Bill,
        monthsAhead: Int = 3,
        now: Date = .now,
        calendar: Calendar = .current,
        in context: ModelContext
    ) {
        // Variable bills (like electricity) are added by hand when they arrive, never generated.
        guard !bill.isArchived, bill.amountType == .fixed else { return }

        // A one-time bill has a single instance, on its start date's month.
        if bill.recurrence == .once {
            let parts = calendar.dateComponents([.year, .month], from: bill.startDate)
            guard let year = parts.year, let month = parts.month else { return }
            let key = year * 100 + month
            guard !(bill.instances ?? []).contains(where: { $0.periodKey == key }),
                  let due = DueDateCalculator.dueDate(
                      year: year, month: month, dueDay: bill.dueDay,
                      weekendRule: bill.weekendRule, calendar: calendar
                  )
            else { return }
            let amount = bill.amountType == .fixed ? bill.defaultAmount : nil
            context.insert(BillInstance(bill: bill, dueDate: due, periodKey: key, amount: amount))
            return
        }

        if bill.recurrence.isWeekly {
            generateWeekly(for: bill, monthsAhead: monthsAhead, now: now, calendar: calendar, in: context)
            return
        }

        let start = calendar.dateComponents([.year, .month], from: bill.startDate)
        let current = calendar.dateComponents([.year, .month], from: now)
        guard let startYear = start.year, let startMonth = start.month,
              let currentYear = current.year, let currentMonth = current.month
        else { return }

        // Months are counted as an absolute index so stepping across years is simple arithmetic.
        let startIndex = startYear * 12 + (startMonth - 1)
        let currentIndex = currentYear * 12 + (currentMonth - 1)
        let lastIndex = currentIndex + monthsAhead
        let step = bill.monthStep

        let existingKeys = Set((bill.instances ?? []).map(\.periodKey))

        var index = startIndex
        // Skip ahead to the first occurrence in or after the current month.
        if index < currentIndex {
            index += ((currentIndex - index + step - 1) / step) * step
        }

        while index <= lastIndex {
            let year = index / 12
            let month = index % 12 + 1
            let key = year * 100 + month
            if !existingKeys.contains(key),
               let due = DueDateCalculator.dueDate(
                   year: year, month: month, dueDay: bill.dueDay,
                   weekendRule: bill.weekendRule, calendar: calendar
               ) {
                let amount = bill.amountType == .fixed ? bill.defaultAmount : nil
                let instance = BillInstance(bill: bill, dueDate: due, periodKey: key, amount: amount)
                context.insert(instance)
            }
            index += step
        }
    }

    /// Weekly and every-two-weeks bills: one instance every 7 or 14 days from the first due date,
    /// from the start of the current month through `monthsAhead` months out.
    private static func generateWeekly(
        for bill: Bill,
        monthsAhead: Int,
        now: Date,
        calendar: Calendar,
        in context: ModelContext
    ) {
        let step = bill.recurrence.dayStep
        let anchor = calendar.startOfDay(for: bill.startDate)
        guard let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start,
              let horizon = calendar.date(byAdding: .month, value: monthsAhead + 1, to: startOfMonth)
        else { return }

        // Skip ahead to the first occurrence in or after the current month.
        var due = anchor
        if due < startOfMonth {
            let days = calendar.dateComponents([.day], from: anchor, to: startOfMonth).day ?? 0
            due = calendar.date(byAdding: .day, value: ((days + step - 1) / step) * step, to: anchor) ?? horizon
        }

        let existingKeys = Set((bill.instances ?? []).map(\.periodKey))
        let amount = bill.defaultAmount

        while due < horizon {
            let key = bill.periodKey(for: due, calendar: calendar)
            if !existingKeys.contains(key) {
                // The key follows the scheduled day, so a weekend shift can't make a duplicate later.
                let shifted = DueDateCalculator.applyWeekendRule(bill.weekendRule, to: due, calendar: calendar)
                context.insert(BillInstance(bill: bill, dueDate: shifted, periodKey: key, amount: amount))
            }
            guard let next = calendar.date(byAdding: .day, value: step, to: due) else { break }
            due = next
        }
    }

    /// Call after editing a bill: drops unpaid instances from the current month on, then regenerates
    /// them from the new settings. Paid instances and past overdue ones are kept.
    static func regenerate(
        for bill: Bill,
        now: Date = .now,
        calendar: Calendar = .current,
        in context: ModelContext
    ) {
        // Bills on a variable account are entered by hand, so editing the account must not touch them.
        guard bill.amountType == .fixed else { return }

        let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        // A one-time bill has only one instance, so replace it even if it's already overdue.
        let isOnce = bill.recurrence == .once
        for instance in bill.instances ?? [] where !instance.isPaid && (isOnce || instance.dueDate >= startOfMonth) {
            context.delete(instance)
        }
        // Deleted objects can still show up in the relationship until saved.
        try? context.save()
        generate(for: bill, now: now, calendar: calendar, in: context)
    }

    /// Tops up every active bill. Run at launch and when returning to the foreground.
    static func generateAll(in context: ModelContext, now: Date = .now) {
        let descriptor = FetchDescriptor<Bill>(predicate: #Predicate { !$0.isArchived })
        guard let bills = try? context.fetch(descriptor) else { return }
        for bill in bills {
            generate(for: bill, now: now, in: context)
        }
    }
}
