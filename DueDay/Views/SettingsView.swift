import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query(sort: \Profile.sortOrder) private var profiles: [Profile]
    @AppStorage(selectedProfileKey) private var selectedProfileID = ""
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system.rawValue
    @AppStorage(CurrencySetting.storageKey) private var currencyCode = CurrencySetting.detectedCode
    @State private var showingProfiles = false

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

            Section("About") {
                LabeledContent("Version", value: versionText)
                Label("Your bills stay on this device. DueDay has no accounts and no server.", systemImage: "lock.shield")
                    .font(.outfit(14))
                    .foregroundStyle(Theme.mutedInk)
            }
        }
        .dueDayForm()
        .navigationTitle("Settings")
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
