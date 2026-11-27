import SwiftUI

/// How the amount of an installment plan is entered.
enum InstallmentEntry: String, CaseIterable, Identifiable, Hashable {
    /// The amount typed is one payment, e.g. ₱2,000 a month.
    case perPayment
    /// The amount typed is the whole price, split evenly across the payments.
    case total

    var id: String { rawValue }

    var title: String {
        switch self {
        case .perPayment: String(localized: "Per payment")
        case .total: String(localized: "Total price")
        }
    }
}

/// What the installment section of the add and edit forms holds, before it's saved to a bill.
struct InstallmentDraft: Hashable {
    var isOn = false
    var countText = "12"
    var paidBeforeText = ""
    var entry = InstallmentEntry.perPayment

    init() {}

    /// The form's values for a saved bill. A plan entered as a total shows its total again.
    init(bill: Bill) {
        isOn = bill.installmentCount != nil
        countText = bill.installmentCount.map(String.init) ?? "12"
        paidBeforeText = bill.installmentsPaidBefore > 0 ? String(bill.installmentsPaidBefore) : ""
        entry = bill.installmentTotal != nil ? .total : .perPayment
    }

    var count: Int? {
        guard let value = Int(countText.trimmingCharacters(in: .whitespaces)),
              (2...Bill.maxInstallments).contains(value)
        else { return nil }
        return value
    }

    var paidBefore: Int {
        Int(paidBeforeText.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    /// Label for the amount field.
    var amountLabel: String {
        guard isOn else { return String(localized: "Amount") }
        return entry == .total ? String(localized: "Total price") : String(localized: "Amount per payment")
    }

    /// Whether the plan can be saved. `minimumCount` keeps the count from going below payments
    /// already paid in the app.
    func isValid(minimumCount: Int = 2) -> Bool {
        guard isOn else { return true }
        guard let count, count >= minimumCount else { return false }
        return paidBefore >= 0 && paidBefore < count
    }

    /// One payment's amount for the typed amount.
    func perPayment(for amount: Decimal?) -> Decimal? {
        guard let amount else { return nil }
        guard isOn, entry == .total, let count else { return amount }
        return Bill.perPaymentAmount(total: amount, count: count)
    }

    /// Writes the amount and plan to the bill. Call after its recurrence is set.
    func apply(to bill: Bill, amount: Decimal?) {
        if isOn, bill.recurrence != .once, let count {
            bill.installmentCount = count
            bill.installmentsPaidBefore = min(paidBefore, count - 1)
            bill.installmentTotal = entry == .total ? amount : nil
            bill.defaultAmount = perPayment(for: amount)
        } else {
            bill.installmentCount = nil
            bill.installmentsPaidBefore = 0
            bill.installmentTotal = nil
            bill.defaultAmount = amount
        }
    }
}

/// The "Installment plan" card on the add and edit forms, for fixed bills that repeat.
struct InstallmentCard: View {
    @Binding var draft: InstallmentDraft
    /// The amount typed in the Amount card.
    let amount: Decimal?
    let startDate: Date
    let recurrence: RecurrenceKind
    let interval: Int
    let weekendRule: WeekendRule
    /// Payments already paid in the app, so the count can't drop below them when editing.
    var minimumCount = 2

    var body: some View {
        FormCard(
            title: "Installment plan",
            symbol: "chart.bar.doc.horizontal",
            footer: draft.isOn ? summary : "For something paid off over a set number of payments, like a phone over 24 months."
        ) {
            OptionChip(title: "Pay in installments", symbol: "number", isSelected: draft.isOn) {
                draft.isOn.toggle()
            }
            if draft.isOn {
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Amount entered is")
                    ChipGrid(options: InstallmentEntry.allCases, selected: $draft.entry, title: { $0.title })
                }
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        FieldLabel("Number of payments")
                        TextField("24", text: $draft.countText)
                            .keyboardType(.numberPad)
                            .insetField()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        FieldLabel("Already paid")
                        TextField("0", text: $draft.paidBeforeText)
                            .keyboardType(.numberPad)
                            .insetField()
                    }
                }
                if let problem {
                    Text(problem)
                        .font(.outfit(13))
                        .foregroundStyle(Theme.danger)
                }
            }
        }
    }

    /// Why the plan can't be saved yet, if it can't.
    private var problem: String? {
        guard let count = draft.count else {
            return String(localized: "Enter 2 to \(Bill.maxInstallments) payments.")
        }
        if count < minimumCount {
            return String(localized: "\(minimumCount) payments are already paid, so the plan needs at least that many.")
        }
        if draft.paidBefore >= count {
            return String(localized: "Already paid must be less than the number of payments.")
        }
        return nil
    }

    /// "24 payments of ₱2,000.00, ₱48,000.00 in total. Last payment due Oct 2028."
    private var summary: String {
        guard let count = draft.count, problem == nil else {
            return String(localized: "The first due date is the next payment you still owe.")
        }
        var lines: [String] = []
        if let per = draft.perPayment(for: amount), per > 0 {
            if draft.entry == .total, let amount {
                let last = amount - per * Decimal(count - 1)
                if last == per {
                    lines.append(String(localized: "\(count) payments of \(per.currencyString)."))
                } else {
                    lines.append(String(localized: "\(count - 1) payments of \(per.currencyString), then \(last.currencyString)."))
                }
            } else {
                lines.append(String(localized: "\(count) payments of \(per.currencyString), \((per * Decimal(count)).currencyString) in total."))
            }
        }
        if draft.paidBefore > 0 {
            lines.append(String(localized: "The first due date is payment \(draft.paidBefore + 1)."))
        } else {
            lines.append(String(localized: "The first due date is payment 1."))
        }
        let calendar = Calendar.current
        if let last = Bill.occurrenceDueDate(
            count - draft.paidBefore - 1, startDate: startDate, recurrence: recurrence, interval: interval,
            dueDay: calendar.component(.day, from: startDate), weekendRule: weekendRule, calendar: calendar
        ) {
            lines.append(String(localized: "Last payment due \(last.formatted(.dateTime.month(.abbreviated).day().year()))."))
        }
        return lines.joined(separator: " ")
    }
}
