import SwiftUI
import SwiftData

/// Key for the selected profile's id. An empty string means "All profiles".
let selectedProfileKey = "selectedProfileID"

extension Bill {
    /// Whether the bill belongs to the selected profile (or any, when the selection is empty).
    func isIn(profileID: String) -> Bool {
        profileID.isEmpty || profile?.id.uuidString == profileID
    }
}

/// Toolbar menu to pick which profile's bills to show.
struct ProfileSwitcher: View {
    @Binding var selectedID: String
    @Query(sort: \Profile.sortOrder) private var profiles: [Profile]

    @State private var showingManager = false

    private var selected: Profile? { profiles.first { $0.id.uuidString == selectedID } }

    var body: some View {
        Menu {
            Picker("Profile", selection: $selectedID) {
                Label("All profiles", systemImage: "square.stack").tag("")
                ForEach(profiles) { profile in
                    Label(profile.name, systemImage: profile.kind.symbol).tag(profile.id.uuidString)
                }
            }
            Divider()
            Button("Manage Profiles…", systemImage: "gearshape") { showingManager = true }
        } label: {
            Label(selected?.name ?? "All", systemImage: selected?.kind.symbol ?? "square.stack")
        }
        .sheet(isPresented: $showingManager) {
            ProfilesView(selectedID: $selectedID)
        }
    }
}
