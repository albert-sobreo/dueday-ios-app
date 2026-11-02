import SwiftUI

struct PresetPickerView: View {
    let onSelect: (BillPreset) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [BillPreset] {
        searchText.isEmpty
            ? PresetStore.all
            : PresetStore.all.filter { $0.name.localizedStandardContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(BillCategory.allCases) { category in
                    let presets = filtered.filter { $0.category == category }
                    if !presets.isEmpty {
                        Section(category.title) {
                            ForEach(presets) { preset in
                                Button {
                                    onSelect(preset)
                                    dismiss()
                                } label: {
                                    Label {
                                        Text(preset.name).foregroundStyle(.primary)
                                    } icon: {
                                        Image(systemName: preset.icon).foregroundStyle(preset.color)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText)
            .navigationTitle("Providers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
