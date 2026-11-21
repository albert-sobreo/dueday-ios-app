import SwiftUI
import SwiftData
import Charts

/// A saved bill or account, focused on its current bill: amount, trend, reminders and history.
struct BillDetailView: View {
    let bill: Bill

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingEdit = false
    @State private var showingAddEntry = false
    @State private var instanceToPay: BillInstance?
    @State private var instanceToEdit: BillInstance?
    @State private var scanUpdate: ScanUpdate?
    @State private var scannedNewBill: NewScan?
    @State private var instanceToDelete: BillInstance?
    @State private var deleteWhenClosed = false
    @State private var showingAllHistory = false

    /// How many payments the history shows before "Show all".
    private static let historyPreviewCount = 6

    /// The reminders you can turn on, in days before the due date.
    private static let reminderChoices = [7, 3, 1, 0]

    /// A scan waiting to become a new bill on this account.
    private struct NewScan: Identifiable {
        let id = UUID()
        let draft: ScanDraft
    }

    /// The header follows the bill's own colour; bills without one keep the default peach.
    private var strong: Color { bill.accentHex.map(Color.strongText(hex:)) ?? Theme.detailStrong }
    private var headerTint: Color { bill.accentHex.map(Color.softTint(hex:)) ?? Theme.detailTint }
    private var isVariable: Bool { bill.amountType == .variable }

    private var sortedInstances: [BillInstance] {
        (bill.instances ?? []).sorted { $0.dueDate < $1.dueDate }
    }

    private var cutoff: Cutoff? {
        bill.profile.flatMap { CutoffCalculator.cutoff(containing: .now, paydays: $0.paydays) }
    }

    /// The nearest bill not paid yet, however far away. Reminders are sent for this one.
    private var nextUnpaid: BillInstance? {
        let unpaid = sortedInstances.filter { !$0.isPaid }
        return unpaid.first { $0.status() != .overdue } ?? unpaid.first
    }

