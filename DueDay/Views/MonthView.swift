import SwiftUI
import SwiftData

/// A calendar of what's due, paid and overdue, with totals for each cutoff.
struct MonthView: View {
    @Query(sort: \BillInstance.dueDate) private var instances: [BillInstance]
    @Query(sort: \Profile.sortOrder) private var profiles: [Profile]
    @AppStorage(selectedProfileKey) private var selectedProfileID = ""

    @State private var month = MonthView.startOfMonth(.now)
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)

    private var calendar: Calendar { .current }
    private var strong: Color { Theme.monthStrong }

    private static func startOfMonth(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
    }

    // MARK: Data

    private var visible: [BillInstance] {
        instances.filter { $0.bill?.isArchived != true && ($0.bill?.isIn(profileID: selectedProfileID) ?? false) }
    }

    private var monthInstances: [BillInstance] {
        visible.filter { calendar.isDate($0.dueDate, equalTo: month, toGranularity: .month) }
    }

    private var instancesByDay: [Int: [BillInstance]] {
        Dictionary(grouping: monthInstances) { calendar.component(.day, from: $0.dueDate) }
    }

    private var monthTotal: Decimal {
        monthInstances.reduce(0) { $0 + ($1.amount ?? 0) }
    }

    /// Paydays only make sense for a single profile; "All" mixes different schedules.
    private var selectedProfile: Profile? {
        profiles.first { $0.id.uuidString == selectedProfileID }
    }

    private var cutoffs: [Cutoff] {
        guard let paydays = selectedProfile?.paydays else { return [] }
        return CutoffCalculator.cutoffs(paydays: paydays, in: month)
    }

    /// Days of this month that are paydays. A cutoff can end in the next month, so check the month.
    private var paydayDays: Set<Int> {
        Set(
            cutoffs.compactMap { $0.payday }
                .filter { calendar.isDate($0, equalTo: month, toGranularity: .month) }
                .map { calendar.component(.day, from: $0) }
        )
    }

    private var selectedInstances: [BillInstance] {
        visible.filter { calendar.isDate($0.dueDate, inSameDayAs: selectedDate) }
    }

    /// The month's days, preceded by empty cells so the 1st lands on the right weekday.
    private var gridDays: [Date?] {
        guard let days = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: month)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let dates: [Date?] = days.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: leading) + dates
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 20) {
                    // The bills for the selected day come first, right under the calendar.
                    dayDetail
                    cutoffSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: Bill.self) { BillDetailView(bill: $0) }
    }

    // MARK: Header and calendar

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                arrowButton("chevron.left", label: "Previous month") { shiftMonth(by: -1) }
                Spacer()
                Eyebrow(month.formatted(.dateTime.year()), color: strong)
                Spacer()
                arrowButton("chevron.right", label: "Next month") { shiftMonth(by: 1) }
            }
            .padding(.top, 8)

            Text(month.formatted(.dateTime.month(.wide)).uppercased())
                .font(.barlow(60, weight: .medium, relativeTo: .largeTitle))
                .foregroundStyle(strong)
                .padding(.bottom, -8)

            HStack {
                Text("\(monthInstances.count) \(monthInstances.count == 1 ? "BILL" : "BILLS") · \(monthTotal.pesoString)")
                    .font(.barlow(22, weight: .semibold, relativeTo: .title3))
                    .tracking(1.2)
                    .foregroundStyle(Theme.ink)
                Spacer()
                ProfileSwitcher(selectedID: $selectedProfileID)
                    .font(.outfit(14, weight: .semibold, relativeTo: .subheadline))
                    .secondaryButton(tint: strong)
            }

            DashedDivider(color: strong.opacity(0.4))

            calendarGrid

            legend
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { Theme.monthTint.padding(.top, -400) }
    }

    private func arrowButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 40, height: 40)
        }
        .secondaryButton(tint: strong)
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
    }

    private var calendarGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdaySymbols.indices, id: \.self) { index in
                    Text(weekdaySymbols[index])
                        .font(.outfit(12, weight: .semibold, relativeTo: .caption))
                        .foregroundStyle(strong)
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(gridDays.indices, id: \.self) { index in
                    if let date = gridDays[index] {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 50)
                    }
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let day = calendar.component(.day, from: date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let bills = instancesByDay[day] ?? []

        return Button { selectedDate = date } label: {
            VStack(spacing: 2) {
                Text("\(day)")
                    .font(.outfit(16, weight: .semibold, relativeTo: .body))
                HStack(spacing: 3) {
                    ForEach(bills.prefix(3)) { bill in
                        Circle().fill(dotColor(for: bill, selected: isSelected)).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
                Text(paydayDays.contains(day) ? "PAY" : " ")
                    .font(.outfit(8, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(isSelected ? Color.white : Theme.paid)
            }
            .foregroundStyle(isSelected ? Color.white : Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? strong : Theme.card.opacity(0.65))
            }
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: 12).stroke(Theme.accent, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText(for: date, bills: bills))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Green when paid, orange when overdue or due within 3 days, purple otherwise.
    private func dotColor(for instance: BillInstance, selected: Bool) -> Color {
        if selected { return .white }
        if instance.isPaid { return Theme.paid }
        switch instance.status() {
        case .overdue, .due: return Theme.warning
        default:
            let days = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: instance.dueDate)
            ).day ?? 99
            return days <= 3 ? Theme.warning : strong
        }
    }

    private func accessibilityText(for date: Date, bills: [BillInstance]) -> String {
        let day = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        return bills.isEmpty ? day : "\(day), \(bills.count) \(bills.count == 1 ? "bill" : "bills")"
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem("Paid", Theme.paid)
            legendItem("Due soon", Theme.warning)
            legendItem("Upcoming", strong)
            Text("PAY = payday")
                .font(.outfit(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(Theme.paid)
        }
    }

    private func legendItem(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.outfit(12, relativeTo: .caption)).foregroundStyle(Theme.ink)
        }
    }

    private func shiftMonth(by value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: month) else { return }
        month = next
        // Keep a day selected: today if it's in this month, otherwise the 1st.
        selectedDate = calendar.isDate(next, equalTo: .now, toGranularity: .month)
            ? calendar.startOfDay(for: .now)
            : next
    }

    // MARK: Cutoffs

    @ViewBuilder
    private var cutoffSection: some View {
        if selectedProfile == nil {
            hint("Pick a profile from the button above to see its cutoffs.")
        } else if cutoffs.isEmpty {
            hint("This profile has no paydays yet. Set them in Settings → Cutoffs.")
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(cutoffs.indices, id: \.self) { index in
                    cutoffCard(CutoffSummary(cutoff: cutoffs[index], instances: visible))
                }
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.outfit(14, relativeTo: .footnote))
            .foregroundStyle(Theme.mutedInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
    }

    private func cutoffCard(_ summary: CutoffSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(summary.cutoff.longTitle())
            Text(summary.total.pesoString)
                .font(.barlow(30, weight: .medium, relativeTo: .title))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(summary.paidCount) of \(summary.count) paid")
                .font(.outfit(13, relativeTo: .footnote))
                .foregroundStyle(Theme.mutedInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    // MARK: Selected day

    private var dayDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))

            if selectedInstances.isEmpty {
                Text("No bills due on this day.")
                    .font(.outfit(15))
                    .foregroundStyle(Theme.mutedInk)
            } else {
                ForEach(selectedInstances) { instance in
                    if let bill = instance.bill {
                        NavigationLink(value: bill) {
                            dayRow(instance, bill: bill)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func dayRow(_ instance: BillInstance, bill: Bill) -> some View {
        let chip = BillStatusText.chip(for: instance)
        return HStack(spacing: 12) {
            LogoBadge(logo: bill.logoData, symbol: bill.displayIcon, color: bill.displayColor, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(bill.name)
                    .font(.outfit(16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                StatusChip(text: chip.text, foreground: chip.foreground, background: chip.background)
            }
            Spacer()
            Text(instance.amount?.pesoString ?? "—")
                .font(.barlow(24, weight: .medium, relativeTo: .title3))
                .foregroundStyle(Theme.ink)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
