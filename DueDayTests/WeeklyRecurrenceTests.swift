import Foundation
import SwiftData
import Testing
@testable import DueDay

private let weeklyCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    return calendar
}()

private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    weeklyCalendar.date(from: DateComponents(year: year, month: month, day: day))!
}

/// A context doesn't keep its container alive, so containers are held here for the whole test run.
@MainActor private var weeklyContainers: [ModelContainer] = []

@MainActor
private func makeWeeklyContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: Profile.self, CustomProvider.self, CustomPaymentMethod.self,
        Bill.self, BillInstance.self, Payment.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    weeklyContainers.append(container)
    return container.mainContext
}

@MainActor
struct WeeklyRecurrenceTests {
    private func weeklyBill(_ kind: RecurrenceKind, starting start: Date, in context: ModelContext) -> Bill {
        let bill = Bill(name: "Allowance")
        bill.amountType = .fixed
        bill.defaultAmount = 500
        bill.recurrence = kind
        bill.startDate = start
        bill.dueDay = weeklyCalendar.component(.day, from: start)
        context.insert(bill)
        return bill
    }

    private func dueDates(_ bill: Bill) -> [Date] {
        (bill.instances ?? []).map(\.dueDate).sorted()
    }

    @Test func weeklyBillsFallEverySevenDaysFromTheFirstDueDate() throws {
        let context = try makeWeeklyContext()
        // Monday 5 October 2026, with "today" in November.
        let bill = weeklyBill(.weekly, starting: day(2026, 10, 5), in: context)
        InstanceGenerator.generate(for: bill, now: day(2026, 11, 3), calendar: weeklyCalendar, in: context)

        let dates = dueDates(bill)
        #expect(dates.first == day(2026, 11, 2))              // The first Monday in the current month.
        #expect(dates.count >= 13)                            // November through February.
        for (earlier, later) in zip(dates, dates.dropFirst()) {
            #expect(weeklyCalendar.dateComponents([.day], from: earlier, to: later).day == 7)
        }
        #expect(Set((bill.instances ?? []).map(\.periodKey)).count == dates.count)
    }

    @Test func everyTwoWeeksSkipsAWeek() throws {
        let context = try makeWeeklyContext()
        let bill = weeklyBill(.everyTwoWeeks, starting: day(2026, 10, 5), in: context)
        InstanceGenerator.generate(for: bill, now: day(2026, 11, 3), calendar: weeklyCalendar, in: context)

        let dates = dueDates(bill)
        // 5 and 19 October, then 2 November, so the first one this month is the 2nd.
        #expect(dates.first == day(2026, 11, 2))
        for (earlier, later) in zip(dates, dates.dropFirst()) {
            #expect(weeklyCalendar.dateComponents([.day], from: earlier, to: later).day == 14)
        }
    }

    @Test func generatingAgainAddsNothing() throws {
        let context = try makeWeeklyContext()
        let bill = weeklyBill(.weekly, starting: day(2026, 10, 5), in: context)
        InstanceGenerator.generate(for: bill, now: day(2026, 11, 3), calendar: weeklyCalendar, in: context)
        let first = (bill.instances ?? []).count
        InstanceGenerator.generate(for: bill, now: day(2026, 11, 3), calendar: weeklyCalendar, in: context)
        #expect((bill.instances ?? []).count == first)
    }

    @Test func aBillMovedToAnotherDayIsNotGeneratedAgain() throws {
        let context = try makeWeeklyContext()
        let bill = weeklyBill(.weekly, starting: day(2026, 10, 5), in: context)
        InstanceGenerator.generate(for: bill, now: day(2026, 11, 3), calendar: weeklyCalendar, in: context)
        let count = (bill.instances ?? []).count

        // Moving a due date keeps its key, so the slot isn't empty and nothing new appears.
        let moved = try #require(dueDates(bill).first.flatMap { first in
            (bill.instances ?? []).first { $0.dueDate == first }
        })
        moved.dueDate = day(2026, 11, 4)
        InstanceGenerator.generate(for: bill, now: day(2026, 11, 3), calendar: weeklyCalendar, in: context)
        #expect((bill.instances ?? []).count == count)
    }

    @Test func aWeekendDueDateCanShiftToFriday() throws {
        let context = try makeWeeklyContext()
        // Saturday 7 November 2026.
        let bill = weeklyBill(.weekly, starting: day(2026, 11, 7), in: context)
        bill.weekendRule = .previousBusinessDay
        InstanceGenerator.generate(for: bill, now: day(2026, 11, 3), calendar: weeklyCalendar, in: context)

        #expect(dueDates(bill).first == day(2026, 11, 6))
    }

    @Test func monthlyKeysAreUnchanged() {
        let bill = Bill(name: "Rent")
        #expect(bill.periodKey(for: day(2026, 11, 20), calendar: weeklyCalendar) == 202611)
        bill.recurrence = .weekly
        #expect(bill.periodKey(for: day(2026, 11, 20), calendar: weeklyCalendar) == 20261120)
    }
}
