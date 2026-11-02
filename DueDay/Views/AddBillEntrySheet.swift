import SwiftUI
import SwiftData

/// Adds a bill that just arrived to a saved variable account, such as this month's Meralco bill.
struct AddBillEntryForm: View {
    let bill: Bill
    /// True when shown as a sheet (with a Cancel pill) rather than pushed in the add flow.
    var isSheet = false
    var onCancel: () -> Void = {}
    let onSaved: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var amountText = ""
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var billingPeriod = ""

    private var amount: Decimal? { amountText.parsedAmount }

    var body: some View {
        FormScreen(
            title: "New bill",
            showsCancel: isSheet,
            primaryTitle: "Add bill",
            primaryEnabled: (amount ?? 0) > 0,
            onCancel: onCancel,
            onPrimary: save
        ) {
            FormCard(title: "Account", symbol: "person.text.rectangle") {
                HStack(spacing: 12) {
                    Image(systemName: bill.displayIcon)
                        .foregroundStyle(bill.displayColor)
                        .frame(width: 40, height: 40)
                        .background(bill.displayColor.opacity(0.16), in: .rect(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(bill.name).font(.outfit(17, weight: .semibold)).foregroundStyle(Theme.ink)
                        if let account = bill.maskedAccountNumber {
                            Text("ACCT \(account)").font(.outfit(13)).foregroundStyle(Theme.mutedInk)
                        }
                    }
                }
            }

            FormCard(title: "Amount due", symbol: "banknote") {
                HStack(spacing: 6) {
                    Text(CurrencySetting.symbol).font(.barlow(34, weight: .medium)).foregroundStyle(Theme.ink)
                    TextField("0.00", text: $amountText)
                        .font(.barlow(34, weight: .medium))
                        .keyboardType(.decimalPad)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 58)
                .background(FormStyle.fieldFill, in: .rect(cornerRadius: 14))
            }

            FormCard(title: "Due", symbol: "calendar", footer: "For example “Sep 28–Oct 27”.") {
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Due date")
                    DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Billing period (optional)")
                    TextField("Sep 28–Oct 27", text: $billingPeriod).insetField()
                }
            }
        }
    }

    private func save() {
        guard let amount else { return }
        let period = billingPeriod.trimmingCharacters(in: .whitespaces)
        bill.addInstance(
            dueDate: dueDate,
            amount: amount,
            billingPeriod: period.isEmpty ? nil : period,
            in: modelContext
        )
        onSaved()
    }
}

/// Sheet wrapper for adding a bill to an account from outside the add flow.
struct AddBillEntrySheet: View {
    let bill: Bill

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AddBillEntryForm(
            bill: bill,
            isSheet: true,
            onCancel: { dismiss() },
            onSaved: { dismiss() }
        )
    }
}
