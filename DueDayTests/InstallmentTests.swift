import Foundation
import SwiftData
import Testing
@testable import DueDay

private let planCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    planCalendar.date(from: DateComponents(year: year, month: month, day: day))!
}

/// A context doesn't keep its container alive, so containers are held here for the whole test run.
@MainActor private var planContainers: [ModelContainer] = []

@MainActor
private func makePlanContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: Profile.self, CustomProvider.self, CustomPaymentMethod.self,
        Bill.self, BillInstance.self, Payment.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    planContainers.append(container)
    return container.mainContext
}

@MainActor
struct InstallmentTests {
    /// A phone plan: `count` monthly payments of ₱2,000 due on the 15th, the first in `start`.
    private func phonePlan(
        count: Int,
        paidBefore: Int = 0,
        starting start: Date = day(2026, 11, 15),
        recurrence: RecurrenceKind = .monthly,
        in context: ModelContext
    ) -> Bill {
        let bill = Bill(name: "iPhone")
        bill.amountType = .fixed
        bill.defaultAmount = 2000
        bill.recurrence = recurrence
        bill.startDate = start
        bill.dueDay = planCalendar.component(.day, from: start)
        bill.installmentCount = count
        bill.installmentsPaidBefore = paidBefore
        context.insert(bill)
        return bill
    }

    private func sorted(_ bill: Bill) -> [BillInstance] {
        (bill.instances ?? []).sorted { $0.dueDate < $1.dueDate }
    }

    /// Pays every open payment in order, generating ahead each month as the app would.
    private func payAll(_ bill: Bill, from start: Date, months: Int, in context: ModelContext) throws {
        for offset in 0..<months {
            let now = planCalendar.date(byAdding: .month, value: offset, to: start)!
            InstanceGenerator.generate(for: bill, now: now, calendar: planCalendar, in: context)
            for instance in sorted(bill) where !instance.isPaid && instance.dueDate <= now {
                instance.markPaid(amount: instance.amount ?? 0, method: nil, date: now, in: context)
            }
            try context.save()
        }
    }

    @Test func paymentsAreNumberedFromOne() throws {
        let context = try makePlanContext()
        let bill = phonePlan(count: 24, in: context)
        InstanceGenerator.generate(for: bill, now: day(2026, 11, 1), calendar: planCalendar, in: context)

        let numbers = sorted(bill).map(\.installmentNumber)
        #expect(numbers == [1, 2, 3, 4])                       // November through February.
        #expect(sorted(bill).first?.installmentLabel == "1 of 24")
    }

    @Test func generationStopsAtTheLastPayment() throws {
        let context = try makePlanContext()
        let bill = phonePlan(count: 3, in: context)
        InstanceGenerator.generate(for: bill, now: day(2026, 11, 1), calendar: planCalendar, in: context)

        let instances = sorted(bill)
        #expect(instances.count == 3)
        #expect(instances.last?.dueDate == day(2027, 1, 15))
        #expect(instances.last?.isFinalInstallment == true)

        // Months later, nothing more is added.
        InstanceGenerator.generate(for: bill, now: day(2027, 3, 1), calendar: planCalendar, in: context)
        #expect((bill.instances ?? []).count == 3)
    }

    @Test func alreadyPaidPaymentsShiftTheNumbers() throws {
        let context = try makePlanContext()
        let bill = phonePlan(count: 24, paidBefore: 21, in: context)
        InstanceGenerator.generate(for: bill, now: day(2026, 11, 1), calendar: planCalendar, in: context)

        #expect(sorted(bill).map(\.installmentNumber) == [22, 23, 24])
        #expect(bill.installmentsPaid == 21)
        #expect(bill.installmentsLeft == 3)
        #expect(bill.remainingBalance == 6000)
        #expect(bill.installmentPlanTotal == 48000)
        #expect(bill.finalInstallmentDueDate(calendar: planCalendar) == day(2027, 1, 15))
    }

