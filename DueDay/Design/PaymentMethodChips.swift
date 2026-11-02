import SwiftUI

/// Chips for choosing how a bill is usually paid, with "No preference" to clear the choice.
struct PaymentMethodChips: View {
    @Binding var selection: PaymentMethod?

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
            OptionChip(title: "No preference", symbol: "minus.circle", leadingAligned: true, isSelected: selection == nil) {
                selection = nil
            }
            ForEach(PaymentMethod.allCases) { method in
                OptionChip(title: method.title, symbol: method.symbol, leadingAligned: true, isSelected: selection == method) {
                    selection = method
                }
            }
        }
    }
}
