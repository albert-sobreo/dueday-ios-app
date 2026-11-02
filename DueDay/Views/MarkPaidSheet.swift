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
    @State private var note = ""

    private var amount: Decimal? { amountText.parsedAmount }

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    TextField("₱0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                }

                Section("Payment") {
                    Picker("Method", selection: $method) {
                        Text("Not specified").tag(PaymentMethod?.none)
                        ForEach(PaymentMethod.allCases) { method in
                            Label(method.title, systemImage: method.symbol)
                                .tag(PaymentMethod?.some(method))
                        }
                    }
                    DatePicker("Date paid", selection: $paidDate, displayedComponents: .date)
                    TextField("Reference number (optional)", text: $referenceNumber)
                    TextField("Note (optional)", text: $note)
                }
            }
            .navigationTitle(instance.bill?.name ?? "Mark as paid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mark paid") { save() }
                        .disabled((amount ?? 0) <= 0)
                }
            }
            .onAppear {
                method = instance.bill?.defaultPaymentMethod
                if let existing = instance.amount {
                    amountText = "\(existing)"
                }
            }
        }
    }

    private func save() {
        guard let amount else { return }
        instance.markPaid(
            amount: amount,
            method: method,
            date: paidDate,
            referenceNumber: referenceNumber.isEmpty ? nil : referenceNumber,
            note: note.isEmpty ? nil : note,
            in: modelContext
        )
        dismiss()
    }
}
