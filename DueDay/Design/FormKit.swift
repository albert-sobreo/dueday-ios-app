import SwiftUI

// Building blocks for the app's forms: a screen with a Cancel pill and a bottom action button,
// glass cards with an icon and a spaced heading, and chip-style option buttons.
// The theme red is used for icons, chips, fields and buttons. Text (titles, labels, notes) stays
// in the system's primary and secondary colours.

enum FormStyle {
    /// Neutral fill behind text fields and other inputs, with no colour.
    static let fieldFill = Color.primary.opacity(0.06)
    /// Soft tint behind unselected chips.
    static let chipFill = Theme.accentSoft
    /// Fill of a selected chip.
    static let selectedFill = Theme.accent
    /// Text on a selected chip: white in light mode, dark in dark mode for contrast.
    static let onSelected = Theme.onAccent
}

extension View {
    /// The bottom action button in the forms: a glass pill in the app's theme colour.
    @ViewBuilder
    func formPrimaryButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent).tint(Theme.accent)
        } else {
            self.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(Theme.accent)
        }
    }
}

/// A form screen. As a sheet it shows a Cancel pill and a centred title; pushed onto a navigation
/// stack it uses the navigation bar's title and back button instead.
struct FormScreen<Content: View>: View {
    let title: String
    var showsCancel = true
    let primaryTitle: String
    var primaryEnabled = true
    /// Closes the form. A pushed form leaves this nil and uses the back button; a form at the root of a
    /// sheet passes it to get a Cancel button in the navigation bar.
    var onCancel: (() -> Void)?
    /// Everything the person can edit, as one value. Once it differs from how the form started, the
    /// form counts as changed: swiping it away is blocked and Cancel asks first. Leave it out for
    /// forms with nothing worth protecting.
    var changeToken: AnyHashable?
    let onPrimary: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var baseline: AnyHashable?
    @State private var confirmingDiscard = false

    private var hasChanges: Bool {
        guard let changeToken, let baseline else { return false }
        return changeToken != baseline
    }

    /// Cancel, after checking that nothing would be lost.
    private func requestCancel() {
        if hasChanges { confirmingDiscard = true } else { onCancel?() }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if showsCancel { sheetHeader }
                content()
            }
            .padding(.horizontal, 20)
            .padding(.top, showsCancel ? 20 : 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { primaryButton }
        .navigationTitle(showsCancel ? "" : title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(showsCancel ? .hidden : .automatic, for: .navigationBar)
        .toolbar {
            if !showsCancel, onCancel != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: requestCancel)
                }
            }
        }
        .interactiveDismissDisabled(hasChanges)
        // Forms fill in their starting values as they appear, so take the starting point just after.
        .task(id: changeToken == nil) {
            guard changeToken != nil else { return }
            try? await Task.sleep(for: .milliseconds(500))
            baseline = changeToken
        }
        .confirmationDialog("Discard your changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { onCancel?() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("What you've entered here won't be saved.")
        }
    }

    private var sheetHeader: some View {
        ZStack {
            Text(title)
                .font(.outfit(18, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(Theme.ink)
            HStack {
                Button(action: requestCancel) {
                    Text("Cancel")
                        .font(.outfit(16, weight: .medium))
                        .padding(.horizontal, 6)
                        .frame(minHeight: 36)
                }
                .secondaryButton(tint: Theme.accent)
                Spacer()
            }
        }
    }

    private var primaryButton: some View {
        Button(action: onPrimary) {
            Text(primaryTitle)
                .font(.outfit(18, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .formPrimaryButton()
        .disabled(!primaryEnabled)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.background.opacity(0.9))
    }
}

/// A glass card with an icon and a spaced, condensed heading, like a section of the form.
struct FormCard<Content: View>: View {
    let title: String
    let symbol: String
    var footer: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                Text(title.uppercased())
                    .font(.barlow(22, weight: .semibold, relativeTo: .title3))
                    .tracking(3)
                    .foregroundStyle(Theme.ink)
            }
            content()
            if let footer {
                Text(footer)
                    .font(.outfit(13, relativeTo: .footnote))
                    .foregroundStyle(Color.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassSurface(cornerRadius: 26)
    }
}

/// Small spaced label above a field.
struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.outfit(11, weight: .semibold, relativeTo: .caption2))
            .tracking(1.8)
            .foregroundStyle(Color.secondary)
    }
}

extension View {
    /// A softly tinted rounded field background, for text fields inside cards.
    func insetField() -> some View {
        self
            .font(.outfit(17))
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(FormStyle.fieldFill, in: .rect(cornerRadius: 14))
    }
}

/// A pill-shaped option: filled when selected, softly tinted when not.
struct OptionChip: View {
    let title: String
    var symbol: String?
    /// Left-aligns the icon and label instead of centring them.
    var leadingAligned = false
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol) }
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.outfit(15, weight: .semibold))
            .foregroundStyle(isSelected ? FormStyle.onSelected : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: leadingAligned ? .leading : .center)
            .padding(.horizontal, leadingAligned ? 16 : 8)
            .background(isSelected ? FormStyle.selectedFill : FormStyle.chipFill, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A two-column grid of chips for choosing one value. With an optional binding, tapping the
/// selected chip clears it.
struct ChipGrid<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value?
    var columns = 2
    /// Left-aligns each chip's icon and label instead of centring them.
    var leadingAligned = false
    let title: (Value) -> String
    var symbol: (Value) -> String? = { _ in nil }

    init(
        options: [Value],
        selection: Binding<Value?>,
        columns: Int = 2,
        leadingAligned: Bool = false,
        title: @escaping (Value) -> String,
        symbol: @escaping (Value) -> String? = { _ in nil }
    ) {
        self.options = options
        self._selection = selection
        self.columns = columns
        self.leadingAligned = leadingAligned
        self.title = title
        self.symbol = symbol
    }

    /// For a value that always has a selection.
    init(
        options: [Value],
        selected: Binding<Value>,
        columns: Int = 2,
        leadingAligned: Bool = false,
        title: @escaping (Value) -> String,
        symbol: @escaping (Value) -> String? = { _ in nil }
    ) {
        self.init(
            options: options,
            selection: Binding(get: { selected.wrappedValue }, set: { if let value = $0 { selected.wrappedValue = value } }),
            columns: columns,
            leadingAligned: leadingAligned,
            title: title,
            symbol: symbol
        )
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(options, id: \.self) { option in
                OptionChip(
                    title: title(option), symbol: symbol(option),
                    leadingAligned: leadingAligned, isSelected: selection == option
                ) {
                    selection = selection == option ? nil : option
                }
            }
        }
    }
}
