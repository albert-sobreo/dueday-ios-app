import SwiftUI
import SwiftData

struct MarkPaidSheet: View {
    let instance: BillInstance

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @Query(sort: \CustomPaymentMethod.createdAt) private var customMethods: [CustomPaymentMethod]

    @State private var method: PaymentChoice?
    @State private var isAddingMethod = false
    @State private var newMethodName = ""
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
                            methodTile(.builtIn(option))
                        }
                        ForEach(customMethods) { custom in
                            methodTile(.custom(custom.name))
                        }
                        addMethodTile
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
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            // Extra room at the top so the title isn't crowded by the sheet's edge.
            .padding(.top, 36)
        }
        .background(Theme.background)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            method = instance.bill?.paymentChoice
            if let existing = instance.amount {
                amountText = "\(existing)"
            }
        }
        .alert("New payment method", isPresented: $isAddingMethod) {
            TextField("Name, e.g. Cash", text: $newMethodName)
            Button("Add") { addCustomMethod() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved so you can pick it for any bill.")
        }
    }

    /// A tile that adds a custom payment method.
    private var addMethodTile: some View {
        Button {
            newMethodName = ""
            isAddingMethod = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label("Add custom", systemImage: "plus").font(.outfit(15, weight: .semibold))
                Text("Cash, another wallet…").font(.outfit(12)).opacity(0.8)
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassSurface(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    private func addCustomMethod() {
        let name = newMethodName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        // Reuse a method that already has this name instead of adding a duplicate.
        if let builtIn = PaymentMethod.allCases.first(where: { $0.title.caseInsensitiveCompare(name) == .orderedSame }) {
            method = .builtIn(builtIn)
        } else if let existing = customMethods.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            method = .custom(existing.name)
        } else {
            modelContext.insert(CustomPaymentMethod(name: name))
            method = .custom(name)
        }
    }

    private func methodTile(_ option: PaymentChoice) -> some View {
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
