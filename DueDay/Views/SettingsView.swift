import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Query(sort: \Profile.sortOrder) private var profiles: [Profile]
    @AppStorage(selectedProfileKey) private var selectedProfileID = ""
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system.rawValue
    @AppStorage(CurrencySetting.storageKey) private var currencyCode = CurrencySetting.detectedCode
    @AppStorage(ReminderSettings.minutesKey) private var reminderMinutes = ReminderSettings.defaultMinutes
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @State private var showingProfiles = false
    @State private var confirmingClear = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    #if DEBUG
    /// Adds the sample accounts and bills, then keeps generated bills and reminders up to date.
    private func loadSampleBills() {
        SampleData.populate(in: modelContext)
        ProfileSeeder.ensureDefault(in: modelContext)
        InstanceGenerator.generateAll(in: modelContext)
        let context = modelContext
        Task {
            try? context.save()
            await ReminderScheduler.reschedule(in: context)
        }
    }

    /// Wipes the store for testing, then brings back the default profile as on a fresh install.
    private func clearAllData() {
        try? modelContext.delete(model: Bill.self)
        try? modelContext.delete(model: BillInstance.self)
        try? modelContext.delete(model: Payment.self)
        try? modelContext.delete(model: CustomProvider.self)
        try? modelContext.delete(model: CustomPaymentMethod.self)
        try? modelContext.delete(model: Profile.self)
        try? modelContext.save()
        // Forget the choice, so the fresh Personal profile is selected like on a first launch.
        UserDefaults.standard.removeObject(forKey: selectedProfileKey)
        ProfileSeeder.ensureDefault(in: modelContext)
        let context = modelContext
        Task { await ReminderScheduler.reschedule(in: context) }
    }
    #endif

    /// The reminder time as a date, for the time picker.
    private var reminderTime: Binding<Date> {
        Binding(
            get: { ReminderSettings.date(on: .now) },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                reminderMinutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private var notificationsAllowed: Bool {
        notificationStatus == .authorized || notificationStatus == .provisional || notificationStatus == .ephemeral
    }

    /// The offered currencies, plus the region's own if it isn't in the list.
    private var currencyChoices: [String] {
        var codes = CurrencySetting.choices
        if !codes.contains(CurrencySetting.detectedCode) { codes.insert(CurrencySetting.detectedCode, at: 0) }
        return codes
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            // The title is the first row, so it scrolls away with the page, like on Bills.
            Text("SETTINGS")
                .font(.barlow(60, weight: .medium, relativeTo: .largeTitle))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(Color.clear)
                // Same top and side spacing as the title on Bills (8 down, 20 in from the edge).
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))

            Section {
                ForEach(profiles) { profile in
                    NavigationLink {
                        CutoffSetupView(profile: profile)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: profile.kind.symbol)
                                .font(.footnote)
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color(hex: profile.colorHex), in: .rect(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(profile.name).font(.outfit(16, weight: .semibold))
                                Text(CutoffSetupView.summary(for: profile.paydays))
                                    .font(.outfit(13))
                                    .foregroundStyle(Theme.mutedInk)
                            }
                        }
                    }
                }
            } header: {
                Text("Cutoffs")
            } footer: {
                Text("A cutoff is the stretch of the month between two paydays. DueDay adds up the bills in each one so you know how much to set aside before you're paid.")
            }

            Section {
                DatePicker("Remind me at", selection: reminderTime, displayedComponents: .hourAndMinute)

                if notificationsAllowed {
                    Label("Notifications are on", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.paid)
                } else if notificationStatus == .notDetermined {
                    Button("Allow Notifications", systemImage: "bell.badge") {
                        Task {
                            _ = await ReminderScheduler.requestAuthorizationIfNeeded()
                            notificationStatus = await ReminderScheduler.authorizationStatus()
                            await ReminderScheduler.reschedule(in: modelContext)
                        }
                    }
                } else {
                    Label("Notifications are turned off for DueDay", systemImage: "bell.slash")
                        .foregroundStyle(Theme.warning)
                    Button("Open Settings", systemImage: "gearshape") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("Each bill reminds you on the days set in its own settings, at this time. Reminders have a Mark paid button.")
            }

            Section {
                Picker("Theme", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            } footer: {
                Text("System follows your iPhone's light or dark setting.")
            }

            Section("Profiles") {
                Button("Manage Profiles", systemImage: "person.2") { showingProfiles = true }
            }

            SupportSection()

            Section("About") {
                LabeledContent("Version", value: versionText)
                Label("Your bills stay on this device. DueDay has no accounts and no server.", systemImage: "lock.shield")
                    .font(.outfit(14))
                    .foregroundStyle(Theme.mutedInk)
            }

            #if DEBUG
            Section {
                Button("Load Sample Bills", systemImage: "tray.and.arrow.down") { loadSampleBills() }
                Button("Clear All Data", systemImage: "trash", role: .destructive) { confirmingClear = true }
            } header: {
                Text("Debug")
            } footer: {
                Text("Only in debug builds. Sample bills are added to what you have. Clear All Data removes every bill, payment, profile and custom provider, and cancels reminders.")
            }
            #endif
        }
        .dueDayForm()
        // A list starts with extra space at the top; remove it so the title sits where Bills' does.
        .contentMargins(.top, 0, for: .scrollContent)
        .ownsTopOfScreen()
        #if DEBUG
        .confirmationDialog("Clear all data?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive, action: clearAllData)
        } message: {
            Text("This can't be undone.")
        }
        #endif
        .task { notificationStatus = await ReminderScheduler.authorizationStatus() }
        .onChange(of: reminderMinutes) {
            Task { await ReminderScheduler.reschedule(in: modelContext) }
        }
        .sheet(isPresented: $showingProfiles) {
            ProfilesView(selectedID: $selectedProfileID)
        }
    }
}

