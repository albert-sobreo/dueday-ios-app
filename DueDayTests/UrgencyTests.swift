import Foundation
import SwiftData
import Testing
@testable import DueDay

private let urgencyCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    urgencyCalendar.date(from: DateComponents(year: year, month: month, day: day))!
}

/// "Today" for every test: Tuesday 3 November 2026.
private let today = date(2026, 11, 3)

private func instance(due: Date, amountType: AmountType = .fixed) -> BillInstance {
    let bill = Bill(name: "Test")
    bill.amountType = amountType
    return BillInstance(bill: bill, dueDate: due, periodKey: 0, amount: 100)
}

struct UrgencyTests {
    @Test func aFixedBillAMonthAwayIsNotUrgent() {
        #expect(!instance(due: date(2026, 12, 3)).isUrgent(cutoff: nil, now: today, calendar: urgencyCalendar))
    }

    @Test func overdueDueTodayAndDueWithinAWeekAreUrgent() {
        for due in [date(2026, 11, 1), date(2026, 11, 3), date(2026, 11, 10)] {
            #expect(instance(due: due).isUrgent(cutoff: nil, now: today, calendar: urgencyCalendar))
        }
    }

    @Test func eightDaysAwayIsNotUrgentWithoutACutoff() {
        #expect(!instance(due: date(2026, 11, 11)).isUrgent(cutoff: nil, now: today, calendar: urgencyCalendar))
    }

    @Test func aBillInTheCurrentCutoffIsUrgentEvenBeyondAWeek() throws {
        let cutoff = try #require(CutoffCalculator.cutoff(containing: today, paydays: [15, 30], calendar: urgencyCalendar))
        // 14 November is 11 days away, but before the 15th payday.
        #expect(instance(due: date(2026, 11, 14)).isUrgent(cutoff: cutoff, now: today, calendar: urgencyCalendar))
        // 20 November belongs to the next cutoff.
        #expect(!instance(due: date(2026, 11, 20)).isUrgent(cutoff: cutoff, now: today, calendar: urgencyCalendar))
    }

    @Test func aVariableBillIsAlwaysUrgentBecauseSomeoneAddedIt() {
        #expect(instance(due: date(2026, 12, 20), amountType: .variable)
            .isUrgent(cutoff: nil, now: today, calendar: urgencyCalendar))
    }
}
