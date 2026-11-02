import Foundation
import SwiftData
import Testing
@testable import DueDay

/// A context doesn't keep its container alive, so containers are held here for the whole test run.
@MainActor private var backupContainers: [ModelContainer] = []

@MainActor
private func makeBackupContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: Profile.self, CustomProvider.self, CustomPaymentMethod.self,
        Bill.self, BillInstance.self, Payment.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    backupContainers.append(container)
    return container.mainContext
}

@MainActor
struct BackupTests {
    /// One profile with one paid bill, as a user's data would look.
    private func populate(_ context: ModelContext) throws -> (profile: Profile, bill: Bill) {
        let profile = Profile(name: "Personal")
        profile.paydays = [10, 25]
        context.insert(profile)

        let bill = Bill(name: "Meralco")
        bill.defaultAmount = Decimal(string: "1234.56")
        bill.dueDay = 20
        bill.reminderOffsets = [7, 1, 0]
        bill.profile = profile
        context.insert(bill)

        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let instance = BillInstance(bill: bill, dueDate: due, periodKey: 202_701, amount: Decimal(string: "1234.56"))
        context.insert(instance)
        instance.markPaid(amount: Decimal(string: "1234.56")!, method: .builtIn(.gcash), note: "Paid early", in: context)
        try context.save()
        return (profile, bill)
    }

    @Test func aBackupRestoresIntoAFreshStore() async throws {
        let source = try makeBackupContext()
        let original = try populate(source)
        let data = try BackupManager.makeBackup(from: source)

        let target = try makeBackupContext()
        // A fresh install already has its own empty Personal profile.
        ProfileSeeder.ensureDefault(in: target)

        let summary = try await BackupManager.restore(data, into: target)
        #expect(summary.billsAdded == 1)
        #expect(summary.paymentsAdded == 1)

        let profiles = try target.fetch(FetchDescriptor<Profile>())
        #expect(profiles.count == 1)
        #expect(profiles.first?.id == original.profile.id)
        #expect(profiles.first?.paydays == [10, 25])

        let bills = try target.fetch(FetchDescriptor<Bill>())
        #expect(bills.count == 1)
        let restored = try #require(bills.first)
        #expect(restored.id == original.bill.id)
        #expect(restored.defaultAmount == Decimal(string: "1234.56"))
        #expect(restored.reminderOffsets == [7, 1, 0])
        #expect(restored.profile?.id == original.profile.id)

        let payment = try #require(try target.fetch(FetchDescriptor<Payment>()).first)
        #expect(payment.amountPaid == Decimal(string: "1234.56"))
        #expect(payment.method == .gcash)
        #expect(payment.note == "Paid early")
        #expect(payment.instance?.isPaid == true)
    }

    @Test func importingTheSameBackupTwiceAddsNothing() async throws {
        let source = try makeBackupContext()
        _ = try populate(source)
        let data = try BackupManager.makeBackup(from: source)

        let target = try makeBackupContext()
        _ = try await BackupManager.restore(data, into: target)
        let second = try await BackupManager.restore(data, into: target)

        #expect(second.billsAdded == 0)
        #expect(second.paymentsAdded == 0)
        #expect(try target.fetch(FetchDescriptor<Bill>()).count == 1)
        #expect(try target.fetch(FetchDescriptor<Payment>()).count == 1)
        #expect(try target.fetch(FetchDescriptor<Profile>()).count == 1)
    }

    @Test func importingKeepsWhatIsAlreadyThere() async throws {
        let source = try makeBackupContext()
        _ = try populate(source)
        let data = try BackupManager.makeBackup(from: source)

        let target = try makeBackupContext()
        let profile = Profile(name: "Business")
        target.insert(profile)
        let existing = Bill(name: "Rent")
        existing.profile = profile
        target.insert(existing)
        try target.save()

        _ = try await BackupManager.restore(data, into: target)

        let names = Set(try target.fetch(FetchDescriptor<Bill>()).map(\.name))
        #expect(names == ["Rent", "Meralco"])
        #expect(try target.fetch(FetchDescriptor<Profile>()).count == 2)
    }

    @Test func aFileThatIsNotABackupIsRejected() async throws {
        let target = try makeBackupContext()
        await #expect(throws: BackupError.self) {
            try await BackupManager.restore(Data("not a backup".utf8), into: target)
        }
    }
}
