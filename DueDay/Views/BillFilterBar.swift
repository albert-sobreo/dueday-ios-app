import SwiftUI
import SwiftData

private extension View {
    /// Liquid Glass on iOS 26 and later: tinted with the theme colour when selected, clear otherwise.
    /// Earlier versions get a solid capsule.
    @ViewBuilder
    func filterGlass(isSelected: Bool) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(
                isSelected ? .regular.tint(Theme.accent).interactive() : .regular.interactive(),
                in: .capsule
            )
        } else {
            self.background(isSelected ? Theme.accent : Theme.accentSoft, in: .capsule)
        }
    }
}

/// A scrolling row of quick filters, each with a count where it makes sense.
struct BillFilterBar: View {
    @Binding var selection: BillFilter
    let selectedProfileID: String
    /// Made once by the Bills tab and shared with the list below, so the work isn't done twice.
    let engine: BillFilterEngine

    /// Cutoff filters only appear when the selected profile has paydays.
    private func available(_ engine: BillFilterEngine) -> [BillFilter] {
        BillFilter.allCases.filter { !$0.needsCutoffs || !engine.paydays.isEmpty }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(available(engine)) { filter in
                    chip(filter, count: engine.count(for: filter))
                }
            }
            .padding(.horizontal, 20)
        }
        // Let the row run to the screen edges.
        .padding(.horizontal, -20)
        .scrollClipDisabled()
        // A profile without paydays has no cutoff filters, so fall back if one was selected.
        .onAppear {
            if !available(engine).contains(selection) { selection = .all }
        }
        .onChange(of: selectedProfileID) {
            if !available(engine).contains(selection) { selection = .all }
        }
    }

    private func chip(_ filter: BillFilter, count: Int?) -> some View {
        let isSelected = selection == filter
        return Button {
            withAnimation(.snappy) { selection = filter }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: filter.symbol)
                Text(filter.title)
                if let count, count > 0 {
                    Text("\(count)")
                        .contentTransition(.numericText())
                        .font(.outfit(12, weight: .bold, relativeTo: .caption))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(isSelected ? Theme.onAccent.opacity(0.22) : Theme.accent.opacity(0.14), in: .capsule)
                }
            }
            .font(.outfit(14, weight: .semibold, relativeTo: .subheadline))
            .foregroundStyle(isSelected ? Theme.onAccent : Theme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .filterGlass(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count.map { "\(filter.title), \($0)" } ?? filter.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