    /// The bill to show: the nearest unpaid one if it's close, else an overdue one, else the latest
    /// paid. A fixed bill is generated months ahead, so once this month's is paid the header keeps
    /// showing it as paid, rather than jumping to next month's. With nothing paid yet, the first
    /// upcoming bill is shown.
    private var current: BillInstance? {
        let unpaid = sortedInstances.filter { !$0.isPaid }
        let upcoming = unpaid.first { $0.status() != .overdue }
        if let upcoming, upcoming.isUrgent(cutoff: cutoff) { return upcoming }
        if let overdue = unpaid.first(where: { $0.status() == .overdue }) { return overdue }
        return sortedInstances.last(where: \.isPaid) ?? upcoming
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                VStack(spacing: 16) {
                    if chartPoints.count > 0 { chartCard }
                    remindersCard
                    if !bill.paidInstances.isEmpty { historyCard }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .rowSwipeActionsContainer()
        .background(Theme.background)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Edit") {
                    if let current, !current.isPaid {
                        Button("Edit This Bill", systemImage: "pencil") { instanceToEdit = current }
                    }
                    Button("Edit Account", systemImage: "gearshape") { showingEdit = true }
                    // Only variable accounts: a fixed bill would just be generated again.
                    if isVariable, let current {
                        Divider()
                        Button("Delete This Bill", systemImage: "trash", role: .destructive) {
                            instanceToDelete = current
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete this bill?",
            isPresented: Binding(get: { instanceToDelete != nil }, set: { if !$0 { instanceToDelete = nil } }),
            titleVisibility: .visible,
            presenting: instanceToDelete
        ) { instance in
            Button("Delete Bill", role: .destructive) { delete(instance) }
        } message: { instance in
            Text("The \(instance.dueDate.formatted(.dateTime.month(.wide).day())) bill\(instance.isPaid ? " and its payment" : "") will be removed. \(bill.name) stays.")
        }
        .sheet(item: $instanceToEdit) { EditInstanceSheet(instance: $0) }
        .sheet(item: $scanUpdate) { ScanUpdateSheet(update: $0) }
        .sheet(item: $scannedNewBill) { scan in
            NavigationStack {
                ScanBillView(
                    draft: scan.draft, fixedAccount: bill,
                    onDone: { scannedNewBill = nil }, onCancel: { scannedNewBill = nil }
                )
            }
        }
        .sheet(isPresented: $showingEdit) {
            EditBillView(bill: bill) {
                // Delete after this screen is gone, so nothing reads a deleted bill.
                deleteWhenClosed = true
                dismiss()
            }
        }
        .sheet(isPresented: $showingAddEntry) { AddBillEntrySheet(bill: bill) }
        .sheet(item: $instanceToPay) { MarkPaidSheet(instance: $0) }
        .onDisappear {
            if deleteWhenClosed { modelContext.delete(bill) }
        }
    }

    /// Removes one bill (and its payments) from a variable account, and drops its reminders.
    private func delete(_ instance: BillInstance) {
        modelContext.delete(instance)
        instanceToDelete = nil
        saveAndReschedule()
    }

    /// Marks a paid bill as unpaid again, e.g. after paying it by mistake. Its reminders come back.
    private func undoPayment(_ instance: BillInstance) {
        instance.markUnpaid(in: modelContext)
        saveAndReschedule()
    }

    private func saveAndReschedule() {
        let context = modelContext
        Task {
            try? context.save()
            await ReminderScheduler.reschedule(in: context)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                if let current { statusChip(for: current) }
                StatusChip(text: bill.amountType.title.uppercased(), foreground: strong, background: Theme.card)
            }
            .padding(.top, 8)

            Text(bill.name.uppercased())
                .font(.barlow(60, weight: .medium, relativeTo: .largeTitle))
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // The due date as a pill, from cool (far away) to hot (near), like on Today.
                if let current, !current.isPaid {
                    let urgency = BillStatusText.urgency(for: current.dueDate)
                    Label(
                        current.dueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased(),
                        systemImage: "calendar"
                    )
                    .font(.outfit(12, weight: .bold, relativeTo: .caption))
                    .tracking(1.2)
                    .foregroundStyle(urgency.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(urgency.fill, in: .capsule)
                    .fixedSize()
                }
            }

            if let current {
                DashedDivider(color: strong.opacity(0.4))
                factsRow(for: current)
                amountRow(for: current)
                actions(for: current)
            } else {
                DashedDivider(color: strong.opacity(0.4))
                Text("No bill yet")
                    .font(.barlow(34, weight: .medium, relativeTo: .title))
                    .foregroundStyle(strong)
                if isVariable { newBillButtons }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            // Faded watermark behind the header, clipped to it: the uploaded logo if there is one,
            // otherwise the bill's icon.
            Color.clear.overlay(alignment: .topTrailing) {
                if let logo = bill.logoData, let image = UIImage(data: logo) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 300, height: 300)
                        .opacity(0.14)
                        .offset(x: 70, y: 40)
                } else {
                    Image(systemName: bill.displayIcon)
                        .font(.system(size: 220, weight: .bold))
                        .foregroundStyle(strong.opacity(0.08))
                        .offset(x: 40, y: 10)
                }
            }
            .clipped()
            .accessibilityHidden(true)
        }
        .background { headerTint.padding(.top, -400) }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let account = bill.maskedAccountNumber { parts.append(account) }
        parts.append(bill.category.title)
        return parts.joined(separator: " · ").uppercased()
    }

    private func statusChip(for instance: BillInstance) -> some View {
        let chip = BillStatusText.chip(for: instance)
        return StatusChip(text: chip.text, foreground: chip.foreground, background: chip.background)
    }

