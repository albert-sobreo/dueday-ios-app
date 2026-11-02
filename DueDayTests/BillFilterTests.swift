import Foundation
import SwiftData
import Testing
@testable import DueDay

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
}

@MainActor private var filterContainers: [ModelContainer] = []

@MainActor
struct BillFilterTests {
    /// Today is 2 Nov 2026, with paydays on the 15th and 30th, so cutoffs are Nov 1–15, Nov 16–30, Dec 1–15.
    private let today = date(2026, 11, 2)
    private let paydays = [15, 30]

    private func engine(_ dueDates: [(day: Date, paid: Bool)]) throws -> BillFilterEngine {
        let container = try ModelContainer(
            for: Profile.self, CustomProvider.self, CustomPaymentMethod.self,
            Bill.self, BillInstance.self, Payment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        filterContainers.append(container)
        let context = container.mainContext
        let bill = Bill(name: "Test")
        context.insert(bill)

        var made: [BillInstance] = []
        for item in dueDates {
            let instance = bill.addInstance(dueDate: item.day, amount: 100, calendar: calendar, in: context)
            if item.paid { instance.markPaid(amount: 100, method: nil, date: today, in: context) }
            made.append(instance)
        }
        return BillFilterEngine(instances: made, paydays: paydays, now: today, calendar: calendar)
    }

    private func days(_ items: [BillInstance]) -> [Int] {
        items.map { calendar.component(.day, from: $0.dueDate) + 100 * calendar.component(.month, from: $0.dueDate) }
    }

    @Test func overdueMeansDueBeforeToday() throws {
        let engine = try engine([(date(2026, 10, 30), false), (date(2026, 11, 2), false), (date(2026, 11, 5), false)])
        #expect(days(engine.items(for: .overdue)) == [1030])
    }

    @Test func dueSoonIsTheNextSevenDaysAndNotOverdue() throws {
        let engine = try engine([
            (date(2026, 10, 30), false),   // overdue
            (date(2026, 11, 2), false),    // today
            (date(2026, 11, 9), false),    // 7 days away: included
            (date(2026, 11, 10), false),   // 8 days away: not yet
        ])
        #expect(days(engine.items(for: .dueSoon)) == [1102, 1109])
    }

    @Test func eachCutoffFilterListsItsOwnBills() throws {
        let engine = try engine([
            (date(2026, 11, 5), false),    // current: Nov 1–15
            (date(2026, 11, 20), false),   // next: Nov 16–30
            (date(2026, 12, 8), false),    // later: Dec 1–15
            (date(2027, 1, 8), false),     // later
        ])
        #expect(days(engine.items(for: .currentCutoff)) == [1105])
        #expect(days(engine.items(for: .nextCutoff)) == [1120])
        #expect(days(engine.items(for: .laterCutoffs)) == [1208, 108])
    }

    @Test func overdueBillsAreNotInTheCutoffFilters() throws {
        let engine = try engine([(date(2026, 10, 30), false)])
        #expect(engine.items(for: .currentCutoff).isEmpty)
    }

    @Test func anOverdueBillInsideTheCurrentCutoffIsListedThere() throws {
        // Nov 1 is overdue today (Nov 2) but still inside the Nov 1–15 cutoff; Oct 30 is older than it.
        let engine = try engine([(date(2026, 10, 30), false), (date(2026, 11, 1), false), (date(2026, 11, 5), false)])
        #expect(days(engine.items(for: .currentCutoff)) == [1101, 1105])
        #expect(days(engine.overdueBeforeCutoffs) == [1030])
        // The Overdue filter still lists every overdue bill.
        #expect(days(engine.items(for: .overdue)) == [1030, 1101])
    }

    @Test func paidBillsLeaveTheUnpaidFilters() throws {
        let engine = try engine([(date(2026, 11, 5), true), (date(2026, 11, 6), false)])
        #expect(days(engine.items(for: .currentCutoff)) == [1106])
        #expect(days(engine.items(for: .paid)) == [1105])
    }

    @Test func cutoffFiltersAreEmptyWithoutPaydays() throws {
        var engine = try engine([(date(2026, 11, 5), false)])
        engine = BillFilterEngine(instances: engine.instances, paydays: [], now: today, calendar: calendar)
        #expect(engine.items(for: .currentCutoff).isEmpty)
        #expect(engine.items(for: .nextCutoff).isEmpty)
        #expect(engine.items(for: .laterCutoffs).isEmpty)
    }

    @Test func countsMatchTheLists() throws {
        let engine = try engine([(date(2026, 10, 30), false), (date(2026, 11, 5), false)])
        #expect(engine.count(for: .overdue) == 1)
        #expect(engine.count(for: .currentCutoff) == 1)
        #expect(engine.count(for: .all) == nil)
        #expect(engine.count(for: .accounts) == nil)
    }
}