/// Set a profile's paydays, which split each month into cutoffs.
struct CutoffSetupView: View {
    @Bindable var profile: Profile

    private static let maxPaydays = 4

    private static let quickSetups: [(title: String, days: [Int])] = [
        ("15th & 30th", [15, 30]),
        ("10th & 25th", [10, 25]),
        ("Once a month, 30th", [30]),
        ("No cutoffs", []),
    ]

    /// "Paydays: 15th, 30th" or "No cutoffs".
    static func summary(for paydays: [Int]) -> String {
        guard !paydays.isEmpty else { return "No cutoffs" }
        return "Paydays: " + paydays.sorted().map(ordinal).joined(separator: ", ")
    }

    static func ordinal(_ day: Int) -> String {
        let suffix: String
        if (11...13).contains(day % 100) {
            suffix = "th"
        } else {
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(day)\(suffix)"
    }

    private var previewCutoffs: [Cutoff] {
        CutoffCalculator.cutoffs(paydays: profile.paydays, in: .now)
    }

    var body: some View {
        Form {
            Section {
                ForEach(profile.paydays.indices, id: \.self) { index in
                    Stepper(
                        "Payday \(index + 1): the \(Self.ordinal(profile.paydays[index]))",
                        value: $profile.paydays[index],
                        in: 1...31
                    )
                }
                .onDelete { profile.paydays.remove(atOffsets: $0) }

                if profile.paydays.count < Self.maxPaydays {
                    Button("Add Payday", systemImage: "plus") {
                        profile.paydays.append(profile.paydays.last.map { min($0 + 15, 30) } ?? 15)
                    }
                }
            } header: {
                Text("Paydays")
            } footer: {
                Text("Days of the month you get paid. Each cutoff runs from the day after one payday to the next, so with the 10th and 25th you get 26th–10th and 11th–25th. A payday later than a short month's last day moves to its last day.")
            }

            Section("Quick setup") {
                ForEach(Self.quickSetups, id: \.title) { setup in
                    Button {
                        profile.paydays = setup.days
                    } label: {
                        HStack {
                            Text(setup.title).foregroundStyle(Theme.ink)
                            Spacer()
                            if profile.paydays.sorted() == setup.days.sorted() {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }

            Section {
                if previewCutoffs.isEmpty {
                    Text("No cutoffs. Add a payday to split the month.")
                        .foregroundStyle(Theme.mutedInk)
                } else {
                    ForEach(previewCutoffs.indices, id: \.self) { index in
                        let cutoff = previewCutoffs[index]
                        HStack {
                            Text(cutoff.longTitle())
                                .font(.outfit(16, weight: .semibold))
                            Spacer()
                            if let payday = cutoff.payday {
                                Text("Payday \(payday.formatted(.dateTime.month(.abbreviated).day()))")
                                    .font(.outfit(14))
                                    .foregroundStyle(Theme.paid)
                            }
                        }
                    }
                }
            } header: {
                Text("This month")
            }
        }
        .dueDayForm()
        .navigationTitle("\(profile.name) cutoffs")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            // Keep paydays sorted and free of duplicates.
            profile.paydays = Array(Set(profile.paydays)).sorted()
        }
    }
}
