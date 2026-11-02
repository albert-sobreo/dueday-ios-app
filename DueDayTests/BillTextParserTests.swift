import Foundation
import Testing
@testable import DueDay

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func parts(_ date: Date?) -> [Int]? {
    guard let date else { return nil }
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return [c.year!, c.month!, c.day!]
}

@MainActor
struct BillTextParserTests {
    private let presets = PresetStore.all

    @Test func readsAMeralcoStyleBill() {
        let lines = [
            "MERALCO",
            "Customer Account Number",
            "2011-4589-321",
            "Billing Period Sep 28 - Oct 27, 2026",
            "Previous Balance 2,598.00",
            "Total Amount Due ₱2,845.60",
            "Due Date Nov 5, 2026",
        ]
        let bill = BillTextParser.parse(lines: lines, presets: presets, calendar: calendar)
        #expect(bill.presetID == "meralco")
        #expect(bill.amount == Decimal(string: "2845.60"))
        #expect(parts(bill.dueDate) == [2026, 11, 5])
        #expect(bill.accountNumber == "2011-4589-321")
        #expect(bill.billingPeriod?.contains("Sep 28") == true)
    }

    @Test func prefersTotalAmountDueOverAPreviousBalance() {
        let lines = ["Previous balance 5,000.00", "Total Amount Due", "1,234.50"]
        let bill = BillTextParser.parse(lines: lines, presets: presets, calendar: calendar)
        #expect(bill.amount == Decimal(string: "1234.50"))
    }

    @Test func readsDifferentDateFormats() {
        #expect(parts(BillTextParser.findDate(in: "Due 15 Nov 2026", calendar: calendar)) == [2026, 11, 15])
        #expect(parts(BillTextParser.findDate(in: "15-Nov-2026", calendar: calendar)) == [2026, 11, 15])
        #expect(parts(BillTextParser.findDate(in: "November 15, 2026", calendar: calendar)) == [2026, 11, 15])
        #expect(parts(BillTextParser.findDate(in: "11/15/2026", calendar: calendar)) == [2026, 11, 15])
    }

    @Test func shortKeywordsMustBeWholeWords() {
        // "SKY" appears inside "SKYLINE", which isn't the biller Sky.
        let bill = BillTextParser.parse(lines: ["SKYLINE VILLAS", "Total Amount Due 100.00"], presets: presets, calendar: calendar)
        #expect(bill.presetID == nil)
    }

    @Test func missingThingsAreLeftEmpty() {
        let bill = BillTextParser.parse(lines: ["Thank you for your payment"], presets: presets, calendar: calendar)
        #expect(bill.amount == nil)
        #expect(bill.dueDate == nil)
        #expect(bill.accountNumber == nil)
    }
}
