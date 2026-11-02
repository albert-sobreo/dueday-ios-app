import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack { UpcomingView() }
                .tabItem { Label("Upcoming", systemImage: "calendar") }

            NavigationStack { BillsListView() }
                .tabItem { Label("Bills", systemImage: "list.bullet") }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Bill.self, BillInstance.self, Payment.self], inMemory: true)
}
