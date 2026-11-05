import SwiftUI
import SwiftData

/// The bills section at the top of the Bills tab. With the "All" filter it's the full overview:
/// what's overdue, then each cutoff. With any other filter it shows just that list.
struct UnpaidByCutoffView: View {
    let selectedProfileID: String
    var filter: BillFilter = .all

    /// Made once by the Bills tab and shared with the filter bar.
    let engine: BillFilterEngine

    /// One titled list of bills, with its total.
    private struct Group {
        let title: String
        var tint: Color?
        let items: [BillInstance]
        /// Variable accounts whose bill hasn't been added yet, shown after the bills as "No bill yet".
        var awaiting: [AwaitedBill] = []
        var emptyText: String?

        var isEmpty: Bool { items.isEmpty && awaiting.isEmpty }
    }

    // MARK: Data

    private func total(_ items: [BillInstance]) -> Decimal {
        items.reduce(0) { $0 + ($1.amount ?? 0) }
    }

    private func cutoffName(_ index: Int) -> String {
        index == 0 ? "Current cutoff" : index == 1 ? "Next cutoff" : "Later"
    }

    /// The lists for the chosen filter. They're drawn by position, so switching filters changes the
    /// text of the same headings in place, and their words and numbers can roll.
    private var groups: [Group] {
        switch filter {
        case .all:
            var result: [Group] = []
            // Overdue bills inside a cutoff are listed in that cutoff, so only older ones are here.
            if !engine.overdueBeforeCutoffs.isEmpty {
                result.append(Group(title: "Overdue", tint: Theme.danger, items: engine.overdueBeforeCutoffs))
            }
            if engine.paydays.isEmpty {
                result.append(Group(title: "Unpaid", items: engine.upcoming))
            } else {
                for (index, cutoff) in engine.cutoffs.prefix(4).enumerated() {
                    // Later cutoffs show each account once, so monthly bills don't repeat.
                    let group = Group(
                        title: "\(cutoffName(index)) · \(cutoff.longTitle())",
                        items: index < 2 ? engine.bills(in: cutoff) : engine.laterBills(in: cutoff),
                        awaiting: index < 2 ? engine.awaited(in: cutoff) : engine.laterAwaited(in: cutoff),
                        emptyText: index == 0 ? "Nothing left to pay this cutoff." : "No bills in this cutoff yet."
                    )
                    // The current and next cutoffs always show; later empty ones are skipped.
                    if !group.isEmpty || index < 2 { result.append(group) }
                }
            }
            return result

        case .overdue:
            return [Group(title: "Overdue", tint: Theme.danger, items: engine.overdue, emptyText: "Nothing is overdue. Nice.")]

        case .dueSoon:
            return [Group(
                title: "Due in the next \(BillFilterEngine.dueSoonDays) days",
                tint: Theme.warning,
                items: engine.dueSoon,
                emptyText: "Nothing due in the next \(BillFilterEngine.dueSoonDays) days."
            )]

        case .currentCutoff:
            return [cutoffGroup(index: 0, emptyText: "Nothing left to pay this cutoff.")]

        case .nextCutoff:
            return [cutoffGroup(index: 1, emptyText: "No bills in the next cutoff yet.")]

        case .laterCutoffs:
            let withBills = engine.laterCutoffs
                .map { Group(title: "Later · \($0.longTitle())", items: engine.laterBills(in: $0), awaiting: engine.laterAwaited(in: $0)) }
                .filter { !$0.isEmpty }
            if withBills.isEmpty {
                return [Group(title: "Later cutoffs", items: [], emptyText: "No bills in later cutoffs yet.")]
            }
            return withBills

        case .paid:
            return [Group(title: "Paid this month", tint: Theme.paid, items: engine.paidThisMonth, emptyText: "No bills paid this month yet.")]

        case .accounts:
            return []
        }
    }

    private func cutoffGroup(index: Int, emptyText: String) -> Group {
        guard engine.cutoffs.indices.contains(index) else {
            return Group(title: cutoffName(index), items: [], emptyText: emptyText)
        }
        let cutoff = engine.cutoffs[index]
        return Group(
            title: "\(cutoffName(index)) · \(cutoff.longTitle())",
            items: engine.bills(in: cutoff),
            awaiting: engine.awaited(in: cutoff),
            emptyText: emptyText
        )
    }

    // MARK: Body

    var body: some View {
        let groups = groups
        // Nothing unpaid at all: the overview has nothing to say.
        if filter == .all && engine.unpaid.isEmpty && engine.awaited.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 24) {
                if filter == .all {
                    Text("TO PAY")
                        .font(.barlow(30, relativeTo: .title))
                        .foregroundStyle(Theme.ink)
                        .padding(.bottom, -12)
                }

                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    groupView(group)
                }

                if filter == .all && engine.paydays.isEmpty {
                    note(selectedProfileID.isEmpty
                         ? "Pick a profile to group these by cutoff."
                         : "Set this profile's paydays in Settings → Cutoffs to group these by cutoff.")
                } else if filter.needsCutoffs && engine.paydays.isEmpty {
                    note("Set this profile's paydays in Settings → Cutoffs to use cutoff filters.")
                }
            }
        }
    }

    // MARK: Rows

    private func groupView(_ group: Group) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // The title and total roll to their new text when the filter changes.
                Eyebrow(group.title, color: group.tint ?? Theme.mutedInk)
                    .contentTransition(.numericText())
                Spacer()
                if !group.items.isEmpty {
                    Text(total(group.items).currencyString)
                        .font(.barlow(20, weight: .medium, relativeTo: .title3))
                        .foregroundStyle(group.tint ?? Theme.ink)
                        .contentTransition(.numericText())
                }
            }

            if group.isEmpty, let emptyText = group.emptyText {
                Text(emptyText)
                    .font(.outfit(14, relativeTo: .footnote))
                    .foregroundStyle(Theme.mutedInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, instance in
                        if index > 0 { Divider().padding(.leading, 62) }
                        row(instance)
                    }
                    ForEach(Array(group.awaiting.enumerated()), id: \.element.id) { index, item in
                        if index > 0 || !group.items.isEmpty { Divider().padding(.leading, 62) }
                        awaitedRow(item)
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
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            // Rows just fade, with no sliding.
            .transition(.opacity)
        }
    }

    /// A variable account whose bill for that month hasn't been added yet.
    private func awaitedRow(_ item: AwaitedBill) -> some View {
        NavigationLink(value: item.bill) {
            HStack(spacing: 12) {
                LogoBadge(logo: item.bill.logoData, symbol: item.bill.displayIcon, color: item.bill.displayColor, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.bill.name)
                        .font(.outfit(16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: 6) {
                        Text("~" + item.dueDate.formatted(.dateTime.month(.abbreviated).day()).uppercased())
                            .font(.outfit(12, weight: .semibold, relativeTo: .caption))
                            .foregroundStyle(Theme.mutedInk)
                        StatusChip(text: "No bill yet", foreground: Theme.mutedInk, background: FormStyle.fieldFill)
                    }
                }
                Spacer()
                Text("—")
                    .font(.barlow(22, weight: .medium, relativeTo: .title3))
                    .foregroundStyle(Theme.mutedInk)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Usually due around this date. Add the bill when it arrives.")
        .transition(.opacity)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.outfit(13, relativeTo: .footnote))
            .foregroundStyle(Theme.mutedInk)
    }
}
