import SwiftUI
import SwiftData

/// A scan of this bill, waiting to be checked before it updates the bill.
struct ScanUpdate: Identifiable {
    let id = UUID()
    let instance: BillInstance
    let draft: ScanDraft
}

/// Shows what was read from a scan next to the bill's current details, so you can check it and update
/// the bill's amount, due date and billing period in one go.
struct ScanUpdateSheet: View {
    let update: ScanUpdate

    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var dueDate = Date()
    @State private var billingPeriod = ""
    @State private var keepScan = true
    @State private var loaded = false

    private var instance: BillInstance { update.instance }
    private var scanned: ScannedBill { update.draft.scanned }
    private var previewImage: UIImage? { update.draft.attachment.flatMap(UIImage.init(data:)) }
    private var amount: Decimal? { amountText.parsedAmount }

    var body: some View {
        FormScreen(
            title: instance.bill?.name ?? "Update bill",
            primaryTitle: "Update bill",
            primaryEnabled: (amount ?? 0) > 0,
            onCancel: { dismiss() },
            changeToken: [amountText, dueDate, billingPeriod, keepScan] as [AnyHashable],
            onPrimary: save
        ) {
            if let previewImage {
                FormCard(
                    title: "Your scan",
                    symbol: "doc.text.viewfinder",
                    footer: "Read on your device. Check the details below, and fix anything that's wrong."
                ) {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(.rect(cornerRadius: 12))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Scanned bill")
                }
            }

            FormCard(
                title: "Amount due",
                symbol: "banknote",
                footer: scanned.amount == nil ? "We couldn't find the amount, so this is the bill's current one." : nil
            ) {
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
                footer: scanned.dueDate == nil ? "We couldn't find the due date, so this is the bill's current one." : nil
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

            if previewImage != nil {
                FormCard(title: "Keep the scan", symbol: "paperclip", footer: "Attached to this bill, on your device.") {
                    OptionChip(title: "Attach the scan to this bill", symbol: "paperclip", isSelected: keepScan) {
                        keepScan.toggle()
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    /// What was read wins, and anything it couldn't find keeps the bill's current value.
    private func load() {
        guard !loaded else { return }
        loaded = true
        let value = scanned.amount ?? instance.amount
        amountText = value.map { "\($0)" } ?? ""
        dueDate = scanned.dueDate ?? instance.dueDate
        billingPeriod = scanned.billingPeriod ?? instance.billingPeriod ?? ""
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
        if keepScan, let data = update.draft.attachment { instance.attachment = data }

        // A bill's account number is filled in from the scan if it didn't have one.
        if let bill = instance.bill, bill.accountNumber == nil, let number = scanned.accountNumber {
            bill.accountNumber = number
        }

        // The due date may have moved, so the reminders need rebuilding.
        if let context = instance.modelContext {
            Task {
                try? context.save()
                await ReminderScheduler.reschedule(in: context)
            }
        }
        dismiss()
    }
}
