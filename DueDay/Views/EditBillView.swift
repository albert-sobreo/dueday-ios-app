import SwiftUI
import SwiftData

/// Edit a saved bill or account.
struct EditBillView: View {
    let bill: Bill
    /// Called after the user confirms deleting the bill. The caller removes it once it's off screen.
    var onDelete: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Profile.sortOrder) private var profiles: [Profile]

    @State private var profile: Profile?
    @State private var name = ""
    @State private var category = BillCategory.other
    @State private var accountNumber = ""
    @State private var amountText = ""
    @State private var recurrence = RecurrenceKind.monthly
    @State private var interval = 2
    @State private var startDate = Date()
    @State private var weekendRule = WeekendRule.none
    @State private var reminderOffsets: Set<Int> = []
    @State private var paymentMethod: PaymentChoice?
    @State private var colorHex = ColorPalette.choices[0]
    @State private var originalColorHex = ColorPalette.choices[0]
    @State private var logoData: Data?
    @State private var originalLogoData: Data?
    @State private var nudgeEnabled = false
    @State private var expectedDay = 20
    @State private var remindsBeforeUsualDue = true
    @State private var usualDueDay = 1
    /// The due day shown when the screen opened, so an untouched inferred day isn't pinned on save.
    @State private var loadedDueDay = 1
    @State private var showingAddEntry = false
    @State private var confirmingDelete = false

    private var isVariable: Bool { bill.amountType == .variable }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (isVariable || (amountText.parsedAmount ?? 0) > 0)
    }

    var body: some View {
        FormScreen(
            title: "Edit",
            primaryTitle: "Save",
            primaryEnabled: canSave,
            onCancel: { dismiss() },
            changeToken: [
                name, accountNumber, amountText, colorHex, profile?.id, category, recurrence, interval,
                startDate, weekendRule, reminderOffsets.sorted(), paymentMethod?.title, logoData,
                nudgeEnabled, expectedDay, remindsBeforeUsualDue, usualDueDay,
            ] as [AnyHashable?],
            onPrimary: save
        ) {
            if profiles.count > 1 { profileCard }
            accountCard
            if isVariable {
                addBillCard
                nudgeCard
            } else {
                amountCard
                scheduleCard
            }
            FormCard(
                title: "Logo",
                symbol: "photo",
                footer: "Use a logo you have the right to use. It's stored on your device and in your iCloud."
            ) {
                LogoPickerRow(logoData: $logoData, symbol: bill.displayIcon, color: Color.adaptive(hex: colorHex))
            }
            FormCard(title: "Colour", symbol: "paintpalette") {
                ColorChoiceRow(hex: $colorHex)
            }
            remindersCard
            FormCard(title: "Usually paid with", symbol: "creditcard") {
                PaymentMethodChips(selection: $paymentMethod)
            }
            manageCard
        }
        .sheet(isPresented: $showingAddEntry) { AddBillEntrySheet(bill: bill) }
        .confirmationDialog("Delete \(bill.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete \(bill.name) and Its History", role: .destructive) {
                dismiss()
                onDelete()
            }
        } message: {
            Text("This removes all \((bill.instances ?? []).count) of its bills and payments. To keep the history, archive it instead.")
        }
        .onAppear(perform: load)
    }

    // MARK: Cards

    private var profileCard: some View {
        FormCard(title: "Profile", symbol: "person.2") {
            ChipGrid(
                options: profiles,
                selected: Binding(get: { profile ?? profiles[0] }, set: { profile = $0 }),
                title: { $0.name },
                symbol: { $0.kind.symbol }
            )
        }
    }

    private var accountCard: some View {
        FormCard(title: "Account", symbol: "person.text.rectangle") {
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("Name")
                TextField("Name", text: $name).insetField()
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
                FieldLabel(PresetStore.preset(withID: bill.presetID)?.accountNumberLabel ?? "Account number (optional)")
                TextField("Account number", text: $accountNumber)
                    .textInputAutocapitalization(.characters)
                    .insetField()
            }
        }
    }

    private var addBillCard: some View {
        FormCard(
            title: "Bills",
            symbol: "doc.text",
            footer: "Variable bills don't repeat. Add each one when it arrives."
        ) {
            OptionChip(title: "Add a bill for this account", symbol: "plus", isSelected: true) {
                showingAddEntry = true
            }
        }
    }

    private var nudgeCard: some View {
        FormCard(
            title: "Every month",
            symbol: "bell.badge",
            footer: "Until you add that month's bill, you're reminded before the usual due day, nudged to add it, and the account is flagged on your Bills tab."
        ) {
            OptionChip(title: "Remind me before it's due", symbol: "calendar.badge.clock", isSelected: remindsBeforeUsualDue) {
                remindsBeforeUsualDue.toggle()
            }
            if remindsBeforeUsualDue {
                Stepper("Usually due around day \(usualDueDay)", value: $usualDueDay, in: 1...31)
                    .font(.outfit(16))
            }
            OptionChip(title: "Nudge me to add the bill", symbol: "bell", isSelected: nudgeEnabled) {
                nudgeEnabled.toggle()
            }
            if nudgeEnabled {
                Stepper("Usually arrives around day \(expectedDay)", value: $expectedDay, in: 1...31)
                    .font(.outfit(16))
            }
        }
    }

    private var amountCard: some View {
        FormCard(title: "Amount", symbol: "banknote") {
            HStack(spacing: 6) {
                Text(CurrencySetting.symbol).font(.barlow(28, weight: .medium)).foregroundStyle(Theme.ink)
                TextField("0.00", text: $amountText)
                    .font(.barlow(28, weight: .medium))
                    .keyboardType(.decimalPad)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(FormStyle.fieldFill, in: .rect(cornerRadius: 14))
        }
    }

    private var scheduleCard: some View {
        FormCard(
            title: "Schedule",
            symbol: "calendar",
            footer: recurrence == .once ? nil
                : recurrence.isWeekly ? "Repeats on the same weekday as this date."
                : "Repeats on this day each month. Short months use their last day."
        ) {
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("Repeats")
                ChipGrid(options: RecurrenceKind.displayOrder, selected: $recurrence, title: { $0.title })
            }
            if recurrence == .everyNMonths {
                Stepper("Every \(interval) months", value: $interval, in: 2...11)
                    .font(.outfit(16))
            }
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(recurrence == .once ? "Due date" : "First due date")
                DatePicker("Due date", selection: $startDate, displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("If it falls on a weekend")
                ChipGrid(options: WeekendRule.allCases, selected: $weekendRule, columns: 1, title: { $0.title })
            }
        }
    }

    private var remindersCard: some View {
        FormCard(title: "Reminders", symbol: "bell") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                ForEach(ReminderChoice.all, id: \.days) { choice in
                    OptionChip(title: choice.title, isSelected: reminderOffsets.contains(choice.days)) {
                        if reminderOffsets.contains(choice.days) {
                            reminderOffsets.remove(choice.days)
                        } else {
                            reminderOffsets.insert(choice.days)
                        }
                    }
                }
            }
        }
    }

    private var manageCard: some View {
        FormCard(
            title: "Manage",
            symbol: "archivebox",
            footer: "Archiving hides the bill and its upcoming reminders but keeps your payment history."
        ) {
            OptionChip(
                title: bill.isArchived ? "Restore" : "Archive",
                symbol: "archivebox",
                isSelected: false
            ) {
                setArchived(!bill.isArchived)
                dismiss()
            }
            Button(role: .destructive) { confirmingDelete = true } label: {
                Text("Delete")
                    .font(.outfit(16, weight: .semibold))
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.danger.opacity(0.1), in: .capsule)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Logic

    private func load() {
        profile = bill.profile
        name = bill.name
        category = bill.category
        accountNumber = bill.accountNumber ?? ""
        amountText = bill.defaultAmount.map { "\($0)" } ?? ""
        recurrence = bill.recurrence
        interval = max(bill.recurrenceInterval, 2)
        // Show the start month on the bill's real due day (older bills stored a different day).
        let calendar = Calendar.current
        var parts = calendar.dateComponents([.year, .month], from: bill.startDate)
        let monthLength = calendar.range(of: .day, in: .month, for: bill.startDate)?.count ?? 28
        parts.day = min(max(bill.dueDay, 1), monthLength)
        startDate = calendar.date(from: parts) ?? bill.startDate
        weekendRule = bill.weekendRule
        reminderOffsets = Set(bill.reminderOffsets)
        paymentMethod = bill.paymentChoice
        nudgeEnabled = bill.expectedDay != nil
        expectedDay = bill.expectedDay ?? 20
        remindsBeforeUsualDue = bill.remindsBeforeUsualDue
        usualDueDay = bill.expectedDueDay() ?? bill.dueDay
        loadedDueDay = usualDueDay
        originalColorHex = bill.colorHex ?? bill.displayColor.hexString
        colorHex = originalColorHex
        originalLogoData = bill.logoData
        logoData = bill.logoData
    }

    private func setArchived(_ archived: Bool) {
        bill.isArchived = archived
        if archived {
            // Archiving stops future bills, but paid history stays.
            for instance in bill.instances ?? [] where !instance.isPaid {
                modelContext.delete(instance)
            }
        } else {
            InstanceGenerator.generate(for: bill, in: modelContext)
        }
    }

    private func save() {
        bill.name = name.trimmingCharacters(in: .whitespaces)
        bill.category = category
        bill.accountNumber = accountNumber.isEmpty ? nil : accountNumber
        bill.reminderOffsets = reminderOffsets.sorted(by: >)
        bill.paymentChoice = paymentMethod
        bill.profile = profile
        if isVariable {
            bill.expectedDay = nudgeEnabled ? expectedDay : nil
            bill.remindsBeforeUsualDue = remindsBeforeUsualDue
            // Store the due day once it's set by hand or the account has no bill to take it from.
            if bill.usualDueDay != nil || usualDueDay != loadedDueDay || bill.expectedDueDay() == nil {
                bill.usualDueDay = usualDueDay
            }
        }
        // Only store a colour when it was changed, so untouched bills keep following their provider.
        if colorHex != originalColorHex { bill.colorHex = colorHex }
        if logoData != originalLogoData { bill.logoData = logoData }

        if !isVariable {
            bill.defaultAmount = amountText.parsedAmount
            bill.recurrence = recurrence
            bill.recurrenceInterval = recurrence == .everyNMonths ? interval : 1
            bill.startDate = startDate
            // The due day always comes from the picked date.
            bill.dueDay = Calendar.current.component(.day, from: startDate)
            bill.weekendRule = weekendRule
            InstanceGenerator.regenerate(for: bill, in: modelContext)
        }
        dismiss()
    }
}
