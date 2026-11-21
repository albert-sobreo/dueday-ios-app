import SwiftUI
import SwiftData

struct ContentView: View {
    private enum AppTab: Hashable {
        case today, month, bills, settings, add
    }

    @AppStorage(selectedProfileKey) private var selectedProfileID = ""
    @State private var selection: AppTab = .today
    @State private var lastContentTab: AppTab = .today
    @State private var addSearchText = ""
    /// Read so every screen redraws with the new currency when it's changed in Settings.
    @AppStorage(CurrencySetting.storageKey) private var currencyCode = CurrencySetting.detectedCode

    var body: some View {
        // The standard system tab bar. The search-role tab is pinned by the system in its own round
        // bubble at the trailing edge. Here it holds "Add a bill", and the search field the system
        // shows for it filters the billers.
        TabView(selection: $selection) {
            // Each tab shows its name under the icon, so the less obvious ones (Bills, Month) are clear.
            Tab(value: AppTab.today) {
                NavigationStack { TodayView() }
            } label: {
                Label("Today", systemImage: "house")
            }

            Tab(value: AppTab.bills) {
                NavigationStack { BillsListView() }
            } label: {
                Label("Bills", systemImage: "list.bullet")
            }

            Tab(value: AppTab.month) {
                NavigationStack { MonthView() }
            } label: {
                Label("Month", systemImage: "calendar")
            }

            Tab(value: AppTab.settings) {
                NavigationStack { SettingsView() }
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Tab(value: AppTab.add, role: .search) {
                AddBillView(
                    defaultProfileID: selectedProfileID,
                    externalSearch: $addSearchText,
                    onFinish: { selection = lastContentTab }
                )
            } label: {
                Label("Add", systemImage: "plus")
            }
            .accessibilityLabel("Add a bill")
        }
        .id(currencyCode)
        .tint(Theme.tabTint)
        // The search field itself is on the Add screen, not here: put on the whole tab view, it
        // also showed up in every sheet, such as Profiles.
        .searchActivatesOnSelection()
        .onChange(of: selection) { _, newValue in
            if newValue != .add { lastContentTab = newValue }
        }
    }
}

private extension View {
    /// Selecting the search tab starts a search. Needs iOS 26; earlier versions skip it.
    @ViewBuilder
    func searchActivatesOnSelection() -> some View {
        if #available(iOS 26.0, *) {
            self.tabViewSearchActivation(.searchTabSelection)
        } else {
            self
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Profile.self, CustomProvider.self, CustomPaymentMethod.self, Bill.self, BillInstance.self, Payment.self], inMemory: true)
}
