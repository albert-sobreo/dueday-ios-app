import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A whole copy of the user's data as one JSON file, so bills survive a lost or replaced phone.
/// Importing only adds what's missing, matched by id, and never deletes or overwrites anything.
struct BackupFile: Codable {
    static let currentVersion = 1

    var version: Int = BackupFile.currentVersion
    var exportedAt: Date = .now
    var profiles: [ProfileRecord] = []
    var customProviders: [CustomProviderRecord] = []
    var customPaymentMethods: [CustomPaymentMethodRecord] = []
    var bills: [BillRecord] = []
    var instances: [InstanceRecord] = []
    var payments: [PaymentRecord] = []

    struct ProfileRecord: Codable {
        var id: UUID
        var name: String
        var kind: ProfileKind
        var colorHex: String
        var sortOrder: Int
        var paydays: [Int]
    }

    struct CustomProviderRecord: Codable {
        var id: UUID
        var name: String
        var category: BillCategory
        var amountType: AmountType
        var accountNumberLabel: String?
        var colorHex: String
        var logoData: Data?
    }

    struct CustomPaymentMethodRecord: Codable {
        var id: UUID
        var name: String
        var createdAt: Date
    }

    struct BillRecord: Codable {
        var id: UUID
        var name: String
        var presetID: String?
        var colorHex: String?
        var logoData: Data?
        var category: BillCategory
        var accountNumber: String?
        var amountType: AmountType
        /// Amounts are written as text, so no precision is lost to floating point.
        var defaultAmount: String?
        var recurrence: RecurrenceKind
        var recurrenceInterval: Int
        var startDate: Date
        var dueDay: Int
        var weekendRule: WeekendRule
        var reminderOffsets: [Int]
        var defaultPaymentMethod: PaymentMethod?
        var customPaymentName: String?
        var expectedDay: Int?
        /// Optional so backups made before these existed still import.
        var usualDueDay: Int?
        var remindsBeforeUsualDue: Bool?
        var liveActivityEnabled: Bool
        var isArchived: Bool
        var profileID: UUID?
    }

    struct InstanceRecord: Codable {
        var id: UUID
        var billID: UUID
        var dueDate: Date
        var createdAt: Date
        var periodKey: Int
        var amount: String?
        var isPaid: Bool
        var billingPeriod: String?
        var attachment: Data?
    }

    struct PaymentRecord: Codable {
        var id: UUID
        var instanceID: UUID
        var paidDate: Date
        var amountPaid: String
        var method: PaymentMethod?
        var customMethodName: String?
        var referenceNumber: String?
        var note: String?
    }
}

enum BackupError: LocalizedError {
    case unreadable
    case newerVersion

    var errorDescription: String? {
        switch self {
        case .unreadable: "This file isn't a DueDay backup."
        case .newerVersion: "This backup was made by a newer version of DueDay. Update the app, then try again."
        }
    }
}

/// What an import did, for the message shown afterwards.
struct RestoreSummary {
    var billsAdded = 0
    var paymentsAdded = 0
    /// Bills in the file that were already in the app.
    var billsSkipped = 0

    var message: String {
        if billsAdded == 0 && paymentsAdded == 0 {
            return "Everything in this backup is already in DueDay. Nothing was changed."
        }
        var parts = ["Added \(billsAdded) \(billsAdded == 1 ? "account" : "accounts")"]
        if paymentsAdded > 0 { parts.append("\(paymentsAdded) \(paymentsAdded == 1 ? "payment" : "payments")") }
        var text = parts.joined(separator: " and ") + "."
        if billsSkipped > 0 { text += " \(billsSkipped) were already here." }
        return text
    }
}

enum BackupManager {
    private static let posix = Locale(identifier: "en_US_POSIX")

    private static func text(_ value: Decimal?) -> String? {
        value.map { "\($0)" }
    }

    private static func decimal(_ text: String?) -> Decimal? {
        text.flatMap { Decimal(string: $0, locale: posix) }
    }

    // MARK: Export

