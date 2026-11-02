import SwiftUI
import SwiftData

/// Correct the amount, due date or billing period of one bill, such as a typo in this month's Meralco.
struct EditInstanceSheet: View {
    let instance: BillInstance

    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var dueDate = Date()
    @State private var billingPeriod = ""

    private var amount: Decimal? { amountText.parsedAmount }

    var body: some View {
        FormScreen(
            title: instance.bill?.name ?? "Edit bill",
            primaryTitle: "Save",
            primaryEnabled: (amount ?? 0) > 0,
            onCancel: { dismiss() },
            changeToken: [amountText, dueDate, billingPeriod] as [AnyHashable],
            onPrimary: save
        ) {
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

            FormCard(
                title: "Due",
                symbol: "calendar",
                footer: "Only this bill changes. The account and its other bills stay as they are."
            ) {
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
        .onAppear {
            amountText = instance.amount.map { "\($0)" } ?? ""
            dueDate = instance.dueDate
            billingPeriod = instance.billingPeriod ?? ""
        }
    }

    private func save() {
        guard let amount else { return }
        let calendar = Calendar.current
        instance.amount = amount
        instance.dueDate = calendar.startOfDay(for: dueDate)
        // Keep the month key in step with the due date so it can't collide with another month's bill.
        instance.periodKey = calendar.component(.year, from: dueDate) * 100 + calendar.component(.month, from: dueDate)
        let period = billingPeriod.trimmingCharacters(in: .whitespaces)
        instance.billingPeriod = period.isEmpty ? nil : period
        dismiss()
    }
}
