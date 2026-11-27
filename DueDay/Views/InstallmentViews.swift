import SwiftUI
import SwiftData

/// A thin bar showing how much of an installment plan is paid.
struct InstallmentProgressBar: View {
    let progress: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(tint)
                    .frame(width: max(proxy.size.width * min(max(progress, 0), 1), progress > 0 ? height : 0))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Plan progress")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent paid")
    }
}

/// The installment plan on a bill's detail screen: payments made, what's left, and when it ends.
struct InstallmentProgressCard: View {
    let bill: Bill
    let tint: Color
    let onPayOff: () -> Void

    var body: some View {
        let count = bill.installmentCount ?? 0
        let paidOff = bill.isPaidOff
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Eyebrow("Installment plan")
                Spacer()
                if paidOff {
                    StatusChip(text: String(localized: "Paid off"), foreground: Theme.paid, background: Theme.paidFill)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(bill.installmentsPaid)")
                    .font(.barlow(44, weight: .medium, relativeTo: .largeTitle))
                    .foregroundStyle(tint)
                Text("of \(count) paid")
                    .font(.outfit(17, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(Theme.ink)
            }

            InstallmentProgressBar(progress: bill.installmentProgress, tint: tint, height: 10)

            HStack(alignment: .top, spacing: 14) {
                fact("Left to pay", bill.remainingBalance.currencyString)
                Divider().frame(height: 34)
                fact("Total", bill.installmentPlanTotal.currencyString)
                if !paidOff, let last = bill.finalInstallmentDueDate() {
                    Divider().frame(height: 34)
                    fact("Last due", last.formatted(.dateTime.month(.abbreviated).year()))
                }
            }

            if !paidOff && bill.installmentsLeft > 1 && !bill.isArchived {
                Button(action: onPayOff) {
                    Label("Pay off remaining", systemImage: "flag.checkered")
                        .font(.outfit(16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .secondaryButton(tint: tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(label)
            Text(value)
                .font(.barlow(22, weight: .semibold, relativeTo: .title3))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

/// Settles the rest of an installment plan in one payment. The amount starts at the balance left
/// and can be changed, e.g. for an early payoff discount.
struct PayOffSheet: View {
    let bill: Bill

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var paidDate = Date()
    @State private var method: PaymentChoice?

    private var amount: Decimal? { amountText.parsedAmount }

    var body: some View {
        FormScreen(
            title: String(localized: "Pay off remaining"),
            primaryTitle: String(localized: "Confirm payoff"),
            primaryEnabled: (amount ?? 0) > 0,
            onCancel: { dismiss() },
            changeToken: [amountText, paidDate, method?.title] as [AnyHashable?],
            onPrimary: save
        ) {
            FormCard(
                title: "Payoff",
                symbol: "flag.checkered",
                footer: "Pays the \(bill.installmentsLeft) payments left on \(bill.name) at once, then moves it to Paid off."
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Amount paid")
                    HStack(spacing: 6) {
                        Text(CurrencySetting.symbol).font(.barlow(28, weight: .medium)).foregroundStyle(Theme.ink)
                        TextField("0.00", text: $amountText)
                            .font(.barlow(28, weight: .medium))
                            .keyboardType(.decimalPad)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .background(FormStyle.fieldFill, in: .rect(cornerRadius: 14))
                }
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Date paid")
                    DatePicker("Date paid", selection: $paidDate, in: ...Date.now, displayedComponents: .date)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            FormCard(title: "Paid with", symbol: "creditcard") {
                PaymentMethodChips(selection: $method)
            }
        }
        .onAppear {
            amountText = "\(bill.remainingBalance)"
            method = bill.paymentChoice
        }
    }

    private func save() {
        guard let amount else { return }
        bill.payOffRemaining(amount: amount, method: method, date: paidDate, in: modelContext)
        let context = modelContext
        Task {
            try? context.save()
            await ReminderScheduler.reschedule(in: context)
        }
        dismiss()
    }
}