    @Test func everyNMonthsAndWeeklyPlansStopToo() throws {
        let context = try makePlanContext()
        let quarterly = phonePlan(count: 2, recurrence: .everyNMonths, in: context)
        quarterly.recurrenceInterval = 3
        InstanceGenerator.generate(for: quarterly, monthsAhead: 12, now: day(2026, 11, 1), calendar: planCalendar, in: context)
        #expect(sorted(quarterly).map(\.dueDate) == [day(2026, 11, 15), day(2027, 2, 15)])

        let weekly = phonePlan(count: 5, starting: day(2026, 11, 2), recurrence: .weekly, in: context)
        InstanceGenerator.generate(for: weekly, now: day(2026, 11, 1), calendar: planCalendar, in: context)
        #expect(sorted(weekly).map(\.installmentNumber) == [1, 2, 3, 4, 5])
        #expect(sorted(weekly).last?.dueDate == day(2026, 11, 30))
    }

    @Test func aTotalPriceIsSplitWithTheRoundingOnTheLastPayment() throws {
        let context = try makePlanContext()
        let bill = phonePlan(count: 3, in: context)
        bill.installmentTotal = 1000
        bill.defaultAmount = Bill.perPaymentAmount(total: 1000, count: 3)
        #expect(bill.defaultAmount == Decimal(string: "333.33"))

        InstanceGenerator.generate(for: bill, now: day(2026, 11, 1), calendar: planCalendar, in: context)
        let amounts = sorted(bill).compactMap(\.amount)
        #expect(amounts == [Decimal(string: "333.33")!, Decimal(string: "333.33")!, Decimal(string: "333.34")!])
        #expect(bill.remainingBalance == 1000)
    }

    @Test func payingTheLastPaymentClosesThePlan() throws {
        let context = try makePlanContext()
        let bill = phonePlan(count: 3, in: context)
        try payAll(bill, from: day(2026, 11, 20), months: 2, in: context)
        #expect(!bill.isPaidOff)
        #expect(!bill.isArchived)
        #expect(bill.installmentsPaid == 2)

        try payAll(bill, from: day(2027, 1, 20), months: 1, in: context)
        #expect(bill.isPaidOff)
        #expect(bill.isArchived)
        #expect(bill.installmentsPaid == 3)
        #expect(bill.remainingBalance == 0)
        #expect(bill.installmentPlanTotal == 6000)
    }

    @Test func undoingTheLastPaymentReopensThePlan() throws {
        let context = try makePlanContext()
        let bill = phonePlan(count: 2, in: context)
        try payAll(bill, from: day(2026, 11, 20), months: 2, in: context)
        #expect(bill.isArchived)

        sorted(bill).last?.markUnpaid(in: context)
        #expect(!bill.isPaidOff)
        #expect(!bill.isArchived)
        #expect(bill.installmentsLeft == 1)
    }

    @Test func outOfOrderPaymentDoesNotCloseThePlanEarly() throws {
        let context = try makePlanContext()
        let bill = phonePlan(count: 3, in: context)
        InstanceGenerator.generate(for: bill, now: day(2026, 11, 1), calendar: planCalendar, in: context)
        let last = try #require(sorted(bill).last)
        last.markPaid(amount: 2000, method: nil, in: context)
        #expect(!bill.isPaidOff)
        #expect(!bill.isArchived)
    }

    @Test func anEditedPaymentAmountCountsInTheBalance() throws {
        let context = try makePlanContext()
        let bill = phonePlan(count: 24, in: context)
        InstanceGenerator.generate(for: bill, now: day(2026, 11, 1), calendar: planCalendar, in: context)
        sorted(bill).first?.amount = 2500
        #expect(bill.remainingBalance == 2500 + 2000 * 23)
    }

    @Test func editingKeepsPaidNumbersAndRebuildsTheRest() throws {
        let context = try makePlanContext()
        let bill = phonePlan(count: 6, in: context)
        try payAll(bill, from: day(2026, 11, 20), months: 2, in: context)

        // Stretch the plan to 8 payments of ₱1,500 in January.
        bill.installmentCount = 8
        bill.defaultAmount = 1500
        InstanceGenerator.regenerate(for: bill, now: day(2027, 1, 1), calendar: planCalendar, in: context)

        let paid = sorted(bill).filter(\.isPaid)
        #expect(paid.map(\.installmentNumber) == [1, 2])
        #expect(paid.compactMap(\.amount) == [2000, 2000])
        let open = sorted(bill).filter { !$0.isPaid }
        #expect(open.first?.installmentNumber == 3)
        #expect(open.first?.amount == 1500)
        #expect(bill.remainingBalance == 1500 * 6)
    }

