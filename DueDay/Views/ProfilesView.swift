import SwiftUI
import SwiftData

/// Lists profiles and lets you add, edit, reorder-free delete them.
struct ProfilesView: View {
    @Binding var selectedID: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Profile.sortOrder) private var profiles: [Profile]

    @State private var profileToEdit: Profile?
    @State private var showingNew = false
    @State private var profileToDelete: Profile?

    var body: some View {
        NavigationStack {
            List {
                ForEach(profiles) { profile in
                    Button { profileToEdit = profile } label: {
                        HStack(spacing: 12) {
                            Image(systemName: profile.kind.symbol)
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Color(hex: profile.colorHex), in: .rect(cornerRadius: 9))
                            VStack(alignment: .leading) {
                                Text(profile.name).font(.headline)
                                Text("\(profile.kind.title) · \((profile.bills ?? []).count) bills")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        // Keep at least one profile so new bills always have a home.
                        if profiles.count > 1 {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                profileToDelete = profile
                            }
                        }
                    }
                }
            }
            .navigationTitle("Profiles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Profile", systemImage: "plus") { showingNew = true }
                }
            }
            .sheet(isPresented: $showingNew) {
                ProfileFormView(profile: nil, nextSortOrder: (profiles.last?.sortOrder ?? 0) + 1)
            }
            .sheet(item: $profileToEdit) { ProfileFormView(profile: $0, nextSortOrder: 0) }
            .confirmationDialog(
                "Delete \(profileToDelete?.name ?? "profile")?",
                isPresented: Binding(get: { profileToDelete != nil }, set: { if !$0 { profileToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete Profile and Its Bills", role: .destructive) {
                    if let profile = profileToDelete {
                        if selectedID == profile.id.uuidString { selectedID = "" }
                        modelContext.delete(profile)
                    }
                    profileToDelete = nil
                }
            } message: {
                Text("This also deletes all of its bills and payment history.")
            }
        }
    }
}

struct ProfileFormView: View {
    let profile: Profile?
    let nextSortOrder: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind = ProfileKind.personal
    @State private var colorHex = Profile.palette[0]
    @State private var paydays: [Int] = [15, 30]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $kind) {
                        ForEach(ProfileKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                }

                Section("Colour") {
                    HStack {
                        ForEach(Profile.palette, id: \.self) { hex in
                            Button { colorHex = hex } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if hex == colorHex {
                                            Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Colour \(hex)")
                        }
                    }
                }

                Section {
                    ForEach(paydays.indices, id: \.self) { index in
                        Stepper("Day \(paydays[index])", value: $paydays[index], in: 1...31)
                    }
                    .onDelete { paydays.remove(atOffsets: $0) }
                    if paydays.count < 4 {
                        Button("Add Payday", systemImage: "plus") { paydays.append(15) }
                    }
                } header: {
                    Text("Paydays")
                } footer: {
                    Text("Used to split bills into cutoffs. Leave empty if this profile doesn't follow paydays.")
                }
            }
            .navigationTitle(profile == nil ? "New Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard let profile else { return }
                name = profile.name
                kind = profile.kind
                colorHex = profile.colorHex
                paydays = profile.paydays
            }
        }
    }

    private func save() {
        let target = profile ?? Profile()
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.kind = kind
        target.colorHex = colorHex
        target.paydays = Array(Set(paydays)).sorted()
        if profile == nil {
            target.sortOrder = nextSortOrder
            modelContext.insert(target)
        }
        dismiss()
    }
}