    static func makeBackup(from context: ModelContext) throws -> Data {
        var file = BackupFile()

        file.profiles = try context.fetch(FetchDescriptor<Profile>(sortBy: [SortDescriptor(\.sortOrder)])).map {
            .init(id: $0.id, name: $0.name, kind: $0.kind, colorHex: $0.colorHex, sortOrder: $0.sortOrder, paydays: $0.paydays)
        }
        file.customProviders = try context.fetch(FetchDescriptor<CustomProvider>()).map {
            .init(
                id: $0.id, name: $0.name, category: $0.category, amountType: $0.amountType,
                accountNumberLabel: $0.accountNumberLabel, colorHex: $0.colorHex, logoData: $0.logoData
            )
        }
        file.customPaymentMethods = try context.fetch(FetchDescriptor<CustomPaymentMethod>()).map {
            .init(id: $0.id, name: $0.name, createdAt: $0.createdAt)
        }
        file.bills = try context.fetch(FetchDescriptor<Bill>()).map {
            .init(
                id: $0.id, name: $0.name, presetID: $0.presetID, colorHex: $0.colorHex, logoData: $0.logoData,
                category: $0.category, accountNumber: $0.accountNumber, amountType: $0.amountType,
                defaultAmount: text($0.defaultAmount), recurrence: $0.recurrence,
                recurrenceInterval: $0.recurrenceInterval, startDate: $0.startDate, dueDay: $0.dueDay,
                weekendRule: $0.weekendRule, reminderOffsets: $0.reminderOffsets,
                defaultPaymentMethod: $0.defaultPaymentMethod, customPaymentName: $0.customPaymentName,
                expectedDay: $0.expectedDay, usualDueDay: $0.usualDueDay,
                remindsBeforeUsualDue: $0.remindsBeforeUsualDue, liveActivityEnabled: $0.liveActivityEnabled,
                isArchived: $0.isArchived, profileID: $0.profile?.id
            )
        }
        file.instances = try context.fetch(FetchDescriptor<BillInstance>()).compactMap { instance in
            guard let billID = instance.bill?.id else { return nil }
            return .init(
                id: instance.id, billID: billID, dueDate: instance.dueDate, createdAt: instance.createdAt,
                periodKey: instance.periodKey, amount: text(instance.amount), isPaid: instance.isPaid,
                billingPeriod: instance.billingPeriod, attachment: instance.attachment
            )
        }
        file.payments = try context.fetch(FetchDescriptor<Payment>()).compactMap { payment in
            guard let instanceID = payment.instance?.id else { return nil }
            return .init(
                id: payment.id, instanceID: instanceID, paidDate: payment.paidDate,
                amountPaid: "\(payment.amountPaid)", method: payment.method,
                customMethodName: payment.customMethodName, referenceNumber: payment.referenceNumber,
                note: payment.note
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    // MARK: Import

    /// Adds everything in the backup that isn't in the app yet, then brings generated bills,
    /// reminders and the selected profile up to date.
    @discardableResult
    static func restore(_ data: Data, into context: ModelContext) async throws -> RestoreSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(BackupFile.self, from: data) else { throw BackupError.unreadable }
        guard file.version <= BackupFile.currentVersion else { throw BackupError.newerVersion }

        var summary = RestoreSummary()

        // On a fresh install the app has made an empty default profile. Drop it, so the
        // restored "Personal" isn't listed twice.
        var profiles = try context.fetch(FetchDescriptor<Profile>())
        let hasBills = !(try context.fetch(FetchDescriptor<Bill>())).isEmpty
        if !hasBills, !file.profiles.isEmpty {
            let backedUp = Set(file.profiles.map(\.id))
            let stale = profiles.filter { ($0.bills ?? []).isEmpty && !backedUp.contains($0.id) }
            let staleIDs = Set(stale.map(\.id))
            for profile in stale { context.delete(profile) }
            profiles.removeAll { staleIDs.contains($0.id) }
        }

        var profilesByID = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for record in file.profiles where profilesByID[record.id] == nil {
            let profile = Profile(name: record.name, kind: record.kind)
            profile.id = record.id
            profile.colorHex = record.colorHex
            profile.sortOrder = record.sortOrder
            profile.paydays = record.paydays
            context.insert(profile)
            profilesByID[record.id] = profile
        }

        let providerIDs = Set(try context.fetch(FetchDescriptor<CustomProvider>()).map(\.id))
        for record in file.customProviders where !providerIDs.contains(record.id) {
            let provider = CustomProvider(name: record.name, category: record.category)
            provider.id = record.id
            provider.amountType = record.amountType
            provider.accountNumberLabel = record.accountNumberLabel
            provider.colorHex = record.colorHex
            provider.logoData = record.logoData
            context.insert(provider)
        }

        let methodNames = Set(try context.fetch(FetchDescriptor<CustomPaymentMethod>()).map(\.name))
        for record in file.customPaymentMethods where !methodNames.contains(record.name) {
            let method = CustomPaymentMethod(name: record.name)
            method.id = record.id
            method.createdAt = record.createdAt
            context.insert(method)
        }

        var billsByID = Dictionary(
            try context.fetch(FetchDescriptor<Bill>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        for record in file.bills {
            if billsByID[record.id] != nil {
                summary.billsSkipped += 1
                continue
            }
            let bill = Bill(name: record.name)
            bill.id = record.id
            bill.presetID = record.presetID
            bill.colorHex = record.colorHex
            bill.logoData = record.logoData
            bill.category = record.category
            bill.accountNumber = record.accountNumber
            bill.amountType = record.amountType
            bill.defaultAmount = decimal(record.defaultAmount)
            bill.recurrence = record.recurrence
            bill.recurrenceInterval = record.recurrenceInterval
            bill.startDate = record.startDate
            bill.dueDay = record.dueDay
            bill.weekendRule = record.weekendRule
            bill.reminderOffsets = record.reminderOffsets
            bill.defaultPaymentMethod = record.defaultPaymentMethod
            bill.customPaymentName = record.customPaymentName
            bill.expectedDay = record.expectedDay
            bill.usualDueDay = record.usualDueDay
            bill.remindsBeforeUsualDue = record.remindsBeforeUsualDue ?? true
            bill.liveActivityEnabled = record.liveActivityEnabled
            bill.isArchived = record.isArchived
            bill.profile = record.profileID.flatMap { profilesByID[$0] }
            context.insert(bill)
            billsByID[record.id] = bill
            summary.billsAdded += 1
        }

        var instancesByID = Dictionary(
            try context.fetch(FetchDescriptor<BillInstance>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        for record in file.instances where instancesByID[record.id] == nil {
            guard let bill = billsByID[record.billID] else { continue }
            let instance = BillInstance(bill: bill, dueDate: record.dueDate, periodKey: record.periodKey, amount: decimal(record.amount))
            instance.id = record.id
            instance.createdAt = record.createdAt
            instance.isPaid = record.isPaid
            instance.billingPeriod = record.billingPeriod
            instance.attachment = record.attachment
            context.insert(instance)
            instancesByID[record.id] = instance
        }

        let paymentIDs = Set(try context.fetch(FetchDescriptor<Payment>()).map(\.id))
        for record in file.payments where !paymentIDs.contains(record.id) {
            guard let instance = instancesByID[record.instanceID] else { continue }
            let payment = Payment(
                instance: instance, paidDate: record.paidDate,
                amountPaid: decimal(record.amountPaid) ?? 0, method: record.method
            )
            payment.id = record.id
            payment.customMethodName = record.customMethodName
            payment.referenceNumber = record.referenceNumber
            payment.note = record.note
            context.insert(payment)
            summary.paymentsAdded += 1
        }

        try context.save()

        ProfileSeeder.ensureDefault(in: context)
        InstanceGenerator.generateAll(in: context)
        try context.save()
        selectAvailableProfile(in: context)
        await ReminderScheduler.reschedule(in: context)
        return summary
    }

    /// If the remembered profile is gone (a fresh install's default was replaced by the backup's),
    /// fall back to the first one. "All" is stored as an empty value and is left alone.
    private static func selectAvailableProfile(in context: ModelContext) {
        let saved = UserDefaults.standard.string(forKey: selectedProfileKey) ?? ""
        guard !saved.isEmpty else { return }
        let profiles = (try? context.fetch(FetchDescriptor<Profile>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        if !profiles.contains(where: { $0.id.uuidString == saved }), let first = profiles.first {
            UserDefaults.standard.set(first.id.uuidString, forKey: selectedProfileKey)
        }
    }
}

/// Wraps the backup data so the system file exporter can save it.
struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
