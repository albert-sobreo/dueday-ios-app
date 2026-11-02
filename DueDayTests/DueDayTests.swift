import Foundation
import SwiftData
import Testing
@testable import DueDay

/// A calendar and dates that don't depend on the machine's time zone.
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
}

private func parts(_ date: Date) -> [Int] {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return [c.year!, c.month!, c.day!]
}

/// A context doesn't keep its container alive, so containers are held here for the whole test run.
@MainActor private var liveContainers: [ModelContainer] = []

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: Profile.self, CustomProvider.self, CustomPaymentMethod.self,
        Bill.self, BillInstance.self, Payment.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    liveContainers.append(container)
    return container.mainContext
}

// MARK: - Due dates

struct DueDateTests {
    @Test func dayPastTheEndOfAShortMonthFallsOnItsLastDay() {
        let due = DueDateCalculator.dueDate(year: 2026, month: 2, dueDay: 31, weekendRule: .none, calendar: calendar)
        #expect(parts(due!) == [2026, 2, 28])
    }

    @Test func sundayShiftsBackToFriday() {
        // 1 Nov 2026 is a Sunday.
        let due = DueDateCalculator.dueDate(year: 2026, month: 11, dueDay: 1, weekendRule: .previousBusinessDay, calendar: calendar)
        #expect(parts(due!) == [2026, 10, 30])
    }

    @Test func saturdayShiftsBackToFriday() {
        // 7 Nov 2026 is a Saturday.
        let due = DueDateCalculator.dueDate(year: 2026, month: 11, dueDay: 7, weekendRule: .previousBusinessDay, calendar: calendar)
        #expect(parts(due!) == [2026, 11, 6])
    }

    @Test func weekdayIsLeftAloneWhenShiftingIsOn() {
        let due = DueDateCalculator.dueDate(year: 2026, month: 11, dueDay: 4, weekendRule: .previousBusinessDay, calendar: calendar)
        #expect(parts(due!) == [2026, 11, 4])
    }

    @Test func weekendIsKeptWhenShiftingIsOff() {
        let due = DueDateCalculator.dueDate(year: 2026, month: 11, dueDay: 7, weekendRule: .none, calendar: calendar)
        #expect(parts(due!) == [2026, 11, 7])
    }
}

// MARK: - Cutoffs

struct CutoffTests {
    @Test func cutoffsRunFromTheDayAfterOnePaydayToTheNext() {
        let cutoffs = CutoffCalculator.cutoffs(paydays: [10, 25], in: date(2026, 11, 15), calendar: calendar)
        #expect(cutoffs.count == 3)
        #expect(parts(cutoffs[0].startDate) == [2026, 10, 26])
        #expect(parts(cutoffs[0].endDate) == [2026, 11, 10])
        #expect(parts(cutoffs[1].startDate) == [2026, 11, 11])
        #expect(parts(cutoffs[1].endDate) == [2026, 11, 25])
        #expect(parts(cutoffs[2].startDate) == [2026, 11, 26])
        #expect(parts(cutoffs[2].endDate) == [2026, 12, 10])
    }

    @Test func aBillAfterTheLastPaydayBelongsToTheNextMonthsFirstCutoff() {
        let cutoff = CutoffCalculator.cutoff(containing: date(2026, 11, 28), paydays: [10, 25], calendar: calendar)
        #expect(cutoff.map { parts($0.startDate) } == [2026, 11, 26])
        #expect(cutoff.map { parts($0.endDate) } == [2026, 12, 10])
    }

    @Test func aPaydayPastTheEndOfAShortMonthMovesToItsLastDay() {
        let cutoffs = CutoffCalculator.cutoffs(paydays: [30], in: date(2026, 2, 10), calendar: calendar)
        let february = cutoffs.first { parts($0.endDate) == [2026, 2, 28] }
        #expect(february != nil)
        #expect(february.map { parts($0.startDate) } == [2026, 1, 31])
    }

    @Test func noPaydaysMeansNoCutoffs() {
        #expect(CutoffCalculator.cutoffs(paydays: [], in: date(2026, 11, 15), calendar: calendar).isEmpty)
    }

