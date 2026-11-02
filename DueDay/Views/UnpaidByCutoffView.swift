import SwiftUI
import SwiftData

/// Unpaid bills grouped by cutoff: what's overdue, what's left in the current cutoff, and what's
/// coming in the next ones. Used at the top of the Bills tab.
struct UnpaidByCutoffView: View {
    let selectedProfileID: String

    @Query(sort: \BillInstance.dueDate) private var instances: [BillInstance]
    @Query(sort: \Profile.sortOrder) private var profiles: [Profile]

    private var calendar: Calendar { .current }

    // MARK: Data

    private var unpaid: [BillInstance] {
        instances.filter {
            !$0.isPaid && $0.bill?.isArchived != true && ($0.bill?.isIn(profileID: selectedProfileID) ?? false)
        }
    }

    private var overdue: [BillInstance] { unpaid.filter { $0.status() == .overdue } }
    private var upcoming: [BillInstance] { unpaid.filter { $0.status() != .overdue } }

    private var paydays: [Int] {
        profiles.first { $0.id.uuidString == selectedProfileID }?.paydays ?? []
    }

    /// The cutoff we're in, then the following ones, oldest first.
    private var cutoffs: [Cutoff] {
        guard !paydays.isEmpty else { return [] }
        let today = calendar.startOfDay(for: .now)
        var seen = Set<Date>()
        var result: [Cutoff] = []
        for offset in 0...3 {
            guard let month = calendar.date(byAdding: .month, value: offset, to: today) else { continue }
            for cutoff in CutoffCalculator.cutoffs(paydays: paydays, in: month, calendar: calendar)
            where cutoff.endDate >= today && seen.insert(cutoff.startDate).inserted {
                result.append(cutoff)
            }
        }
        return result.sorted { $0.startDate < $1.startDate }
    }

    private func total(_ items: [BillInstance]) -> Decimal {
        items.reduce(0) { $0 + ($1.amount ?? 0) }
    }

    // MARK: Body

    var body: some View {
        if unpaid.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 24) {
                Text("TO PAY")
                    .font(.barlow(30, relativeTo: .title))
                    .foregroundStyle(Theme.ink)
                    .padding(.bottom, -12)

                if !overdue.isEmpty {
                    group(title: "Overdue", tint: Theme.danger, items: overdue)
                }

                if paydays.isEmpty {
                    group(title: "Unpaid", tint: nil, items: upcoming)
                    if selectedProfileID.isEmpty {
                        note("Pick a profile to group these by cutoff.")
                    } else {
                        note("Set this profile's paydays in Settings → Cutoffs to group these by cutoff.")
                    }
                } else {
                    cutoffGroups
                }
            }
        }
    }

    @ViewBuilder
    private var cutoffGroups: some View {
        ForEach(Array(cutoffs.prefix(4).enumerated()), id: \.element.startDate) { index, cutoff in
            let items = upcoming.filter { cutoff.contains($0.dueDate) }
            let prefix = index == 0 ? "Current cutoff" : index == 1 ? "Next cutoff" : "Later"
            // The current and next cutoffs always show; later empty ones are skipped.
            if !items.isEmpty || index < 2 {
                group(
                    title: "\(prefix) · \(cutoff.longTitle())",
                    tint: nil,
                    items: items,
                    emptyText: index == 0 ? "Nothing left to pay this cutoff." : "No bills in this cutoff yet."
                )
            }
        }
    }

    private func group(title: String, tint: Color?, items: [BillInstance], emptyText: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(title, color: tint ?? Theme.mutedInk)
                Spacer()
                if !items.isEmpty {
                    Text(total(items).currencyString)
                        .font(.barlow(20, weight: .medium, relativeTo: .title3))
                        .foregroundStyle(tint ?? Theme.ink)
                }
            }

            if items.isEmpty, let emptyText {
                Text(emptyText)
                    .font(.outfit(14, relativeTo: .footnote))
                    .foregroundStyle(Theme.mutedInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, instance in
                        if index > 0 { Divider().padding(.leading, 62) }
                        row(instance)
                    }
                }
                .padding(.vertical, 6)
                .glassSurface(cornerRadius: 22)
            }
        }
    }

    @ViewBuilder
    private func row(_ instance: BillInstance) -> some View {
        if let bill = instance.bill {
            NavigationLink(value: bill) {
                HStack(spacing: 12) {
                    LogoBadge(logo: bill.logoData, symbol: bill.displayIcon, color: bill.displayColor, size: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bill.name)
                            .font(.outfit(16, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        let chip = BillStatusText.chip(for: instance)
                        HStack(spacing: 6) {
                            Text(instance.dueDate.formatted(.dateTime.month(.abbreviated).day()).uppercased())
                                .font(.outfit(12, weight: .semibold, relativeTo: .caption))
                                .foregroundStyle(Theme.mutedInk)
                            StatusChip(text: chip.text, foreground: chip.foreground, background: chip.background)
                        }
                    }
                    Spacer()
                    Text(instance.amount?.currencyString ?? "—")
                        .font(.barlow(22, weight: .medium, relativeTo: .title3))
                        .foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.outfit(13, relativeTo: .footnote))
            .foregroundStyle(Theme.mutedInk)
    }
}