    private func factsRow(for instance: BillInstance) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if let period = instance.billingPeriod {
                fact("Period", period.uppercased())
                Divider().frame(height: 34)
            }
            // For an unpaid bill the due date is the pill beside the subtitle.
            if instance.isPaid {
                fact("Due", instance.dueDate.formatted(.dateTime.month(.abbreviated).day()).uppercased())
            }
            if let method = instance.latestPayment?.choice ?? bill.paymentChoice {
                if instance.isPaid || instance.billingPeriod != nil { Divider().frame(height: 34) }
                fact("Pay via", method.title.uppercased())
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(label, color: strong)
            Text(value)
                .font(.barlow(24, weight: .semibold, relativeTo: .title3))
                .foregroundStyle(strong)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func amountRow(for instance: BillInstance) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            Text(instance.amount?.pesoString ?? "—")
                .font(.barlow(54, weight: .medium, relativeTo: .largeTitle))
                .foregroundStyle(strong)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let change = bill.percentChange(for: instance), let previous = previousMonthLabel(for: instance) {
                Text("\(change >= 0 ? "+" : "−")\(abs(change).formatted(.number.precision(.fractionLength(1))))% vs \(previous)")
                    .font(.outfit(12, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(change > 0 ? Theme.danger : Theme.paid)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.card, in: .capsule)
            }
        }
    }

    private func previousMonthLabel(for instance: BillInstance) -> String? {
        bill.paidInstances.first { $0.dueDate < instance.dueDate }?
            .dueDate.formatted(.dateTime.month(.abbreviated))
    }

