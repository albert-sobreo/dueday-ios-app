import SwiftUI
import SwiftData

/// Edit or delete one of your saved providers.
struct ProviderEditSheet: View {
    let provider: CustomProvider

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var bills: [Bill]

    @State private var name = ""
    @State private var category = BillCategory.other
    @State private var amountType = AmountType.fixed
    @State private var accountNumberLabel = ""
    @State private var colorHex = ColorPalette.choices[0]
    @State private var logoData: Data?
    @State private var confirmingDelete = false

    /// Bills that were created from this provider.
    private var linkedBills: [Bill] {
        let id = provider.asPreset.id
        return bills.filter { $0.presetID == id }
    }

    var body: some View {
        FormScreen(
            title: "Edit provider",
            primaryTitle: "Save",
            primaryEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty,
            onCancel: { dismiss() },
            changeToken: [name, category, amountType, accountNumberLabel, colorHex, logoData] as [AnyHashable?],
            onPrimary: save
        ) {
            FormCard(
                title: "Details",
                symbol: "building.2",
                footer: "Colour and category also update the \(linkedBills.count) bill\(linkedBills.count == 1 ? "" : "s") already using this provider."
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Name")
                    TextField("Provider name", text: $name).insetField()
                }
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Category")
                    ChipGrid(
                        options: BillCategory.allCases,
                        selected: $category,
                        leadingAligned: true,
                        title: { $0.title },
                        symbol: { $0.symbol }
                    )
                }
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Amount")
                    ChipGrid(options: AmountType.allCases, selected: $amountType, title: { $0.title })
                }
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Account number label (optional)")
                    TextField("Member Number", text: $accountNumberLabel).insetField()
                }
            }

            FormCard(
                title: "Logo",
                symbol: "photo",
                footer: "Use a logo you have the right to use. It's stored on your device and in your iCloud."
            ) {
                LogoPickerRow(logoData: $logoData, symbol: category.symbol, color: Color.adaptive(hex: colorHex))
            }

            FormCard(title: "Colour", symbol: "paintpalette") {
                ColorChoiceRow(hex: $colorHex)
            }

            FormCard(title: "Delete", symbol: "trash", footer: "Bills already created from it are kept.") {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Text("Delete provider")
                        .font(.outfit(16, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.danger.opacity(0.1), in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .confirmationDialog("Delete \(provider.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Provider", role: .destructive) {
                modelContext.delete(provider)
                dismiss()
            }
        }
        .onAppear {
            name = provider.name
            category = provider.category
            amountType = provider.amountType
            accountNumberLabel = provider.accountNumberLabel ?? ""
            colorHex = provider.colorHex
            logoData = provider.logoData
        }
    }

    private func save() {
        provider.name = name.trimmingCharacters(in: .whitespaces)
        provider.category = category
        provider.amountType = amountType
        let label = accountNumberLabel.trimmingCharacters(in: .whitespaces)
        provider.accountNumberLabel = label.isEmpty ? nil : label
        provider.colorHex = colorHex
        provider.logoData = logoData

        // Keep existing bills in step with the look of the provider.
        for bill in linkedBills {
            bill.colorHex = colorHex
            bill.category = category
            bill.logoData = logoData
        }
        dismiss()
    }
}
