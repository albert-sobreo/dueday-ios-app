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
        // The shared form screen: Cancel asks before losing what's entered, and the Confirm button
        // stays pinned at the bottom however many payment methods there are.
        FormScreen(
            title: String(localized: "Mark as paid"),
            primaryTitle: String(localized: "Confirm payment"),
            primaryEnabled: (amount ?? 0) > 0,
            onCancel: { dismiss() },
            changeToken: [amountText, paidDate, referenceNumber, method?.title, keepAttachment] as [AnyHashable?],
            onPrimary: save
        ) {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.barlow(44, relativeTo: .largeTitle))
                    .foregroundStyle(strong)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)

                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("Amount paid")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(CurrencySetting.symbol)
                            .font(.barlow(44, weight: .medium, relativeTo: .largeTitle))
                            .foregroundStyle(Theme.ink)
                        TextField("0.00", text: $amountText)
                            .font(.barlow(44, weight: .medium, relativeTo: .largeTitle))
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
                    .tint(Theme.toggleOn)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
            .foregroundStyle(isSelected ? FormStyle.onSelected : Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background {
                if isSelected { RoundedRectangle(cornerRadius: 14).fill(FormStyle.selectedFill) }
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