    @Test func payingOffEarlySettlesTheRest() throws {
        let context = try makePlanContext()
        let bill = phonePlan(count: 24, in: context)
        try payAll(bill, from: day(2026, 11, 20), months: 1, in: context)
        #expect(bill.installmentsPaid == 1)

        bill.payOffRemaining(amount: 40000, method: nil, date: day(2026, 12, 1), calendar: planCalendar, in: context)
        #expect(bill.isPaidOff)
        #expect(bill.isArchived)
        #expect(bill.installmentsPaid == 24)
        #expect(bill.installmentPlanTotal == 42000)
        #expect((bill.instances ?? []).allSatisfy(\.isPaid))

        // A paid-off plan is never generated again.
        InstanceGenerator.generate(for: bill, now: day(2027, 2, 1), calendar: planCalendar, in: context)
        #expect((bill.instances ?? []).count == 2)
    }

    @Test func aOneTimeBillIsNeverAnInstallment() throws {
        let context = try makePlanContext()
        let bill = phonePlan(count: 12, recurrence: .once, in: context)
        #expect(!bill.isInstallment)
        InstanceGenerator.generate(for: bill, now: day(2026, 11, 1), calendar: planCalendar, in: context)
        #expect(sorted(bill).first?.installmentNumber == nil)
    }

    @Test func theFormDraftSavesAndLoadsBothWaysOfEntering() throws {
        let context = try makePlanContext()
        let bill = phonePlan(count: 2, in: context)

        var draft = InstallmentDraft()
        draft.isOn = true
        draft.countText = "24"
        draft.paidBeforeText = "5"
        draft.entry = .total
        #expect(draft.isValid())
        draft.apply(to: bill, amount: 48000)
        #expect(bill.installmentCount == 24)
        #expect(bill.installmentsPaidBefore == 5)
        #expect(bill.installmentTotal == 48000)
        #expect(bill.defaultAmount == 2000)
        #expect(InstallmentDraft(bill: bill) == draft)

        draft.entry = .perPayment
        draft.apply(to: bill, amount: 1999)
        #expect(bill.installmentTotal == nil)
        #expect(bill.defaultAmount == 1999)

        draft.isOn = false
        draft.apply(to: bill, amount: 1999)
        #expect(bill.installmentCount == nil)
        #expect(!bill.isInstallment)

        var invalid = InstallmentDraft()
        invalid.isOn = true
        invalid.countText = "3"
        invalid.paidBeforeText = "3"
        #expect(!invalid.isValid())
        #expect(!invalid.isValid(minimumCount: 4))
    }

    @Test func plansSurviveABackup() async throws {
        let source = try makePlanContext()
        let bill = phonePlan(count: 24, paidBefore: 5, in: source)
        bill.installmentTotal = 48000
        InstanceGenerator.generate(for: bill, now: day(2026, 11, 1), calendar: planCalendar, in: source)
        try source.save()
        let data = try BackupManager.makeBackup(from: source)

        let target = try makePlanContext()
        try await BackupManager.restore(data, into: target)
        let restored = try #require(try target.fetch(FetchDescriptor<Bill>()).first)
        #expect(restored.installmentCount == 24)
        #expect(restored.installmentsPaidBefore == 5)
        #expect(restored.installmentTotal == 48000)
        #expect((restored.instances ?? []).contains { $0.installmentNumber == 6 })
    }

    @Test func backupsFromBeforeInstallmentsStillImport() throws {
        let decoder = JSONDecoder()
        let json = """
        {"id":"6F1B1C1A-0000-4000-8000-000000000001","name":"Rent","category":"housing","amountType":"fixed",
         "recurrence":"monthly","recurrenceInterval":1,"startDate":0,"dueDay":5,"weekendRule":"none",
         "reminderOffsets":[3,0],"liveActivityEnabled":false,"isArchived":false}
        """
        let record = try decoder.decode(BackupFile.BillRecord.self, from: Data(json.utf8))
        #expect(record.installmentCount == nil)
        #expect(record.installmentsPaidBefore == nil)
    }
}
