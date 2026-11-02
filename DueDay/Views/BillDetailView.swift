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

    /// The bill to show: the nearest unpaid one, else the oldest overdue, else the latest paid.
    private var current: BillInstance? {
        let unpaid = sortedInstances.filter { !$0.isPaid }
        return unpaid.first { $0.status() != .overdue } ?? unpaid.first ?? sortedInstances.last
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
                Label("Paid", systemImage: "checkmark.circle.fill")
                    .font(.outfit(16, weight: .semibold))
                    .foregroundStyle(Theme.paid)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .padding(.vertical, 8)
                    .background(Theme.paidFill, in: .capsule)
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
            reminderRow(
                title: "3 days before",
                subtitle: reminderSubtitle(daysBefore: 3),
                isOn: reminderBinding(3)
            )
            Divider().padding(.vertical, 10)
            reminderRow(
                title: "On due day",
                subtitle: reminderSubtitle(daysBefore: 0),
                isOn: reminderBinding(0)
            )
            Divider().padding(.vertical, 10)
            reminderRow(
                title: "Lock screen on due day",
                subtitle: "Stays until marked paid",
                isOn: Binding(get: { bill.liveActivityEnabled }, set: { bill.liveActivityEnabled = $0 })
            )
        }
        .cardStyle()
    }

    private func reminderRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.outfit(16, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.outfit(13)).foregroundStyle(Theme.mutedInk)
            }
        }
        .tint(Theme.paid)
    }

    /// "Mon, Nov 2 · 9:00 AM" for the current bill, or a hint when there's no bill yet.
    private func reminderSubtitle(daysBefore: Int) -> String {
        guard let due = current?.dueDate, current?.isPaid == false else { return "Sent once a bill is added" }
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
            }
        )
    }

    // MARK: History

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Payment history")
                .font(.outfit(18, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(Theme.ink)

            ForEach(bill.paidInstances.prefix(6)) { instance in
                HStack(alignment: .top, spacing: 14) {
                    Text(instance.dueDate.formatted(.dateTime.month(.abbreviated)).uppercased())
                        .font(.barlow(22, weight: .semibold, relativeTo: .title3))
                        .foregroundStyle(strong)
                        .frame(width: 48, alignment: .leading)
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
                        text: late ? "LATE" : "PAID",
                        foreground: late ? Theme.warning : Theme.paid,
                        background: late ? Theme.warningFill : Theme.paidFill
                    )
                }
                .accessibilityElement(children: .combine)
                .contentShape(.rect)
                .contextMenu {
                    if isVariable {
                        Button("Delete This Bill", systemImage: "trash", role: .destructive) {
                            instanceToDelete = instance
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
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
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: dueDate)
        ).day ?? 0
        // Each band has a light-mode and a dark-mode version: in dark mode the fill is lighter and
        // the text dark, so it stays readable.
        switch days {
        case ..<1:    // due today or overdue
            return (Color(light: 0xD32F2F, dark: 0xFF8A80), Color(light: 0xFFFFFF, dark: 0x3B0A07))
        case 1...3:   // very soon
            return (Color(light: 0xE8590C, dark: 0xFFA066), Color(light: 0xFFFFFF, dark: 0x3A1500))
        case 4...7:   // this week
            return (Color(light: 0xF59F00, dark: 0xFFD166), Color(light: 0x3A2600, dark: 0x3A2600))
        case 8...14:  // a week or two out
            return (Color(light: 0x00897B, dark: 0x5FD6C8), Color(light: 0xFFFFFF, dark: 0x03302B))
        default:      // far away
            return (Color(light: 0x1E88E5, dark: 0x8EC5FF), Color(light: 0xFFFFFF, dark: 0x06243F))
        }
    }

    static func chip(for instance: BillInstance, now: Date = .now) -> (text: String, foreground: Color, background: Color) {
        switch instance.status(now: now) {
        case .paid:
            return ("PAID", Theme.paid, Theme.paidFill)
        case .due:
            return ("DUE TODAY", Theme.warning, Theme.warningFill)
        case .overdue:
            let days = instance.daysOverdue(now: now)
            return ("OVERDUE \(days) \(days == 1 ? "DAY" : "DAYS")", Theme.danger, Theme.dangerFill)
        case .upcoming:
            let calendar = Calendar.current
            let days = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: instance.dueDate)
            ).day ?? 0
            return ("DUE IN \(days) \(days == 1 ? "DAY" : "DAYS")", Theme.warning, Theme.warningFill)
        }
    }
}
