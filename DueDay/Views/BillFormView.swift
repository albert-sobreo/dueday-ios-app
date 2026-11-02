import SwiftUI
import SwiftData

/// Add a new bill (`bill == nil`) or edit an existing one.
struct BillFormView: View {
    let bill: Bill?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var presetID: String?
    @State private var category = BillCategory.other
    @State private var accountNumber = ""
    @State private var amountType = AmountType.fixed
    @State private var amountText = ""
    @State private var recurrence = RecurrenceKind.monthly
    @State private var interval = 2
    @State private var startDate = Date()
    @State private var dueDay = 1
    @State private var weekendRule = WeekendRule.none
    @State private var reminderOffsets: Set<Int> = [3, 0]
    @State private var paymentMethod: PaymentMethod?
    @State private var showingPresets = false

    private static let reminderChoices: [(days: Int, title: String)] = [
        (7, "1 week before"), (3, "3 days before"), (1, "1 day before"), (0, "On the due date")
    ]

    private var preset: BillPreset? { PresetStore.preset(withID: presetID) }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (amountType == .variable || (amountText.parsedAmount ?? 0) > 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { showingPresets = true } label: {
                        Label(preset?.name ?? "Choose a provider", systemImage: "list.bullet.rectangle")
                    }
                    TextField("Name", text: $name)
                    Picker("Category", selection: $category) {
                        ForEach(BillCategory.allCases) { Text($0.title).tag($0) }
                    }
                    TextField(preset?.accountNumberLabel ?? "Account number (optional)", text: $accountNumber)
                }

                Section {
                    Picker("Amount", selection: $amountType) {
                        ForEach(AmountType.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if amountType == .fixed {
                        TextField("₱0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    Text("Amount")
                } footer: {
                    if amountType == .variable {
                        Text("You'll enter the actual amount when each bill arrives.")
                    }
                }

                Section("Schedule") {
                    Picker("Repeats", selection: $recurrence) {
                        ForEach(RecurrenceKind.allCases) { Text($0.title).tag($0) }
                    }
                    if recurrence == .everyNMonths {
                        Stepper("Every \(interval) months", value: $interval, in: 2...11)
                    }
                    Stepper("Due on day \(dueDay)", value: $dueDay, in: 1...31)
                    DatePicker("First due month", selection: $startDate, displayedComponents: .date)
                    Picker("If it falls on a weekend", selection: $weekendRule) {
                        ForEach(WeekendRule.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section("Reminders") {
                    ForEach(Self.reminderChoices, id: \.days) { choice in
                        Toggle(choice.title, isOn: reminderBinding(choice.days))
                    }
                }

                Section("Usually paid with") {
                    Picker("Method", selection: $paymentMethod) {
                        Text("Not specified").tag(PaymentMethod?.none)
                        ForEach(PaymentMethod.allCases) { method in
                            Label(method.title, systemImage: method.symbol)
                                .tag(PaymentMethod?.some(method))
                        }
                    }
                }
            }
            .navigationTitle(bill == nil ? "New Bill" : "Edit Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingPresets) {
                PresetPickerView { apply($0) }
            }
            .onAppear(perform: load)
        }
    }

    private func reminderBinding(_ days: Int) -> Binding<Bool> {
        Binding(
            get: { reminderOffsets.contains(days) },
            set: { isOn in
                if isOn { reminderOffsets.insert(days) } else { reminderOffsets.remove(days) }
            }
        )
    }

    private func apply(_ preset: BillPreset) {
        presetID = preset.id
        name = preset.name
        category = preset.category
        amountType = preset.amountType
    }

    private func load() {
        guard let bill else { return }
        name = bill.name
        presetID = bill.presetID
        category = bill.category
        accountNumber = bill.accountNumber ?? ""
        amountType = bill.amountType
        amountText = bill.defaultAmount.map { "\($0)" } ?? ""
        recurrence = bill.recurrence
        interval = max(bill.recurrenceInterval, 2)
        startDate = bill.startDate
        dueDay = bill.dueDay
        weekendRule = bill.weekendRule
        reminderOffsets = Set(bill.reminderOffsets)
        paymentMethod = bill.defaultPaymentMethod
    }

    private func save() {
        let target = bill ?? Bill()
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.presetID = presetID
        target.category = category
        target.accountNumber = accountNumber.isEmpty ? nil : accountNumber
        target.amountType = amountType
        target.defaultAmount = amountType == .fixed ? amountText.parsedAmount : nil
        target.recurrence = recurrence
        target.recurrenceInterval = recurrence == .everyNMonths ? interval : 1
        target.startDate = startDate
        target.dueDay = dueDay
        target.weekendRule = weekendRule
        target.reminderOffsets = reminderOffsets.sorted(by: >)
        target.defaultPaymentMethod = paymentMethod

        if bill == nil {
            modelContext.insert(target)
            InstanceGenerator.generate(for: target, in: modelContext)
        } else {
            InstanceGenerator.regenerate(for: target, in: modelContext)
        }
        dismiss()
    }
}
