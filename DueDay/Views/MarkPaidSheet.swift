import SwiftUI
import SwiftData

struct MarkPaidSheet: View {
    let instance: BillInstance

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var method: PaymentMethod?
    @State private var paidDate = Date()
    @State private var referenceNumber = ""
    @State private var keepAttachment = true

    private var amount: Decimal? { amountText.parsedAmount }
    private var strong: Color { Theme.detailStrong }

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private var title: String {
        let name = instance.bill?.name ?? "Bill"
        let month = instance.dueDate.formatted(.dateTime.month(.abbreviated))
        return "\(name) · \(month)".uppercased()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("Mark as paid")
                        Text(title)
                            .font(.barlow(44, relativeTo: .largeTitle))
                            .foregroundStyle(strong)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                    }
                    Spacer()
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .tint(Theme.ink)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("Amount paid")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(CurrencySetting.symbol).font(.barlow(44, weight: .medium)).foregroundStyle(Theme.ink)
                        TextField("0.00", text: $amountText)
                            .font(.barlow(44, weight: .medium))
                            .keyboardType(.decimalPad)
                    }
                    Rectangle().fill(Theme.ink).frame(height: 1.5)
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("Date paid")
                        DatePicker("Date paid", selection: $paidDate, in: ...Date.now, displayedComponents: .date)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .glassSurface(cornerRadius: 14)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("Reference no.")
                        TextField("Optional", text: $referenceNumber)
                            .font(.outfit(16))
                            .textInputAutocapitalization(.characters)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 46)
                            .glassSurface(cornerRadius: 14)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Paid with")
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(PaymentMethod.allCases) { option in
                            methodTile(option)
                        }
                    }
                }

                if instance.attachment != nil {
                    Toggle(isOn: $keepAttachment) {
                        Text("Attach the scanned bill to this payment").font(.outfit(15))
                    }
                    .toggleStyle(.switch)
                    .tint(Theme.paid)
                }

                Button(action: save) {
                    Label("Confirm payment", systemImage: "checkmark")
                        .font(.outfit(17, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .primaryButton()
                .disabled((amount ?? 0) <= 0)
            }
            .padding(20)
        }
        .background(Theme.background)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            method = instance.bill?.defaultPaymentMethod
            if let existing = instance.amount {
                amountText = "\(existing)"
            }
        }
    }

    private func methodTile(_ option: PaymentMethod) -> some View {
        let isSelected = method == option
        return Button { method = isSelected ? nil : option } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title).font(.outfit(15, weight: .semibold))
                Text(option.subtitle).font(.outfit(12)).opacity(0.8)
            }
            .foregroundStyle(isSelected ? Theme.onSelected : Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background {
                if isSelected { RoundedRectangle(cornerRadius: 14).fill(Theme.selected) }
            }
            .glassSurface(cornerRadius: 14, enabled: !isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func save() {
        guard let amount else { return }
        instance.markPaid(
            amount: amount,
            method: method,
            date: paidDate,
            referenceNumber: referenceNumber.isEmpty ? nil : referenceNumber,
            in: modelContext
        )
        if !keepAttachment { instance.attachment = nil }
        dismiss()
    }
}
