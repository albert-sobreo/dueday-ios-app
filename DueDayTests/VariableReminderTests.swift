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

@MainActor private var reminderContainers: [ModelContainer] = []

/// Reminders for variable accounts (like electricity) whose bill for the month hasn't been added yet.
@MainActor
struct VariableReminderTests {
    /// Today is 5 Nov 2026.
    private let today = date(2026, 11, 5)

    private func account(usualDueDay: Int? = 20, expectedDay: Int? = nil) throws -> (Bill, ModelContext) {
        let container = try ModelContainer(
            for: Profile.self, CustomProvider.self, CustomPaymentMethod.self,
            Bill.self, BillInstance.self, Payment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        reminderContainers.append(container)
        let context = container.mainContext
        let bill = Bill(name: "Meralco")
        bill.amountType = .variable
        bill.recurrence = .once
        bill.usualDueDay = usualDueDay
        bill.expectedDay = expectedDay
        context.insert(bill)
        return (bill, context)
    }

    private func days(_ dates: [Date]) -> [Int] {
        dates.map { calendar.component(.month, from: $0) * 100 + calendar.component(.day, from: $0) }
    }

    @Test func awaitsThisMonthAndNextWhenNoBillWasAdded() throws {
        let (bill, _) = try account()
        #expect(days(bill.awaitedDueDates(now: today, calendar: calendar)) == [1120, 1220])
    }

    @Test func aBillDueNearTheUsualDayStopsThatMonth() throws {
        let (bill, context) = try account()
        // Came in due a few days early.
        bill.addInstance(dueDate: date(2026, 11, 17), amount: 2_450, calendar: calendar, in: context)
        #expect(days(bill.awaitedDueDates(now: today, calendar: calendar)) == [1220])
    }

    @Test func usesTheLatestBillsDueDayWhenNoneIsSet() throws {
        let (bill, context) = try account(usualDueDay: nil)
        bill.addInstance(dueDate: date(2026, 10, 12), amount: 2_300, calendar: calendar, in: context)
        #expect(bill.expectedDueDay(calendar: calendar) == 12)
        #expect(days(bill.awaitedDueDates(now: today, calendar: calendar)) == [1112, 1212])
    }

    @Test func nothingWithoutAUsualDueDay() throws {
        let (bill, _) = try account(usualDueDay: nil)
        #expect(bill.awaitedDueDates(now: today, calendar: calendar).isEmpty)
    }

    @Test func nothingWhenTurnedOff() throws {
        let (bill, _) = try account()
        bill.remindsBeforeUsualDue = false
        #expect(bill.awaitedDueDates(now: today, calendar: calendar).isEmpty)
    }

    @Test func fixedBillsAreNeverAwaited() throws {
        let (bill, _) = try account()
        bill.amountType = .fixed
        #expect(bill.awaitedDueDates(now: today, calendar: calendar).isEmpty)
    }

    @Test func shortMonthsUseTheirLastDay() throws {
        let (bill, _) = try account(usualDueDay: 31)
        #expect(days(bill.awaitedDueDates(now: today, calendar: calendar)) == [1130, 1231])
    }

    @Test func awaitedRemindersSayTheAmountIsMissing() {
        #expect(ReminderScheduler.awaitedBody(daysBefore: 0) == "Usually due today · Amount not added yet")
        #expect(ReminderScheduler.awaitedBody(daysBefore: 3) == "Usually due in 3 days · Amount not added yet")
    }

    @Test func nudgeRepeatsUntilTheBillIsAdded() throws {
        let (bill, _) = try account(expectedDay: 10)
        let nudges = ReminderScheduler.nudgeDates(for: bill, now: today, calendar: calendar)
        #expect(days(nudges) == [1110, 1113, 1116, 1210, 1213, 1216])
    }

    @Test func nudgeSkipsAMonthOnceItsBillIsAdded() throws {
        let (bill, context) = try account(expectedDay: 3)
        let instance = bill.addInstance(dueDate: date(2026, 11, 14), amount: 2_450, calendar: calendar, in: context)
        instance.createdAt = date(2026, 11, 4)
        let nudges = ReminderScheduler.nudgeDates(for: bill, now: today, calendar: calendar)
        #expect(days(nudges) == [1203, 1206, 1209])
    }

    @Test func pastNudgesAreDropped() throws {
        // Arrives on the 1st: the 1st and 4th have passed, the 7th is still ahead.
        let (bill, _) = try account(expectedDay: 1)
        let nudges = ReminderScheduler.nudgeDates(for: bill, now: today, calendar: calendar)
        #expect(days(nudges) == [1107, 1201, 1204, 1207])
    }

    @Test func noNudgeWhenTurnedOff() throws {
        let (bill, _) = try account(expectedDay: nil)
        #expect(ReminderScheduler.nudgeDates(for: bill, now: today, calendar: calendar).isEmpty)
    }

    @Test func newAccountsGuessArrivalTenDaysBeforeDue() {
        #expect(NewAccountView.arrivalDay(forDueDay: 25) == 15)
        #expect(NewAccountView.arrivalDay(forDueDay: 5) == 25)
    }
}
