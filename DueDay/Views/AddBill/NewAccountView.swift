import SwiftUI
import SwiftData

extension View {
    /// Shared look for the app's plain forms (Settings).
    func dueDayForm() -> some View {
        self
            .font(.outfit(16))
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .tint(Theme.accent)
    }
}

/// Step 2 of 2: the details for a new bill. Variable bills (electricity, water) are saved as an
/// account you can reuse; fixed bills get a repeating schedule.
struct NewAccountView: View {
    /// The chosen biller, or nil for a custom bill.
    let preset: BillPreset?
    var defaultProfileID = ""
    let onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Profile.sortOrder) private var profiles: [Profile]

    @State private var profile: Profile?
    @State private var name = ""
    @State private var category = BillCategory.other
    @State private var accountNumber = ""
    @State private var amountType = AmountType.fixed
    @State private var amountText = ""
    @State private var recurrence = RecurrenceKind.monthly
    @State private var interval = 2
    @State private var startDate = Date()
    @State private var weekendRule = WeekendRule.none
    @State private var reminderOffsets: Set<Int> = [3, 0]
    @State private var paymentMethod: PaymentChoice?
    @State private var billDueDate = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var billingPeriod = ""
    @State private var rememberProvider = true
    @State private var colorHex = ColorPalette.choices[0]
    @State private var logoData: Data?
    @State private var loaded = false

    @Query private var customProviders: [CustomProvider]

    private var isVariable: Bool { amountType == .variable }
    private var isCustom: Bool { preset == nil }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return isVariable || (amountText.parsedAmount ?? 0) > 0
    }

    var body: some View {
        FormScreen(
            title: preset?.name ?? "Custom bill",
            showsCancel: false,
            primaryTitle: isVariable ? "Save account" : "Save bill",
            primaryEnabled: canSave,
            onPrimary: save
        ) {
            if profiles.count > 1 { profileCard }
            accountCard
            amountCard
            if isVariable { billInHandCard } else { scheduleCard }
            logoCard
            colourCard
            remindersCard
            paidWithCard
            if isCustom { rememberCard }
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
        FormCard(
            title: "Account",
            symbol: "person.text.rectangle",
            footer: isVariable ? "Saved on your Bills tab, so next month you only enter the amount and due date." : nil
        ) {
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("Name")
                TextField("Name", text: $name).insetField()
            }
            if isCustom {
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Category")
                    ChipGrid(
                        options: BillCategory.allCases,
                        selected: $category,
                        title: { $0.title },
                        symbol: { $0.symbol }
                    )
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(preset?.accountNumberLabel ?? "Account number (optional)")
                TextField("Account number", text: $accountNumber)
                    .textInputAutocapitalization(.characters)
                    .insetField()
            }
        }
    }

    private var amountCard: some View {
        FormCard(
            title: "Amount",
            symbol: "banknote",
            footer: isVariable
                ? "Changes every month, like electricity. It doesn't repeat; you add each bill when it arrives."
                : "The same every time, like rent or a subscription. It repeats on a schedule."
        ) {
            ChipGrid(options: AmountType.allCases, selected: $amountType, title: { $0.title })
            if !isVariable {
                amountField("Amount")
            }
        }
    }

    private func amountField(_ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(label)
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

    private var billInHandCard: some View {
        FormCard(
            title: "Bill in hand",
            symbol: "doc.text",
            footer: "Add the bill you just received. Leave the amount empty to only save the account."
        ) {
            amountField("Amount due (optional)")
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("Due date")
                DatePicker("Due date", selection: $billDueDate, displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("Billing period (optional)")
                TextField("Sep 28–Oct 27", text: $billingPeriod).insetField()
            }
        }
    }

    private var scheduleCard: some View {
        FormCard(
            title: "Schedule",
            symbol: "calendar",
            footer: recurrence == .once ? nil : "Repeats on this day each month. Short months use their last day."
        ) {
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("Repeats")
                ChipGrid(options: RecurrenceKind.allCases, selected: $recurrence, title: { $0.title })
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

    private var logoCard: some View {
        FormCard(
            title: "Logo",
            symbol: "photo",
            footer: "Optional. Use a logo you have the right to use. It's stored on your device and in your iCloud."
        ) {
            LogoPickerRow(logoData: $logoData, symbol: category.symbol, color: Color.adaptive(hex: colorHex))
        }
    }

    private var colourCard: some View {
        FormCard(title: "Colour", symbol: "paintpalette") {
            ColorChoiceRow(hex: $colorHex)
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

    private var paidWithCard: some View {
        FormCard(title: "Usually paid with", symbol: "creditcard") {
            PaymentMethodChips(selection: $paymentMethod)
        }
    }

    private var rememberCard: some View {
        FormCard(
            title: "Provider",
            symbol: "star",
            footer: "Shows up under “My providers” when you add your next bill."
        ) {
            OptionChip(
                title: "Remember as a provider",
                symbol: "star.fill",
                isSelected: rememberProvider
            ) { rememberProvider.toggle() }
        }
    }

    // MARK: Logic

    private func load() {
        guard !loaded else { return }
        loaded = true
        profile = profiles.first { $0.id.uuidString == defaultProfileID } ?? profiles.first
        if let preset {
            name = preset.name
            category = preset.category
            amountType = preset.amountType
            colorHex = preset.colorHex
            // A provider you saved earlier brings its uploaded logo along.
            if let provider = customProviders.first(where: { $0.asPreset.id == preset.id }) {
                logoData = provider.logoData
            }
        }
    }

    /// A saved variable account for the same provider, profile and account number, if there is one.
    private func existingVariableAccount() -> Bill? {
        guard let presetID = preset?.id else { return nil }
        let number = accountNumber.isEmpty ? nil : accountNumber
        let all = (try? modelContext.fetch(FetchDescriptor<Bill>())) ?? []
        return all.first {
            $0.amountType == .variable && !$0.isArchived && $0.presetID == presetID
                && $0.profile?.id == profile?.id && $0.accountNumber == number
        }
    }

    private func save() {
        let enteredAmount = amountText.parsedAmount
        let period = billingPeriod.trimmingCharacters(in: .whitespaces)

        // Reuse a saved account instead of creating a duplicate each time a bill arrives.
        if isVariable, let existing = existingVariableAccount() {
            if let amount = enteredAmount, amount > 0 {
                existing.addInstance(
                    dueDate: billDueDate, amount: amount,
                    billingPeriod: period.isEmpty ? nil : period, in: modelContext
                )
            }
            onDone()
            return
        }

        var presetID = preset?.id

        // A custom bill can be remembered as a provider for next time.
        if isCustom, rememberProvider {
            let provider = CustomProvider(name: name.trimmingCharacters(in: .whitespaces), category: category)
            provider.amountType = amountType
            provider.colorHex = colorHex
            provider.logoData = logoData
            modelContext.insert(provider)
            presetID = provider.asPreset.id
        }

        let bill = Bill(name: name.trimmingCharacters(in: .whitespaces))
        bill.presetID = presetID
        bill.colorHex = colorHex
        bill.logoData = logoData
        bill.category = category
        bill.accountNumber = accountNumber.isEmpty ? nil : accountNumber
        bill.amountType = amountType
        // Variable bills never store an amount or repeat; each bill is added when it arrives.
        bill.defaultAmount = isVariable ? nil : enteredAmount
        bill.recurrence = isVariable ? .once : recurrence
        bill.recurrenceInterval = recurrence == .everyNMonths ? interval : 1
        bill.startDate = startDate
        // The due day always comes from the picked date.
        bill.dueDay = Calendar.current.component(.day, from: startDate)
        bill.weekendRule = weekendRule
        bill.reminderOffsets = reminderOffsets.sorted(by: >)
        bill.paymentChoice = paymentMethod
        bill.profile = profile
        modelContext.insert(bill)

        if isVariable {
            if let amount = enteredAmount, amount > 0 {
                bill.addInstance(
                    dueDate: billDueDate, amount: amount,
                    billingPeriod: period.isEmpty ? nil : period, in: modelContext
                )
            }
        } else {
            InstanceGenerator.generate(for: bill, in: modelContext)
        }
        onDone()
    }
}

/// Reminder options shown when creating or editing a bill.
enum ReminderChoice {
    static let all: [(days: Int, title: String)] = [
        (7, "1 week before"), (3, "3 days before"), (1, "1 day before"), (0, "On the due date")
    ]
}
