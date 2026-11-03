import SwiftUI
import StoreKit

/// "Support DueDay": three optional tips. Shown as a section of the Settings form.
struct SupportSection: View {
    @State private var tips = TipJar.shared

    var body: some View {
        Section {
            if tips.isLoading && tips.products.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading tips…").foregroundStyle(Theme.mutedInk)
                }
            } else if tips.products.isEmpty {
                Text("Tips aren't available right now.")
                    .foregroundStyle(Theme.mutedInk)
            } else {
                ForEach(tips.products) { product in
                    Button {
                        Task { await tips.buy(product) }
                    } label: {
                        HStack {
                            Label(product.displayName, systemImage: "heart")
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            if tips.purchasingID == product.id {
                                ProgressView()
                            } else {
                                // The price comes from the App Store, so it's right in every currency.
                                Text(product.displayPrice)
                                    .font(.outfit(16, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .disabled(tips.purchasingID != nil)
                }
            }

            if tips.isSupporter {
                Label("Supporter · thank you!", systemImage: "heart.fill")
                    .foregroundStyle(Theme.accent)
            }
        } header: {
            Text("Support DueDay")
        } footer: {
            Text("DueDay is free, with no ads. A tip is completely optional and unlocks nothing.")
        }
        // The thank-you sheet and the error alert are attached to the Settings screen instead. They
        // used to be here, but buying a tip adds a row to this section, and a sheet on a section
        // whose rows change can be dismissed the moment it appears.
        .task { await tips.load() }
    }
}

extension View {
    /// The tip jar's thank-you sheet and error alert. Put them on a view that stays in place,
    /// such as the whole Settings screen, and not on the section that changes after a tip.
    func tipJarPresentations() -> some View {
        modifier(TipJarPresentations())
    }
}

private struct TipJarPresentations: ViewModifier {
    @State private var tips = TipJar.shared

    func body(content: Content) -> some View {
        content
            .alert(
                "Something went wrong",
                isPresented: Binding(get: { tips.errorMessage != nil }, set: { if !$0 { tips.errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(tips.errorMessage ?? "")
            }
            .sheet(isPresented: $tips.showThankYou) { ThankYouView() }
    }
}

/// Shown after a tip.
struct ThankYouView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "heart.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.accent)
            Text("THANK YOU")
                .font(.barlow(54, weight: .medium, relativeTo: .largeTitle))
                .foregroundStyle(Theme.ink)
            Text("Your tip helps keep DueDay free and ad-free for everyone. It means a lot.")
                .font(.outfit(17))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.mutedInk)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                dismiss()
            } label: {
                // The width has to be set on the label, or the glass button hugs its text.
                Text("Done")
                    .font(.outfit(18, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .primaryButton()
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .presentationDetents([.medium])
    }
}
