import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BillInstance.dueDate) private var instances: [BillInstance]
    @Query(sort: \Profile.sortOrder) private var profiles: [Profile]

    @AppStorage(selectedProfileKey) private var selectedProfileID = ""
    @State private var instanceToPay: BillInstance?
    @State private var billToView: Bill?
    @State private var instanceToDelete: BillInstance?
    @State private var showingNewBill = false
    @State private var showingCustomBill = false
    @State private var quickPreset: BillPreset?
    @State private var scannedBill: QuickScan?

    /// A scan from the quick start, waiting to be checked.
    private struct QuickScan: Identifiable {
        let id = UUID()
        let draft: ScanDraft
    }

    private var now: Date { .now }

    // MARK: Data

    /// Instances of active bills in the selected profile.
    private var visible: [BillInstance] {
        instances.filter { $0.bill?.isArchived != true && ($0.bill?.isIn(profileID: selectedProfileID) ?? false) }
    }

    private var unpaid: [BillInstance] { visible.filter { !$0.isPaid } }

    /// The most urgent bill: the oldest overdue one if there is any, otherwise the nearest one due.
    /// `unpaid` is sorted by due date, so the first urgent item is the right one either way. A fixed
    /// bill that's still weeks away isn't urgent (see `isUrgent`), so after paying this month's,
    /// next month's doesn't take over the hero. Later ones are listed below instead.
    private var hero: BillInstance? {
        unpaid.first { $0.isUrgent(cutoff: currentCutoff, now: now) }
    }

    /// Paydays only make sense for a single profile; "All" mixes different schedules.
    private var selectedProfile: Profile? {
        profiles.first { $0.id.uuidString == selectedProfileID }
    }

    private var currentCutoff: Cutoff? {
        guard let paydays = selectedProfile?.paydays else { return nil }
        return CutoffCalculator.cutoff(containing: now, paydays: paydays)
    }

    private var cutoffSummary: CutoffSummary? {
        currentCutoff.map { CutoffSummary(cutoff: $0, instances: visible) }
    }

    /// What Home lists: every overdue bill, plus each bill's next one coming due in the next 30 days.
    /// The app generates a few months of repeating bills ahead, but only the next one of each is shown,
    /// so Home doesn't fill up with future months. The Month and Bills screens show the rest.
    private var homeUnpaid: [BillInstance] {
        let horizon = Calendar.current.date(byAdding: .day, value: 30, to: Calendar.current.startOfDay(for: now)) ?? now
        var billsAlreadyShown = Set<UUID>()
        // The hero stands for its bill, so that bill's later months aren't repeated.
        if let hero, hero.status() != .overdue, let id = hero.bill?.id { billsAlreadyShown.insert(id) }

        // `unpaid` is sorted by due date, so the first one found for a bill is its next one.
        return unpaid.filter { instance in
            if instance.status() == .overdue { return true }
            guard instance.dueDate <= horizon else { return false }
            if instance.id == hero?.id { return true }
            guard let id = instance.bill?.id else { return true }
            return billsAlreadyShown.insert(id).inserted
        }
    }

    /// Other unpaid bills due in the same cutoff as the hero. Without paydays, the next few bills due.
    private var alsoThisCutoff: [BillInstance] {
        // Only shown under the hero. Without one, these bills go in the upcoming list instead.
        guard hero != nil else { return [] }
        let others = homeUnpaid.filter { $0.id != hero?.id && $0.status() != .overdue }
        if let cutoff = currentCutoff {
            return Array(others.filter { cutoff.contains($0.dueDate) }.prefix(3))
        }
        return Array(others.prefix(3))
    }

    /// Overdue bills first, then everything else not already shown above.
    private var upcoming: [BillInstance] {
        let shown = Set(([hero].compactMap { $0 } + alsoThisCutoff).map(\.id))
        return homeUnpaid.filter { !shown.contains($0.id) }
            .sorted { lhs, rhs in
                let l = lhs.status() == .overdue, r = rhs.status() == .overdue
                return l != r ? l : lhs.dueDate < rhs.dueDate
            }
    }

    private var recentlyPaid: [BillInstance] {
        Array(visible.filter(\.isPaid).sorted {
            ($0.latestPayment?.paidDate ?? $0.dueDate) > ($1.latestPayment?.paidDate ?? $1.dueDate)
        }.prefix(5))
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let hero {
                    HeroSection(
                        instance: hero,
                        others: alsoThisCutoff,
                        hasCutoff: currentCutoff != nil,
                        onPay: { pay(hero) },
                        onView: { billToView = hero.bill },
                        onViewOther: { billToView = $0.bill },
                        onDelete: { instanceToDelete = hero }
                    )
                } else {
                    EmptyHero(hasBills: !visible.isEmpty)
                }

                VStack(alignment: .leading, spacing: 24) {
                    // A fresh start: the quickest ways to add a first bill.
                    if visible.isEmpty {
                        QuickStartSection(
                            onPreset: { quickPreset = $0 },
                            onCustom: { showingCustomBill = true },
                            onScan: { scannedBill = QuickScan(draft: $0) },
                            onBrowse: { showingNewBill = true }
                        )
                    }
                    if let summary = cutoffSummary, summary.count > 0 {
                        CutoffCard(summary: summary)
                    }
                    if !upcoming.isEmpty {
                        UpcomingSection(
                            instances: upcoming,
                            cutoff: currentCutoff,
                            showProfile: selectedProfileID.isEmpty,
                            onView: { billToView = $0.bill },
                            onPay: pay,
                            onDelete: { instanceToDelete = $0 }
                        )
                    }
                    if !recentlyPaid.isEmpty {
                        RecentlyPaidCard(
                            instances: recentlyPaid,
                            onView: { billToView = $0.bill },
                            onUndo: { $0.markUnpaid(in: modelContext) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .rowSwipeActionsContainer()
        .background(Theme.background)
        .ownsTopOfScreen()
        .overlay(alignment: .topTrailing) {
            // The profile switcher lives in the header now that the toolbar is gone.
            ProfileSwitcher(selectedID: $selectedProfileID)
                .font(.outfit(14, weight: .semibold, relativeTo: .subheadline))
                .secondaryButton(tint: Theme.todayStrong)
                .padding(.trailing, 20)
                .padding(.top, 4)
        }
        .confirmationDialog(
            "Delete this bill?",
            isPresented: Binding(get: { instanceToDelete != nil }, set: { if !$0 { instanceToDelete = nil } }),
            titleVisibility: .visible,
            presenting: instanceToDelete
        ) { instance in
            Button("Delete \(instance.bill?.name ?? "Bill")", role: .destructive) {
                modelContext.delete(instance)
                instanceToDelete = nil
            }
        } message: { instance in
            Text("Only the \(instance.dueDate.formatted(.dateTime.month(.wide))) bill is removed. The account and its other bills stay.")
        }
        .sheet(item: $instanceToPay) { MarkPaidSheet(instance: $0) }
        .navigationDestination(item: $billToView) { BillDetailView(bill: $0) }
        .sheet(isPresented: $showingNewBill) {
            AddBillView(defaultProfileID: selectedProfileID)
        }
        .sheet(item: $quickPreset) { preset in
            NavigationStack {
                NewAccountView(
                    preset: preset, defaultProfileID: selectedProfileID,
                    onDone: { quickPreset = nil }, onCancel: { quickPreset = nil }
                )
            }
        }
        .sheet(isPresented: $showingCustomBill) {
            NavigationStack {
                NewAccountView(
                    preset: nil, defaultProfileID: selectedProfileID,
                    onDone: { showingCustomBill = false }, onCancel: { showingCustomBill = false }
                )
            }
        }
        .sheet(item: $scannedBill) { scan in
            NavigationStack {
                ScanBillView(
                    draft: scan.draft, defaultProfileID: selectedProfileID,
                    onDone: { scannedBill = nil }, onCancel: { scannedBill = nil }
                )
            }
        }
    }

    /// Always opens the Mark as paid sheet, so you can confirm the amount, date and payment method.
    private func pay(_ instance: BillInstance) {
        instanceToPay = instance
    }
}

#if DEBUG
#Preview("Today") {
    let container = try! ModelContainer(
        for: Profile.self, CustomProvider.self, CustomPaymentMethod.self, Bill.self, BillInstance.self, Payment.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    FontRegistrar.registerAll()

    SampleData.populate(in: context)

    return NavigationStack { TodayView() }
        .modelContainer(container)
}
#endif

// MARK: - Hero

private struct HeroSection: View {
    let instance: BillInstance
    let others: [BillInstance]
    let hasCutoff: Bool
    let onPay: () -> Void
    let onView: () -> Void
    /// Opens one of the other bills listed under "Also this cutoff".
    let onViewOther: (BillInstance) -> Void
    let onDelete: () -> Void

    private var bill: Bill? { instance.bill }
    /// The hero follows the bill's own colour; bills without one keep the default blue.
    private var strong: Color { bill?.accentHex.map(Color.strongText(hex:)) ?? Theme.todayStrong }
    private var headerTint: Color { bill?.accentHex.map(Color.softTint(hex:)) ?? Theme.todayTint }

    private var chip: (text: String, foreground: Color, background: Color) {
        BillStatusText.chip(for: instance)
    }

    /// "MON · NOV 2"
    private var todayLabel: String {
        let weekday = Date.now.formatted(.dateTime.weekday(.abbreviated))
        let monthDay = Date.now.formatted(.dateTime.month(.abbreviated).day())
        return "\(weekday) · \(monthDay)"
    }

    /// "ELECTRICITY", or "INTERNET & PHONE · 7 OF 24" for an installment.
    private var subtitle: String {
        var parts = [bill?.category.title ?? ""]
        if let label = instance.installmentLabel { parts.append(label) }
        return parts.joined(separator: " · ").uppercased()
    }

    /// Pill colours by how soon the bill is due: blue when far, through teal and amber to orange and red.
    private var urgency: (fill: Color, text: Color) {
        BillStatusText.urgency(for: instance.dueDate)
    }

    /// "THU, NOV 5"
    private var dueDateLabel: String {
        instance.dueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(todayLabel, color: strong)
                .padding(.top, 8)

            StatusChip(text: chip.text, foreground: chip.foreground, background: chip.background)

            Text((bill?.name ?? "Bill").uppercased())
                .font(.barlow(54, weight: .medium, relativeTo: .largeTitle))
                .foregroundStyle(strong)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                // Pull the subtitle closer to the name.
                .padding(.bottom, -8)

            HStack(spacing: 10) {
                Text(subtitle)
                    .font(.barlow(20, weight: .semibold, relativeTo: .title3))
                    .tracking(1.5)
                    .foregroundStyle(Theme.ink)

                // The due date as a solid pill whose colour runs from cool (far away) to hot (near).
                Label(dueDateLabel, systemImage: "calendar")
                    .font(.outfit(12, weight: .bold, relativeTo: .caption))
                    .tracking(1.2)
                    .foregroundStyle(urgency.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(urgency.fill, in: .capsule)
                    .accessibilityLabel("Due \(dueDateLabel)")
            }

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                if let amount = instance.amount {
                    Text(amount.pesoString)
                        .font(.barlow(52, weight: .medium, relativeTo: .largeTitle))
                        .foregroundStyle(strong)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Eyebrow("Amount\ndue", color: strong)
                } else {
                    Text("Enter amount")
                        .font(.barlow(30, weight: .medium, relativeTo: .title))
                        .foregroundStyle(strong.opacity(0.7))
                }
            }

            HStack(spacing: 12) {
                Button(action: onPay) {
                    Label("Mark paid", systemImage: "checkmark")
                        .font(.outfit(16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .primaryButton()

                Button(action: onView) {
                    Text("View bill")
                        .font(.outfit(16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .secondaryButton(tint: strong)

                // The same actions as the long-press menu, so they can be found without it.
                Menu {
                    Button("Delete this bill", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.outfit(16, weight: .semibold))
                        .frame(minWidth: 20, minHeight: 28)
                }
                .secondaryButton(tint: strong)
                .accessibilityLabel("More")
            }

            DashedDivider(color: strong.opacity(0.4)).padding(.top, 6)
            Eyebrow(hasCutoff ? "Also this cutoff" : "Also coming up", color: strong)
            if others.isEmpty {
                Text(hasCutoff ? "Nothing else due this cutoff." : "Nothing else coming up.")
                    .font(.outfit(14, relativeTo: .footnote))
                    .foregroundStyle(Theme.ink.opacity(0.7))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(others) { other in
                        Button { onViewOther(other) } label: {
                            AlsoRow(instance: other, labelColor: strong)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the bill")
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            // Large faded day number behind the hero, clipped so it never spills below the tint.
            Color.clear.overlay(alignment: .topTrailing) {
                Text(instance.dueDate.formatted(.dateTime.day(.twoDigits)))
                    .font(.barlow(340, relativeTo: .largeTitle))
                    .foregroundStyle(strong.opacity(0.08))
                    .offset(x: 40, y: -50)
            }
            .clipped()
            .accessibilityHidden(true)
        }
        .contextMenu {
            Button("Delete this bill", systemImage: "trash", role: .destructive, action: onDelete)
        }
        // Extend the tint upward so it fills the area behind the status bar and toolbar.
        .background { headerTint.padding(.top, -400) }
    }
}

private struct AlsoRow: View {
    let instance: BillInstance
    /// Colour for the month and weekday: the hero's, so they sit well on its tint.
    let labelColor: Color

    /// The date takes this bill's own colour.
    private var dayColor: Color {
        instance.bill?.accentHex.map(Color.strongText(hex:)) ?? Theme.todayStrong
    }

    var body: some View {
        // Centered so the day number sits in the middle of the two text lines beside it.
        HStack(alignment: .center, spacing: 10) {
            Text(instance.dueDate.formatted(.dateTime.day(.twoDigits)))
                .font(.barlow(34, weight: .regular, relativeTo: .title))
                .foregroundStyle(dayColor)
                .frame(width: 30, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(instance.dueDate.formatted(.dateTime.month(.abbreviated)).uppercased())
                Text(instance.dueDate.formatted(.dateTime.weekday(.abbreviated)).uppercased())
            }
            .font(.outfit(10, weight: .semibold, relativeTo: .caption2))
            .tracking(1)
            .foregroundStyle(labelColor)
            .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(instance.bill?.name ?? "Bill")
                    .font(.outfit(17, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.outfit(13, relativeTo: .footnote))
                    .foregroundStyle(Theme.ink.opacity(0.75))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        parts.append(instance.amount?.pesoString ?? "Amount varies")
        if let label = instance.installmentLabel { parts.append(label) }
        if let method = instance.bill?.paymentChoice { parts.append(method.title) }
        return parts.joined(separator: " · ")
    }
}

private struct EmptyHero: View {
    let hasBills: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(hasBills ? "You're all set" : "Let's get started", color: Theme.todayStrong)
                .padding(.top, 8)
            Text(hasBills ? "ALL CAUGHT UP" : "WELCOME TO DUEDAY")
                .font(.barlow(54, weight: .medium, relativeTo: .largeTitle))
                .foregroundStyle(Theme.todayStrong)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text(hasBills ? "Nothing is due soon." : "Add your first bill and we'll remind you before it's due. Everything stays on your phone.")
                .font(.outfit(16))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            // A faded icon behind the text, like the day number on a real bill.
            Color.clear.overlay(alignment: .topTrailing) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 180, weight: .bold))
                    .foregroundStyle(Theme.todayStrong.opacity(0.08))
                    .offset(x: 30, y: 10)
            }
            .clipped()
            .accessibilityHidden(true)
        }
        .background { Theme.todayTint.padding(.top, -400) }
    }
}

// MARK: - Quick start

/// What Home shows below the welcome until there's a first bill: scan or import one, pick a common
/// biller, or start from scratch.
private struct QuickStartSection: View {
    let onPreset: (BillPreset) -> Void
    let onCustom: () -> Void
    let onScan: (ScanDraft) -> Void
    let onBrowse: () -> Void

    /// Common billers to start from; falls back to the first few if the list changes.
    private var popular: [BillPreset] {
        let wanted = ["meralco", "maynilad", "pldt", "converge", "globe", "rent"]
        let found = wanted.compactMap { id in PresetStore.all.first { $0.id == id } }
        return found.count >= 4 ? found : Array(PresetStore.all.prefix(6))
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ADD YOUR FIRST BILL")
                .font(.barlow(30, relativeTo: .title))
                .foregroundStyle(Theme.ink)

            ScanTiles(onResult: onScan)

            Eyebrow("Or pick a biller")
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(popular) { preset in
                    Button { onPreset(preset) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: preset.icon)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(preset.color)
                                .frame(width: 28)
                            Text(preset.name)
                                .font(.outfit(15, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .glassSurface(cornerRadius: 16)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 12) {
                Button(action: onCustom) {
                    Label("Custom bill", systemImage: "square.and.pencil")
                        .font(.outfit(16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .primaryButton()

                Button(action: onBrowse) {
                    Label("All billers", systemImage: "list.bullet")
                        .font(.outfit(16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .secondaryButton(tint: Theme.todayStrong)
            }
        }
    }
}

// MARK: - Cutoff

private struct CutoffCard: View {
    let summary: CutoffSummary

    private var title: String {
        "Cutoff · \(summary.cutoff.longTitle())"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(title)
                Spacer()
                if let payday = summary.cutoff.payday {
                    Text("PAYDAY \(payday.formatted(.dateTime.month(.abbreviated).day()).uppercased())")
                        .font(.outfit(12, weight: .bold, relativeTo: .caption))
                        .tracking(1.2)
                        .foregroundStyle(Theme.paid)
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(summary.leftToCover.pesoString)
                    .font(.barlow(44, weight: .medium, relativeTo: .largeTitle))
                    .foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("left to cover")
                    .font(.outfit(14, relativeTo: .footnote))
                    .foregroundStyle(Theme.mutedInk)
            }
            progressBar
            Text("\(summary.paidCount) of \(summary.count) bills paid · \(summary.paidTotal.pesoString) so far")
                .font(.outfit(13, relativeTo: .footnote))
                .foregroundStyle(Theme.mutedInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    /// One segment per bill, filled green once paid. With more than 10 bills the segments get too
    /// thin, so it becomes one bar filled by the share that's paid.
    @ViewBuilder
    private var progressBar: some View {
        if summary.count <= 10 {
            HStack(spacing: 6) {
                ForEach(0..<summary.count, id: \.self) { index in
                    Capsule()
                        .fill(index < summary.paidCount ? Theme.paid : Theme.track)
                        .frame(height: 6)
                }
            }
        } else {
            Capsule()
                .fill(Theme.track)
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Theme.paid)
                            .frame(width: proxy.size.width * CGFloat(summary.paidCount) / CGFloat(summary.count))
                    }
                }
        }
    }
}

// MARK: - Upcoming carousel

private struct UpcomingSection: View {
    let instances: [BillInstance]
    let cutoff: Cutoff?
    let showProfile: Bool
    let onView: (BillInstance) -> Void
    let onPay: (BillInstance) -> Void
    let onDelete: (BillInstance) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("UPCOMING")
                .font(.barlow(30, relativeTo: .title))
                .foregroundStyle(Theme.ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(instances) { instance in
                        UpcomingCard(
                            instance: instance,
                            cutoff: cutoff,
                            showProfile: showProfile,
                            onView: { onView(instance) },
                            onPay: { onPay(instance) },
                            onDelete: { onDelete(instance) }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
            // Don't clip the cards' glass edges and shadows at the scroll view's bounds.
            .scrollClipDisabled()
            // Let the carousel run to the screen edges.
            .padding(.horizontal, -20)
        }
    }
}

private struct UpcomingCard: View {
    let instance: BillInstance
    let cutoff: Cutoff?
    let showProfile: Bool
    let onView: () -> Void
    let onPay: () -> Void
    let onDelete: () -> Void

    private var bill: Bill? { instance.bill }
    private var tint: Color { bill?.displayColor ?? Theme.info }
    private var isOverdue: Bool { instance.status() == .overdue }

    var body: some View {
        // Tapping the card opens the bill. The pay button sits on top rather than inside it, so the
        // two taps don't fight.
        Button(action: onView) {
            content.contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the bill")
        .overlay(alignment: .topTrailing) {
            Button(action: onPay) {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonBorderShape(.circle)
            .secondaryButton(tint: tint)
            .padding(10)
            .accessibilityLabel("Mark \(bill?.name ?? "bill") as paid")
        }
        .contextMenu {
            Button("Mark as paid", systemImage: "checkmark.circle", action: onPay)
            Button("Delete this bill", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isOverdue {
                StatusChip(text: String(localized: "Overdue"), foreground: Theme.danger, background: Theme.dangerFill)
            } else if let cutoff {
                StatusChip(
                    text: cutoff.contains(instance.dueDate) ? String(localized: "This cutoff") : String(localized: "Next cutoff"),
                    foreground: Theme.info, background: Theme.infoFill
                )
            } else {
                let chip = BillStatusText.chip(for: instance)
                StatusChip(text: chip.text, foreground: chip.foreground, background: chip.background)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text((bill?.name ?? "Bill").uppercased())
                    .font(.barlow(30, relativeTo: .title))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(
                    [(showProfile ? bill?.profile?.name : bill?.category.title), instance.installmentLabel]
                        .compactMap { $0 }.joined(separator: " · ").uppercased()
                )
                    .font(.outfit(12, weight: .medium, relativeTo: .caption))
                    .tracking(1.4)
                    .foregroundStyle(tint.opacity(0.85))
            }

            HStack(alignment: .top, spacing: 14) {
                column("Due", instance.dueDate.formatted(.dateTime.month(.abbreviated).day()).uppercased())
                Divider().frame(height: 34)
                column("Amount", instance.amount.map { $0.pesoString } ?? "—")
                if isOverdue {
                    Divider().frame(height: 34)
                    column("Late", "\(instance.daysOverdue())D", color: Theme.danger)
                }
            }
        }
        .frame(width: 270, alignment: .leading)
        .cardStyle()
    }

    private func column(_ label: String, _ value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(label)
            Text(value)
                .font(.barlow(24, weight: .semibold, relativeTo: .title3))
                .foregroundStyle(color ?? tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Recently paid

private struct RecentlyPaidCard: View {
    let instances: [BillInstance]
    let onView: (BillInstance) -> Void
    let onUndo: (BillInstance) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recently paid")
                .font(.outfit(18, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(Theme.ink)

            ForEach(instances) { instance in
                Button { onView(instance) } label: {
                    row(instance).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the bill. Swipe left to undo the payment.")
                .swipeActions(edge: .trailing) {
                    Button("Undo", systemImage: "arrow.uturn.backward") { onUndo(instance) }
                        .tint(Theme.warning)
                }
                .contextMenu {
                    Button("Undo payment", systemImage: "arrow.uturn.backward") { onUndo(instance) }
                }
                .accessibilityActions {
                    Button("Undo payment") { onUndo(instance) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func row(_ instance: BillInstance) -> some View {
        let late = instance.wasPaidLate()
        return HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(instance.bill?.name ?? "Bill")
                    .font(.outfit(16, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.ink)
                Text(detail(instance))
                    .font(.outfit(13, relativeTo: .footnote))
                    .foregroundStyle(Theme.mutedInk)
            }
            Spacer()
            StatusChip(
                text: late ? String(localized: "Late") : String(localized: "Paid"),
                foreground: late ? Theme.warning : Theme.paid,
                background: late ? Theme.warningFill : Theme.paidFill
            )
        }
        .accessibilityElement(children: .combine)
    }

    private func detail(_ instance: BillInstance) -> String {
        var parts: [String] = []
        if let amount = instance.amount { parts.append(amount.pesoString) }
        if let method = instance.latestPayment?.choice { parts.append(method.title) }
        if let date = instance.latestPayment?.paidDate {
            parts.append(date.formatted(.dateTime.month(.abbreviated).day()))
        }
        return parts.joined(separator: " · ")
    }
}