    @ViewBuilder
    private func actions(for instance: BillInstance) -> some View {
        if instance.isPaid {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Label("Paid", systemImage: "checkmark.circle.fill")
                        .font(.outfit(16, weight: .semibold))
                        .foregroundStyle(Theme.paid)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .padding(.vertical, 8)
                        .background(Theme.paidFill, in: .capsule)
                    Button { undoPayment(instance) } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.outfit(16, weight: .semibold))
                            .frame(minHeight: 28)
                    }
                    .secondaryButton(tint: strong)
                    .accessibilityLabel("Undo payment")
                }
                if isVariable { newBillButtons }
            }
        } else {
            HStack(spacing: 12) {
                Button { instanceToPay = instance } label: {
                    Label("Mark paid", systemImage: "checkmark")
                        .font(.outfit(16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .primaryButton()

                // Scan this month's bill to fill in its amount, due date and billing period.
                ScanMenu(onResult: { scanUpdate = ScanUpdate(instance: instance, draft: $0) }) {
                    Label("Scan bill", systemImage: "doc.viewfinder")
                        .font(.outfit(16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .secondaryButton(tint: strong)
            }
        }
    }

    /// For a variable account with no open bill: type the next bill in, or scan it.
    private var newBillButtons: some View {
        HStack(spacing: 12) {
            Button { showingAddEntry = true } label: {
                Label("Add a bill", systemImage: "plus")
                    .font(.outfit(16, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .primaryButton()

            ScanMenu(onResult: { scannedNewBill = NewScan(draft: $0) }) {
                Label("Scan bill", systemImage: "doc.viewfinder")
                    .font(.outfit(16, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .secondaryButton(tint: strong)
        }
    }

    // MARK: Chart

    private struct ChartPoint: Identifiable {
        let id: UUID
        let month: Date
        let amount: Double
        let isCurrent: Bool
    }

    /// Bills from the last 6 months, ending with the current one.
    private var chartWindow: (start: Date, end: Date)? {
        let calendar = Calendar.current
        guard let anchor = current?.dueDate,
              let anchorMonth = calendar.dateInterval(of: .month, for: anchor),
              let start = calendar.date(byAdding: .month, value: -5, to: anchorMonth.start)
        else { return nil }
        return (start, anchorMonth.end)
    }

    private var chartPoints: [ChartPoint] {
        guard let window = chartWindow else { return [] }
        return sortedInstances.compactMap { instance in
            guard let amount = instance.amount,
                  instance.dueDate >= window.start, instance.dueDate < window.end
            else { return nil }
            return ChartPoint(
                id: instance.id, month: instance.dueDate,
                amount: (amount as NSDecimalNumber).doubleValue,
                isCurrent: instance.id == current?.id
            )
        }
    }

    private var averageAmount: Decimal {
        let amounts = chartPoints.map(\.amount)
        guard !amounts.isEmpty else { return 0 }
        return Decimal(amounts.reduce(0, +) / Double(amounts.count))
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow("Last 6 months")
                Spacer()
                Text("avg \(averageAmount.formatted(.currency(code: CurrencySetting.code).locale(CurrencySetting.locale(for: CurrencySetting.code)).precision(.fractionLength(0))))")
                    .font(.outfit(13))
                    .foregroundStyle(Theme.mutedInk)
            }

            Chart(chartPoints) { point in
                BarMark(x: .value("Month", point.month, unit: .month), y: .value("Amount", point.amount))
                    .foregroundStyle(point.isCurrent ? Theme.accent : Theme.chartBar)
                    .cornerRadius(8)
                    .annotation(position: .top, spacing: 4) {
                        Text(compact(point.amount))
                            .font(.outfit(11, weight: point.isCurrent ? .bold : .regular, relativeTo: .caption2))
                            .foregroundStyle(point.isCurrent ? Theme.accent : Theme.mutedInk)
                    }
            }
            .chartYAxis(.hidden)
            .chartXScale(domain: (chartWindow?.start ?? .now)...(chartWindow?.end ?? .now))
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), anchor: .top)
                        .font(.outfit(11, weight: .semibold, relativeTo: .caption2))
                }
            }
            .frame(height: 170)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// 2845 → "2.8k", 480 → "480"
    private func compact(_ value: Double) -> String {
        value >= 1000
            ? (value / 1000).formatted(.number.precision(.fractionLength(1))) + "k"
            : value.formatted(.number.precision(.fractionLength(0)))
    }

    // MARK: Reminders

    private var remindersCard: some View {
        VStack(spacing: 0) {
            ForEach(Self.reminderChoices, id: \.self) { days in
                if days != Self.reminderChoices.first { Divider().padding(.vertical, 10) }
                reminderRow(
                    title: reminderTitle(daysBefore: days),
                    subtitle: reminderSubtitle(daysBefore: days),
                    isOn: reminderBinding(days)
                )
            }
        }
        .cardStyle()
    }

    private func reminderTitle(daysBefore days: Int) -> String {
        switch days {
        case 0: String(localized: "On due day")
        case 1: String(localized: "The day before")
        case 7: String(localized: "A week before")
        default: String(inflecting: "^[\(days) day](inflect: true) before")
        }
    }

    private func reminderRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.outfit(16, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.outfit(13)).foregroundStyle(Theme.mutedInk)
            }
        }
        .tint(Theme.toggleOn)
    }

    /// "Mon, Nov 2 · 9:00 AM" for the next unpaid bill, or a hint when there's no bill yet.
    private func reminderSubtitle(daysBefore: Int) -> String {
        guard let due = nextUnpaid?.dueDate else { return "Sent once a bill is added" }
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -daysBefore, to: due) ?? due
        // The reminder time is set in Settings (9:00 AM by default).
        let at9 = ReminderSettings.date(on: day, calendar: calendar)
        return at9.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
            .replacingOccurrences(of: " at ", with: " · ")
    }

    private func reminderBinding(_ days: Int) -> Binding<Bool> {
        Binding(
            get: { bill.reminderOffsets.contains(days) },
            set: { isOn in
                var offsets = Set(bill.reminderOffsets)
                if isOn { offsets.insert(days) } else { offsets.remove(days) }
                bill.reminderOffsets = offsets.sorted(by: >)
                // Otherwise the change only takes effect the next time reminders are rebuilt.
                saveAndReschedule()
            }
        )
    }

    // MARK: History

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Payment history")
                .font(.outfit(18, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(Theme.ink)

            let paid = bill.paidInstances
            ForEach(showingAllHistory ? paid : Array(paid.prefix(Self.historyPreviewCount))) { instance in
                historyRow(instance)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if isVariable {
                            Button("Delete", systemImage: "trash", role: .destructive) { instanceToDelete = instance }
                        }
                        Button("Undo", systemImage: "arrow.uturn.backward") { undoPayment(instance) }
                            .tint(Theme.warning)
                    }
                    .contextMenu {
                        Button("Undo Payment", systemImage: "arrow.uturn.backward") { undoPayment(instance) }
                        if isVariable {
                            Button("Delete This Bill", systemImage: "trash", role: .destructive) {
                                instanceToDelete = instance
                            }
                        }
                    }
                    .accessibilityActions {
                        Button("Undo payment") { undoPayment(instance) }
                        if isVariable {
                            Button("Delete this bill") { instanceToDelete = instance }
                        }
                    }
            }

            if paid.count > Self.historyPreviewCount {
                Button {
                    withAnimation(.snappy) { showingAllHistory.toggle() }
                } label: {
                    Text(showingAllHistory ? "Show less" : "Show all \(paid.count)")
                        .font(.outfit(15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .secondaryButton(tint: strong)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func historyRow(_ instance: BillInstance) -> some View {
        HStack(alignment: .center, spacing: 14) {
            // Sized so the capitals are as tall as the amount and the line under it together.
            // The fixed height keeps the row from growing to the font's full line height.
            Text(instance.dueDate.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.barlow(42, weight: .semibold, relativeTo: .title))
                .foregroundStyle(strong)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 66, height: 36, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(instance.amount?.pesoString ?? "—")
                    .font(.outfit(16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(paidDetail(instance))
                    .font(.outfit(13))
                    .foregroundStyle(Theme.mutedInk)
            }
            Spacer()
            let late = instance.wasPaidLate()
            StatusChip(
                text: late ? String(localized: "Late") : String(localized: "Paid"),
                foreground: late ? Theme.warning : Theme.paid,
                background: late ? Theme.warningFill : Theme.paidFill
            )
        }
        .accessibilityElement(children: .combine)
        .contentShape(.rect)
    }

    private func paidDetail(_ instance: BillInstance) -> String {
        var parts: [String] = []
        if let date = instance.latestPayment?.paidDate {
            parts.append("Paid \(date.formatted(.dateTime.month(.abbreviated).day()))")
        }
        if let method = instance.latestPayment?.choice { parts.append(method.title) }
        return parts.joined(separator: " · ")
    }
}

/// Status chip wording shared by the Today hero and the bill detail screen.
enum BillStatusText {
    /// Due-date pill colours by how soon the bill is due: blue when far, through teal and amber to
    /// orange and red.
    static func urgency(for dueDate: Date, now: Date = .now) -> (fill: Color, text: Color) {
        switch daysUntil(dueDate, now: now) {
        case ..<1: Theme.urgencyNow        // due today or overdue
        case 1...3: Theme.urgencySoon      // very soon
        case 4...7: Theme.urgencyWeek      // this week
        case 8...14: Theme.urgencyFortnight // a week or two out
        default: Theme.urgencyLater        // far away
        }
    }

    /// Whole days from today to the due date; negative once it's passed.
    static func daysUntil(_ dueDate: Date, now: Date = .now) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: dueDate)
        ).day ?? 0
    }

    /// The status chip: red when overdue, amber when due today or within 3 days, and a calm blue
    /// further out, so a bill weeks away doesn't look urgent. The wording is localizable, with the
    /// day count inflected ("1 day", "2 days"); `StatusChip` uppercases it.
    static func chip(for instance: BillInstance, now: Date = .now) -> (text: String, foreground: Color, background: Color) {
        switch instance.status(now: now) {
        case .paid:
            return (String(localized: "Paid"), Theme.paid, Theme.paidFill)
        case .due:
            return (String(localized: "Due today"), Theme.warning, Theme.warningFill)
        case .overdue:
            let days = instance.daysOverdue(now: now)
            return (String(inflecting: "Overdue ^[\(days) day](inflect: true)"), Theme.danger, Theme.dangerFill)
        case .upcoming:
            let days = daysUntil(instance.dueDate, now: now)
            let text = String(inflecting: "Due in ^[\(days) day](inflect: true)")
            return days <= 3 ? (text, Theme.warning, Theme.warningFill) : (text, Theme.info, Theme.infoFill)
        }
    }
}
