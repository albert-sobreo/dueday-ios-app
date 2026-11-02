import SwiftUI
import SwiftData

/// Chips for choosing how a bill is usually paid: "No preference", the built-in methods, any
/// custom methods you've added, and a chip to add a new one.
struct PaymentMethodChips: View {
    @Binding var selection: PaymentChoice?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomPaymentMethod.createdAt) private var customMethods: [CustomPaymentMethod]

    @State private var isAdding = false
    @State private var newName = ""

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
            OptionChip(title: "No preference", symbol: "minus.circle", leadingAligned: true, isSelected: selection == nil) {
                selection = nil
            }
            ForEach(PaymentMethod.allCases) { method in
                OptionChip(
                    title: method.title, symbol: method.symbol, leadingAligned: true,
                    isSelected: selection == .builtIn(method)
                ) { selection = .builtIn(method) }
            }
            ForEach(customMethods) { custom in
                OptionChip(
                    title: custom.name, symbol: "wallet.pass", leadingAligned: true,
                    isSelected: selection == .custom(custom.name)
                ) { selection = .custom(custom.name) }
                .contextMenu {
                    Button("Delete “\(custom.name)”", systemImage: "trash", role: .destructive) {
                        if selection == .custom(custom.name) { selection = nil }
                        modelContext.delete(custom)
                    }
                }
            }
            OptionChip(title: "Add custom", symbol: "plus", leadingAligned: true, isSelected: false) {
                newName = ""
                isAdding = true
            }
        }
        .alert("New payment method", isPresented: $isAdding) {
            TextField("Name, e.g. Cash", text: $newName)
            Button("Add") { addCustom() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved so you can pick it for any bill.")
        }
    }

    private func addCustom() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        // Reuse a method that already has this name instead of adding a duplicate.
        if let builtIn = PaymentMethod.allCases.first(where: { $0.title.caseInsensitiveCompare(name) == .orderedSame }) {
            selection = .builtIn(builtIn)
        } else if let existing = customMethods.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            selection = .custom(existing.name)
        } else {
            modelContext.insert(CustomPaymentMethod(name: name))
            selection = .custom(name)
        }
    }
}
