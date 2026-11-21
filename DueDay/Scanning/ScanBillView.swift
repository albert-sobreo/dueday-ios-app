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
    /// The biller, starting from what the scan recognised. It can be changed if the scan got it wrong.
    @State private var presetID: String?
    @State private var accountChoice = AccountChoice.automatic
    @State private var loaded = false

    /// Which account the bill goes to: whatever matches what's typed, one you picked, or a new one.
    private enum AccountChoice: Hashable {
        case automatic
        case existing(Bill)
        case new
    }

    private var preset: BillPreset? { PresetStore.preset(withID: presetID) }
    private var previewImage: UIImage? { draft.attachment.flatMap(UIImage.init(data:)) }
    private var amount: Decimal? { amountText.parsedAmount }

    /// The account found from what's typed below. It updates as you fix the name or account number.
    private var detectedAccount: Bill? {
        AccountMatcher.find(
            in: accounts,
            presetID: preset?.id,
            name: name,
            accountNumber: accountNumber,
            profileID: profile?.id
        )
    }

    /// The account this bill will be added to, or nil for a new one.
    private var matchedAccount: Bill? {
        if let fixedAccount { return fixedAccount }
        switch accountChoice {
        case .automatic: return detectedAccount
        case .existing(let account): return account
        case .new: return nil
        }
    }

    /// The accounts you can choose from: the selected profile's, not archived.
    private var profileAccounts: [Bill] {
        accounts.filter { !$0.isArchived && $0.profile?.id == profile?.id }
    }

    /// Set when the scan is for a specific account but looks like it belongs to another one.
    private var conflictMessage: String? {
        guard let fixedAccount else { return nil }
        switch AccountMatcher.conflict(
            scannedPresetID: draft.scanned.presetID,
            scannedAccountNumber: draft.scanned.accountNumber,
            with: fixedAccount
        ) {
        case .differentAccountNumber:
            return "The account number on this scan doesn't match \(fixedAccount.name). Check it's the right bill before adding it."
        case .differentBiller(let presetID):
            let biller = PresetStore.preset(withID: presetID)?.name ?? "another biller"
            return "This looks like a \(biller) bill, not \(fixedAccount.name). Check it's the right bill before adding it."
        case nil:
            return nil
        }
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
            changeToken: [name, accountNumber, amountText, billingPeriod, dueDate, profile?.id, keepScan, presetID, accountChoice] as [AnyHashable?],
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

            if let conflictMessage {
                FormCard(title: "Check the account", symbol: "exclamationmark.triangle", footer: conflictMessage) {
                    EmptyView()
                }
            }

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

            if fixedAccount == nil { accountCard }

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
        // An account picked for one profile isn't one of the next profile's.
        .onChange(of: profile) { if loaded { accountChoice = .automatic } }
    }

    // MARK: Account

    /// Which account the bill goes to, with the details for a new one. If the scan matched the wrong
    /// account, or none, another can be picked from the menu.
    private var accountCard: some View {
        FormCard(title: "Account", symbol: "person.text.rectangle", footer: accountFooter) {
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("Add to")
                accountMenu
            }

            // An account you picked yourself already has its details.
            if case .existing = accountChoice {} else {
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Biller")
                    billerMenu
                }
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Name")
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
    }

    private var accountFooter: String {
        switch accountChoice {
        case .automatic where detectedAccount != nil:
            "We matched this to your existing account. If that's wrong, pick the right one above."
        case .automatic where preset == nil:
            "We couldn't tell which biller this is. Pick it or type its name, or add it to an account you have."
        case .existing(let account):
            "This bill will be added to your \(account.name) account."
        default:
            "A new account will be set up for this bill."
        }
    }

    /// A dropdown of your accounts, plus "New account". The matched account is ticked to start with.
    private var accountMenu: some View {
        Menu {
            Picker("Account", selection: Binding<Bill?>(
                get: { matchedAccount },
                set: { accountChoice = $0.map(AccountChoice.existing) ?? .new }
            )) {
                Label("New account", systemImage: "plus").tag(Bill?.none)
                ForEach(profileAccounts) { account in
                    Text(account.maskedAccountNumber.map { "\(account.name) ••\($0)" } ?? account.name)
                        .tag(Optional(account))
                }
            }
            if accountChoice != .automatic {
                Divider()
                Button("Match automatically", systemImage: "wand.and.stars") { accountChoice = .automatic }
            }
        } label: {
            HStack(spacing: 12) {
                if let account = matchedAccount {
                    LogoBadge(logo: account.logoData, symbol: account.displayIcon, color: account.displayColor, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.name).font(.outfit(17, weight: .semibold)).foregroundStyle(Theme.ink)
                        if accountChoice == .automatic {
                            Text("Matched from your scan").font(.outfit(12)).foregroundStyle(Theme.mutedInk)
                        } else if let number = account.maskedAccountNumber {
                            Text(number).font(.outfit(12)).foregroundStyle(Theme.mutedInk)
                        }
                    }
                } else {
                    Image(systemName: "plus.circle").font(.title3).foregroundStyle(Theme.accent)
                    Text("New account").font(.outfit(17, weight: .semibold)).foregroundStyle(Theme.ink)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").foregroundStyle(Theme.mutedInk)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            .background(FormStyle.fieldFill, in: .rect(cornerRadius: 14))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add to account")
        .accessibilityValue(matchedAccount?.name ?? "New account")
    }

    /// A dropdown of the bundled billers, for when the scan recognised the wrong one or none.
    private var billerMenu: some View {
        Menu {
            Picker("Biller", selection: Binding<String?>(
                get: { presetID },
                set: { newID in
                    presetID = newID
                    if let preset = PresetStore.preset(withID: newID) { name = preset.name }
                }
            )) {
                Text("Not listed").tag(String?.none)
                ForEach(BillCategory.allCases) { category in
                    if let presets = PresetStore.byCategory[category], !presets.isEmpty {
                        Section(category.title) {
                            ForEach(presets) { preset in
                                Text(preset.name).tag(Optional(preset.id))
                            }
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text(preset?.name ?? "Not listed")
                    .font(.outfit(17))
                    .foregroundStyle(preset == nil ? Theme.mutedInk : Theme.ink)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").foregroundStyle(Theme.mutedInk)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(FormStyle.fieldFill, in: .rect(cornerRadius: 14))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Biller")
        .accessibilityValue(preset?.name ?? "Not listed")
    }

    // MARK: Logic

    private func load() {
        guard !loaded else { return }
        loaded = true
        let scanned = draft.scanned
        presetID = scanned.presetID
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