    @Test func everyDayFallsInExactlyOneCutoff() {
        let cutoffs = CutoffCalculator.cutoffs(paydays: [15, 30], in: date(2026, 11, 1), calendar: calendar)
        for day in 1...30 {
            let matching = cutoffs.filter { $0.contains(date(2026, 11, day), calendar: calendar) }
            #expect(matching.count == 1, "Nov \(day) should be in one cutoff")
        }
    }
}

// MARK: - Generating bills

@MainActor
struct InstanceGeneratorTests {
    private func fixedBill(in context: ModelContext, dueDay: Int = 15) -> Bill {
        let bill = Bill(name: "Rent")
        bill.amountType = .fixed
        bill.defaultAmount = 12_000
        bill.recurrence = .monthly
        bill.dueDay = dueDay
        bill.startDate = date(2026, 11, 1)
        context.insert(bill)
        return bill
    }

    @Test func aMonthlyBillGetsTheCurrentMonthAndThreeAhead() throws {
        let context = try makeContext()
        let bill = fixedBill(in: context)
        InstanceGenerator.generate(for: bill, now: date(2026, 11, 2), calendar: calendar, in: context)

        let keys = (bill.instances ?? []).map(\.periodKey).sorted()
        #expect(keys == [202611, 202612, 202701, 202702])
    }

    @Test func generatingAgainDoesNotDuplicate() throws {
        let context = try makeContext()
        let bill = fixedBill(in: context)
        InstanceGenerator.generate(for: bill, now: date(2026, 11, 2), calendar: calendar, in: context)
        InstanceGenerator.generate(for: bill, now: date(2026, 11, 2), calendar: calendar, in: context)
        #expect((bill.instances ?? []).count == 4)
    }

    @Test func aVariableAccountNeverGeneratesBills() throws {
        let context = try makeContext()
        let bill = fixedBill(in: context)
        bill.amountType = .variable
        bill.defaultAmount = nil
        InstanceGenerator.generate(for: bill, now: date(2026, 11, 2), calendar: calendar, in: context)
        #expect((bill.instances ?? []).isEmpty)
    }

    @Test func aOneTimeBillGetsASingleInstance() throws {
        let context = try makeContext()
        let bill = fixedBill(in: context)
        bill.recurrence = .once
        InstanceGenerator.generate(for: bill, now: date(2026, 11, 2), calendar: calendar, in: context)
        InstanceGenerator.generate(for: bill, now: date(2026, 11, 20), calendar: calendar, in: context)
        #expect((bill.instances ?? []).count == 1)
    }

    @Test func everyThreeMonthsSkipsTheMonthsBetween() throws {
        let context = try makeContext()
        let bill = fixedBill(in: context)
        bill.recurrence = .everyNMonths
        bill.recurrenceInterval = 3
        InstanceGenerator.generate(for: bill, now: date(2026, 11, 2), calendar: calendar, in: context)
        let keys = (bill.instances ?? []).map(\.periodKey).sorted()
        #expect(keys == [202611, 202702])
    }

    @Test func aPaidBillSurvivesRegeneration() throws {
        let context = try makeContext()
        let bill = fixedBill(in: context)
        InstanceGenerator.generate(for: bill, now: date(2026, 11, 2), calendar: calendar, in: context)
        let november = (bill.instances ?? []).first { $0.periodKey == 202611 }!
        november.markPaid(amount: 12_000, method: nil, in: context)

        bill.dueDay = 20
        InstanceGenerator.regenerate(for: bill, now: date(2026, 11, 2), calendar: calendar, in: context)

        #expect((bill.instances ?? []).contains { $0.periodKey == 202611 && $0.isPaid })
    }
}

// MARK: - Status and history

@MainActor
struct BillInstanceTests {
    private func instance(due: Date, paid: Bool = false) throws -> BillInstance {
        let context = try makeContext()
        let bill = Bill(name: "Meralco")
        context.insert(bill)
        let instance = bill.addInstance(dueDate: due, amount: 2_800, calendar: calendar, in: context)
        if paid { instance.markPaid(amount: 2_800, method: nil, date: due, in: context) }
        return instance
    }

