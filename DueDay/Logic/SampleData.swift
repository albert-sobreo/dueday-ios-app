#if DEBUG
import Foundation
import SwiftData

/// Debug-only sample bills for checking the UI against the design.
enum SampleData {
    static func populate(in context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        let profile = (try? context.fetch(FetchDescriptor<Profile>(sortBy: [SortDescriptor(\.sortOrder)])))?.first
            ?? {
                let created = Profile(name: "Personal")
                context.insert(created)
                return created
            }()

        @discardableResult
        func addBill(
            _ name: String, _ preset: String, _ category: BillCategory,
            day: Int, amount: Decimal?, method: PaymentMethod?, accountNumber: String? = nil
        ) -> Bill {
            let bill = Bill(name: name)
            bill.presetID = preset
            bill.category = category
            bill.dueDay = day
            bill.amountType = amount == nil ? .variable : .fixed
            bill.defaultAmount = amount
            bill.defaultPaymentMethod = method
            bill.accountNumber = accountNumber
            bill.profile = profile
            context.insert(bill)
            InstanceGenerator.generate(for: bill, now: now, calendar: calendar, in: context)
            return bill
        }

        let meralco = addBill("Meralco", "meralco", .electricity, day: 5, amount: nil, method: .gcash, accountNumber: "20114589")
        addBill("PLDT Fibr", "pldt", .internetPhone, day: 8, amount: 1699, method: .autoDebit)
        let maynilad = addBill("Maynilad", "maynilad", .water, day: 12, amount: nil, method: .gcash)
        addBill("Condo rent", "rent", .housing, day: 15, amount: 12000, method: .bankTransfer)
        let bpi = addBill("BPI Card", "bpi-card", .creditCard, day: 20, amount: nil, method: nil)

        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let currentKey = year * 100 + month

        // Variable accounts don't generate bills, so add the ones that "arrived" this month.
        for (bill, day, amount) in [
            (meralco, 5, Decimal(string: "2845.60")!),
            (maynilad, 12, Decimal(string: "486.25")!),
            (bpi, 20, Decimal(4200)),
        ] {
            if let due = DueDateCalculator.dueDate(year: year, month: month, dueDay: day, weekendRule: .none, calendar: calendar) {
                bill.addInstance(dueDate: due, amount: amount, calendar: calendar, in: context)
            }
        }

        // A paid bill earlier this month.
        let pagibig = addBill("Pag-IBIG", "pagibig", .government, day: 1, amount: 200, method: .gcash)
        if let instance = pagibig.instances?.first(where: { $0.periodKey == currentKey }) {
            instance.markPaid(amount: 200, method: .gcash, date: instance.dueDate, in: context)
        }

        // An overdue bill from last month.
        let globe = Bill(name: "Globe Postpaid")
        globe.presetID = "globe"
        globe.category = .internetPhone
        globe.dueDay = 30
        globe.defaultAmount = 999
        globe.profile = profile
        context.insert(globe)
        if let lastMonth = calendar.date(byAdding: .month, value: -1, to: now),
           let due = DueDateCalculator.dueDate(
               year: calendar.component(.year, from: lastMonth), month: calendar.component(.month, from: lastMonth),
               dueDay: 30, weekendRule: .none, calendar: calendar
           ) {
            let key = calendar.component(.year, from: lastMonth) * 100 + calendar.component(.month, from: lastMonth)
            context.insert(BillInstance(bill: globe, dueDate: due, periodKey: key, amount: 999))
        }
        InstanceGenerator.generate(for: globe, now: now, calendar: calendar, in: context)
    }
}
#endif
