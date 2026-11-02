import AppIntents
import Foundation
import SwiftData

// Shortcuts and Siri: "What's due this week in DueDay" and "Mark Meralco as paid in DueDay".
// Intent types are nonisolated, as App Intents expects; the work that touches the database hops to
// the main actor.

// MARK: - Bill entity

/// A saved bill or account, as Shortcuts and Siri see it. The id is the bill's own UUID, which stays
/// the same across launches and devices.
nonisolated struct BillEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Bill")
    static let defaultQuery = BillEntityQuery()

    var id: UUID
    @Property(title: "Name") var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

nonisolated struct BillEntityQuery: EntityStringQuery {
    /// One batch lookup for the ids the system already holds. Bills that were deleted are left out.
    func entities(for identifiers: [UUID]) async throws -> [BillEntity] {
        await MainActor.run {
            activeBills().filter { identifiers.contains($0.id) }.map { BillEntity(id: $0.id, name: $0.name) }
        }
    }

    /// Typed search in the picker: the framework doesn't filter for us, so we match the name here.
    func entities(matching string: String) async throws -> [BillEntity] {
        await MainActor.run {
            activeBills()
                .filter { $0.name.localizedStandardContains(string) }
                .map { BillEntity(id: $0.id, name: $0.name) }
        }
    }

    /// What the picker shows before anything is typed.
    func suggestedEntities() async throws -> [BillEntity] {
        await MainActor.run {
            activeBills().prefix(20).map { BillEntity(id: $0.id, name: $0.name) }
        }
    }

    @MainActor
    private func activeBills() -> [Bill] {
        let descriptor = FetchDescriptor<Bill>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? AppContainer.shared.mainContext.fetch(descriptor)) ?? []
    }
}

// MARK: - Errors

nonisolated enum DueDayIntentError: Error, CustomLocalizedStringResourceConvertible {
    case billNotFound
    case nothingToPay(String)
    case amountUnknown(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .billNotFound:
            "That bill couldn't be found."
        case .nothingToPay(let name):
            "There's no unpaid bill for \(name)."
        case .amountUnknown(let name):
            "\(name) has no amount yet. Open DueDay to add it."
        }
    }
}

// MARK: - What's due

nonisolated struct WhatsDueIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Due This Week"
    static let description = IntentDescription("Tells you which bills are overdue or due in the next 7 days.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let context = AppContainer.shared.mainContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: today) else {
            return .result(value: "", dialog: "I couldn't work out the dates.")
        }

        let descriptor = FetchDescriptor<BillInstance>(sortBy: [SortDescriptor(\.dueDate)])
        let due = ((try? context.fetch(descriptor)) ?? []).filter {
            !$0.isPaid && $0.bill?.isArchived != true && $0.dueDate < weekEnd
        }

        guard !due.isEmpty else {
            return .result(value: "Nothing due", dialog: "You have nothing due this week.")
        }

        let lines = due.prefix(5).map { instance -> String in
            let name = instance.bill?.name ?? "Bill"
            let amount = instance.amount?.currencyString ?? "no amount yet"
            let date = instance.dueDate.formatted(.dateTime.month(.abbreviated).day())
            let overdue = instance.status() == .overdue ? " (overdue)" : ""
            return "\(name), \(amount), \(date)\(overdue)"
        }
        let more = due.count > 5 ? " and \(due.count - 5) more" : ""
        let summary = "\(due.count) \(due.count == 1 ? "bill" : "bills") to pay: " + lines.joined(separator: "; ") + more + "."
        return .result(value: summary, dialog: "\(summary)")
    }
}

// MARK: - Mark paid

nonisolated struct MarkBillPaidIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Bill as Paid"
    static let description = IntentDescription("Marks the next unpaid bill of an account as paid.")

    @Parameter(title: "Bill")
    var bill: BillEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$bill) as paid")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = AppContainer.shared.mainContext
        let billID = bill.id
        let descriptor = FetchDescriptor<Bill>(predicate: #Predicate { $0.id == billID })
        guard let account = (try? context.fetch(descriptor))?.first else {
            throw DueDayIntentError.billNotFound
        }

        // The nearest unpaid bill: the oldest overdue one, else the next one due.
        let next = (account.instances ?? [])
            .filter { !$0.isPaid }
            .min { $0.dueDate < $1.dueDate }
        guard let next else { throw DueDayIntentError.nothingToPay(account.name) }
        guard next.quickPay(in: context) else { throw DueDayIntentError.amountUnknown(account.name) }

        // Everything that could ask for more input is behind us, so the payment is saved last.
        try? context.save()
        await ReminderScheduler.reschedule(in: context)
        let amount = next.amount?.currencyString ?? ""
        return .result(dialog: "Marked \(account.name) as paid. \(amount)")
    }
}

// MARK: - Shortcuts

nonisolated struct DueDayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatsDueIntent(),
            phrases: [
                "What's due this week in \(.applicationName)",
                "What bills are due in \(.applicationName)",
            ],
            shortTitle: "What's Due",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: MarkBillPaidIntent(),
            phrases: ["Mark \(\.$bill) as paid in \(.applicationName)"],
            shortTitle: "Mark Paid",
            systemImageName: "checkmark.circle"
        )
    }
}