    @Test func statusFollowsTheDueDate() throws {
        let today = date(2026, 11, 5)
        #expect(try instance(due: date(2026, 11, 5)).status(now: today, calendar: calendar) == .due)
        #expect(try instance(due: date(2026, 11, 9)).status(now: today, calendar: calendar) == .upcoming)
        #expect(try instance(due: date(2026, 11, 1)).status(now: today, calendar: calendar) == .overdue)
        #expect(try instance(due: date(2026, 11, 1), paid: true).status(now: today, calendar: calendar) == .paid)
    }

    @Test func daysOverdueCountsWholeDays() throws {
        let overdue = try instance(due: date(2026, 11, 1))
        #expect(overdue.daysOverdue(now: date(2026, 11, 4), calendar: calendar) == 3)
        #expect(try instance(due: date(2026, 11, 8)).daysOverdue(now: date(2026, 11, 4), calendar: calendar) == 0)
    }

    @Test func payingLateIsFlagged() throws {
        let context = try makeContext()
        let bill = Bill(name: "PLDT")
        context.insert(bill)
        let instance = bill.addInstance(dueDate: date(2026, 11, 5), amount: 1_699, calendar: calendar, in: context)
        instance.markPaid(amount: 1_699, method: nil, date: date(2026, 11, 8), in: context)
        #expect(instance.wasPaidLate(calendar: calendar))
    }

    @Test func percentChangeComparesWithThePreviousPaidBill() throws {
        let context = try makeContext()
        let bill = Bill(name: "Meralco")
        context.insert(bill)
        let october = bill.addInstance(dueDate: date(2026, 10, 5), amount: 1_000, calendar: calendar, in: context)
        october.markPaid(amount: 1_000, method: nil, date: date(2026, 10, 5), in: context)
        let november = bill.addInstance(dueDate: date(2026, 11, 5), amount: 1_100, calendar: calendar, in: context)

        let change = try #require(bill.percentChange(for: november))
        #expect(abs(change - 10) < 0.001)
    }

    @Test func aCustomPaymentMethodIsKeptByName() throws {
        let context = try makeContext()
        let bill = Bill(name: "Rent")
        context.insert(bill)
        let instance = bill.addInstance(dueDate: date(2026, 11, 5), amount: 500, calendar: calendar, in: context)
        let payment = instance.markPaid(amount: 500, method: .custom("Cash"), in: context)
        #expect(payment.choice == .custom("Cash"))
        #expect(payment.method == nil)
    }
}

// MARK: - Cutoff totals

@MainActor
struct CutoffSummaryTests {
    @Test func totalsCountOnlyBillsInsideTheCutoff() throws {
        let context = try makeContext()
        let bill = Bill(name: "Mixed")
        context.insert(bill)
        let inside1 = bill.addInstance(dueDate: date(2026, 11, 12), amount: 1_000, calendar: calendar, in: context)
        _ = bill.addInstance(dueDate: date(2026, 11, 20), amount: 500, calendar: calendar, in: context)
        _ = bill.addInstance(dueDate: date(2026, 11, 28), amount: 9_999, calendar: calendar, in: context)
        inside1.markPaid(amount: 1_000, method: nil, date: date(2026, 11, 12), in: context)

        let cutoff = try #require(
            CutoffCalculator.cutoff(containing: date(2026, 11, 15), paydays: [10, 25], calendar: calendar)
        )
        let summary = CutoffSummary(cutoff: cutoff, instances: bill.instances ?? [])
        #expect(summary.count == 2)
        #expect(summary.paidCount == 1)
        #expect(summary.total == 1_500)
        #expect(summary.leftToCover == 500)
    }
}

// MARK: - Parsing amounts

struct AmountParsingTests {
    @Test func parsesCommasAndCentavos() {
        #expect("2,345.60".parsedAmount == Decimal(string: "2345.60"))
    }

    @Test func ignoresAPesoSign() {
        #expect("₱1,000".parsedAmount == 1_000)
    }

    @Test func rejectsText() {
        #expect("abc".parsedAmount == nil)
    }
}
