import SwiftUI
import SwiftData

private extension View {
    /// The system search field for the Add tab. Nothing when this screen is a sheet.
    @ViewBuilder
    func searchInTab(_ text: Binding<String>?) -> some View {
        if let text {
            self.searchable(text: text, prompt: "Meralco, PLDT, SSS…")
        } else {
            self
        }
    }
}

/// Step 1 of 2: pick a saved account, a biller, or a custom bill.
/// Works as a sheet, or as the content of the tab bar's search tab (when `externalSearch` is given).
struct AddBillView: View {
    var defaultProfileID = ""
    /// In the search tab, the system's search field drives filtering. Nil means a sheet with its own field.
    var externalSearch: Binding<String>?
    /// Called after a bill was added. Nil closes the sheet instead.
    var onFinish: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Bill.name) private var bills: [Bill]
    @Query(sort: \CustomProvider.name) private var customProviders: [CustomProvider]

    @State private var localSearch = ""
    @State private var presetChoice: BillPreset?
    @State private var accountChoice: Bill?
    @State private var showingCustom = false
    @State private var isEditingProviders = false
    @State private var providerToEdit: CustomProvider?
    @State private var scanDraft: ScanDraft?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    // MARK: Data

    private var isInTab: Bool { externalSearch != nil }
    private var searchBinding: Binding<String> { externalSearch ?? $localSearch }
    private var searchText: String { searchBinding.wrappedValue }

    private func matches(_ name: String) -> Bool {
        searchText.isEmpty || name.localizedStandardContains(searchText)
    }

    /// Every saved account, so its details never need retyping.
    private var savedAccounts: [Bill] {
        bills.filter { !$0.isArchived && matches($0.name) }
    }

    private func subtitle(for account: Bill) -> String {
        let number = account.maskedAccountNumber
        let kind = account.amountType == .variable ? "add a bill" : "repeats · add extra bill"
        return [number, kind].compactMap { $0 }.joined(separator: " · ")
    }

    private var myProviders: [CustomProvider] { customProviders.filter { matches($0.name) } }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    VStack(alignment: .leading, spacing: 24) {
                        customButton
                        if !savedAccounts.isEmpty { savedAccountsSection }
                        if !myProviders.isEmpty { myProvidersSection }
                        ForEach(BillCategory.allCases) { category in
                            let presets = PresetStore.all.filter { $0.category == category && matches($0.name) }
                            if !presets.isEmpty { presetSection(category, presets) }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
            }
            .background(Theme.background)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if !isInTab {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                    }
                }
            }
            .searchInTab(externalSearch)
            .sheet(item: $providerToEdit) { ProviderEditSheet(provider: $0) }
            .navigationDestination(item: $accountChoice) { account in
                AddBillEntryForm(bill: account, onSaved: finish)
            }
            .navigationDestination(item: $presetChoice) { preset in
                NewAccountView(preset: preset, defaultProfileID: defaultProfileID, onDone: finish)
            }
            .navigationDestination(isPresented: $showingCustom) {
                NewAccountView(preset: nil, defaultProfileID: defaultProfileID, onDone: finish)
            }
            .navigationDestination(item: $scanDraft) { draft in
                ScanBillView(draft: draft, defaultProfileID: defaultProfileID, onDone: finish)
            }
        }
    }

    /// Leaves the add flow once a bill was added: back to the picker, the search cleared, and any scan dropped.
    private func finish() {
        accountChoice = nil
        presetChoice = nil
        scanDraft = nil
        showingCustom = false
        searchBinding.wrappedValue = ""
        if let onFinish { onFinish() } else { dismiss() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Step 1 of 2", color: Theme.addStrong)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text("ADD A BILL")
                .font(.barlow(60, relativeTo: .largeTitle))
                .foregroundStyle(Theme.addStrong)

            Text("Pick your biller and we fill in the rest.")
                .font(.outfit(16))
                .foregroundStyle(Theme.ink)

            // In the search tab the system provides the search field, so this one is only for the sheet.
            if !isInTab {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.mutedInk)
                    TextField("Meralco, PLDT, SSS…", text: searchBinding)
                        .font(.outfit(16))
                        .submitLabel(.search)
                    if !searchText.isEmpty {
                        Button("Clear", systemImage: "xmark.circle.fill") { searchBinding.wrappedValue = "" }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(Theme.mutedInk)
                    }
                }
                .padding(14)
                .glassSurface(cornerRadius: 16)
            }

            DashedDivider(color: Theme.addStrong.opacity(0.4))

            // Read a bill with the camera, or from a PDF or screenshot, all on the device.
            ScanTiles { scanDraft = $0 }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .background { Theme.addTint.padding(.top, -400) }
    }

    // MARK: Sections

    private var savedAccountsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Your accounts")
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(savedAccounts) { account in
                    Button { accountChoice = account } label: {
                        ProviderTile(
                            icon: account.displayIcon,
                            color: account.displayColor,
                            title: account.name,
                            subtitle: subtitle(for: account),
                            logo: account.logoData
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var myProvidersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow("My providers")
                Spacer()
                Button(isEditingProviders ? "Done" : "Edit") { isEditingProviders.toggle() }
                    .font(.outfit(14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(myProviders) { provider in
                    Button {
                        // In edit mode a tap edits the provider; otherwise it picks it.
                        if isEditingProviders {
                            providerToEdit = provider
                        } else {
                            presetChoice = provider.asPreset
                        }
                    } label: {
                        ProviderTile(
                            icon: provider.category.symbol,
                            color: Color.adaptive(hex: provider.colorHex),
                            title: provider.name,
                            subtitle: provider.amountType.title,
                            logo: provider.logoData
                        )
                        .overlay(alignment: .topTrailing) {
                            if isEditingProviders {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.title3)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Theme.accent)
                                    .padding(6)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit Provider", systemImage: "pencil") { providerToEdit = provider }
                    }
                }
            }
        }
    }

    private func presetSection(_ category: BillCategory, _ presets: [BillPreset]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(category.title)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(presets) { preset in
                    Button { presetChoice = preset } label: {
                        ProviderTile(
                            icon: preset.icon,
                            color: preset.color,
                            title: preset.name,
                            subtitle: preset.amountType.title
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var customButton: some View {
        Button { showingCustom = true } label: {
            Label("Custom bill — rent, tuition, loans", systemImage: "plus")
                .font(.outfit(16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .tint(Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.mutedInk.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
        }
        .buttonStyle(.plain)
    }
}

/// A biller or saved account in the picker grid.
struct ProviderTile: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    /// The user's uploaded logo, if any.
    var logo: Data?

    var body: some View {
        HStack(spacing: 10) {
            LogoBadge(logo: logo, symbol: icon, color: color, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.outfit(15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.outfit(12, relativeTo: .caption))
                    .foregroundStyle(Theme.mutedInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .glassSurface(cornerRadius: 16)
        .contentShape(.rect)
    }
}
