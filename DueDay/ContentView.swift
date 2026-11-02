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
            Tab("Today", systemImage: "house", value: AppTab.today) {
                NavigationStack { TodayView() }
            }

            Tab("Month", systemImage: "calendar", value: AppTab.month) {
                NavigationStack { MonthView() }
            }

            Tab("Bills", systemImage: "list.bullet", value: AppTab.bills) {
                NavigationStack { BillsListView() }
            }

            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }

            Tab("Add", systemImage: "plus", value: AppTab.add, role: .search) {
                AddBillView(
                    defaultProfileID: selectedProfileID,
                    externalSearch: $addSearchText,
                    onFinish: { selection = lastContentTab }
                )
            }
        }
        .id(currencyCode)
        .tint(Theme.tabTint)
        .searchable(text: $addSearchText, prompt: "Meralco, PLDT, SSS…")
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
        .modelContainer(for: [Profile.self, CustomProvider.self, Bill.self, BillInstance.self, Payment.self], inMemory: true)
}
