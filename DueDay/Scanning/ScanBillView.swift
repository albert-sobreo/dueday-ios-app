import SwiftUI
import SwiftData

/// What a scan or import produced: the details that were read, and the picture to keep.
struct ScanDraft: Hashable {
    var scanned: ScannedBill
    var attachment: Data?
}

/// Shows what was read from a bill next to the bill itself, so it can be checked and corrected before saving.
/// If the bill belongs to an account you already have, it says so and adds the bill to it.
struct ScanBillView: View {
    let draft: ScanDraft
    var defaultProfileID = ""
    /// Set when the scan is for a specific account, e.g. from its own screen. The bill is always added to it.
    var fixedAccount: Bill?
    let onDone: () -> Void
    /// Set when this form is the first screen of a sheet, to give it a Cancel button.
    var onCancel: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Profile.sortOrder) private var profiles: [Profile]
    @Query(sort: \Bill.name) private var accounts: [Bill]

    @State private var name = ""
    @State private var accountNumber = ""
    @State private var amountText = ""
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var billingPeriod = ""
    @State private var profile: Profile?
    @State private var keepScan = true
    @State private var addAsNewAccount = false
    @State private var loaded = false

    private var preset: BillPreset? { PresetStore.preset(withID: draft.scanned.presetID) }
    private var previewImage: UIImage? { draft.attachment.flatMap(UIImage.init(data:)) }
    private var amount: Decimal? { amountText.parsedAmount }

    /// The account this bill belongs to, if you already have it. It follows what's typed below, so it
    /// updates as you fix the name or account number.
    private var matchedAccount: Bill? {
        if let fixedAccount { return fixedAccount }
        guard !addAsNewAccount else { return nil }
        return AccountMatcher.find(
            in: accounts,
            presetID: preset?.id,
            name: name,
            accountNumber: accountNumber,
            profileID: profile?.id
        )
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (amount ?? 0) > 0
    }

    var body: some View {
        FormScreen(
            title: "Check the bill",
            showsCancel: false,
            primaryTitle: matchedAccount == nil ? "Add bill" : "Add to \(matchedAccount?.name ?? "account")",
            primaryEnabled: canSave,
            onCancel: onCancel,
            changeToken: [name, accountNumber, amountText, billingPeriod, dueDate, profile?.id, keepScan, addAsNewAccount] as [AnyHashable?],
            onPrimary: save
        ) {
            if let previewImage {
                FormCard(
                    title: "Your bill",
                    symbol: "doc.text.viewfinder",
                    footer: "Read on your device. Check the details below, and fix anything that's wrong."
                ) {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 260)
                        .clipShape(.rect(cornerRadius: 12))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Scanned bill")
                }
            }

            if fixedAccount == nil { accountNotice }

            if profiles.count > 1 && fixedAccount == nil {
                FormCard(title: "Profile", symbol: "person.2") {
                    ChipGrid(
                        options: profiles,
                        selected: Binding(get: { profile ?? profiles[0] }, set: { profile = $0 }),
                        title: { $0.name },
                        symbol: { $0.kind.symbol }
                    )
                }
            }

            if fixedAccount == nil {
                FormCard(
                    title: "Account",
                    symbol: "person.text.rectangle",
                    footer: preset == nil && matchedAccount == nil ? "We couldn't tell which biller this is, so type its name." : nil
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        FieldLabel(draft.scanned.providerName == nil ? "Biller name" : "Biller")
                        TextField("Name", text: $name).insetField()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        FieldLabel(preset?.accountNumberLabel ?? "Account number (optional)")
                        TextField("Account number", text: $accountNumber)
                            .textInputAutocapitalization(.characters)
                            .insetField()
                    }
                }
            }

            FormCard(
                title: "Amount due",
                symbol: "banknote",
                footer: draft.scanned.amount == nil ? "We couldn't find the amount. Please type it in." : nil
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
                footer: draft.scanned.dueDate == nil ? "We couldn't find the due date. Please set it." : nil
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

    // MARK: Existing account notice

    /// Says when this bill matches an account you already saved, and lets you save a new one instead.
    @ViewBuilder
    private var accountNotice: some View {
        if let account = matchedAccount {
            FormCard(
                title: "Account found",
                symbol: "checkmark.seal",
                footer: "This bill will be added to your existing \(account.name) account, so you don't have to set it up again."
            ) {
                HStack(spacing: 12) {
                    LogoBadge(logo: account.logoData, symbol: account.displayIcon, color: account.displayColor, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.name).font(.outfit(17, weight: .semibold)).foregroundStyle(Theme.ink)
                        if let number = account.maskedAccountNumber {
                            Text(number).font(.outfit(13)).foregroundStyle(Theme.mutedInk)
                        }
                    }
                    Spacer()
                }
                OptionChip(title: "Save as a new account instead", symbol: "plus", isSelected: false) {
                    addAsNewAccount = true
                }
            }
        } else if addAsNewAccount {
            FormCard(title: "New account", symbol: "plus.circle") {
                OptionChip(title: "Use my existing account instead", symbol: "arrow.uturn.backward", isSelected: false) {
                    addAsNewAccount = false
                }
            }
        }
    }

    // MARK: Logic

    private func load() {
        guard !loaded else { return }
        loaded = true
        let scanned = draft.scanned
        name = scanned.providerName ?? ""
        accountNumber = scanned.accountNumber ?? ""
        amountText = scanned.amount.map { "\($0)" } ?? ""
        if let date = scanned.dueDate { dueDate = date }
        billingPeriod = scanned.billingPeriod ?? ""
        profile = profiles.first { $0.id.uuidString == defaultProfileID } ?? profiles.first

        // A bill that matched by account number alone may not have had its biller recognised.
        if let fixedAccount { name = fixedAccount.name }
        else if name.isEmpty, let account = matchedAccount { name = account.name }
    }

    private func save() {
        guard let amount else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let period = billingPeriod.trimmingCharacters(in: .whitespaces)

        let account: Bill
        if let existing = matchedAccount {
            account = existing
            if existing.accountNumber == nil, !accountNumber.isEmpty { existing.accountNumber = accountNumber }
        } else {
            // A scanned bill is saved as a variable account, so next time only the amount and date change.
            account = Bill(name: trimmedName)
            account.presetID = preset?.id
            account.colorHex = preset?.colorHex
            account.category = preset?.category ?? .other
            account.accountNumber = accountNumber.isEmpty ? nil : accountNumber
            account.amountType = .variable
            account.recurrence = .once
            account.profile = profile
            modelContext.insert(account)
        }

        let instance = account.addInstance(
            dueDate: dueDate, amount: amount,
            billingPeriod: period.isEmpty ? nil : period, in: modelContext
        )
        if keepScan { instance.attachment = draft.attachment }

        // Ask to send reminders the first time, then schedule them.
        let context = modelContext
        Task {
            if await ReminderScheduler.requestAuthorizationIfNeeded() {
                try? context.save()
                await ReminderScheduler.reschedule(in: context)
            }
        }
        onDone()
    }
}
