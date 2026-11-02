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
        guard var date = calendar.date(from: components) else { return nil }

        if weekendRule == .previousBusinessDay {
            // Saturday goes back one day, Sunday goes back two.
            switch calendar.component(.weekday, from: date) {
            case 7: date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
            case 1: date = calendar.date(byAdding: .day, value: -2, to: date) ?? date
            default: break
            }
        }
        return date
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
        guard !bill.isArchived else { return }

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

    /// Call after editing a bill: drops unpaid instances from the current month on, then regenerates
    /// them from the new settings. Paid instances and past overdue ones are kept.
    static func regenerate(
        for bill: Bill,
        now: Date = .now,
        calendar: Calendar = .current,
        in context: ModelContext
    ) {
        let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        for instance in bill.instances ?? [] where !instance.isPaid && instance.dueDate >= startOfMonth {
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
