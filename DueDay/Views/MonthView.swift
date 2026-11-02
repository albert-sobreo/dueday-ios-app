import SwiftUI
import SwiftData

/// A calendar of what's due, paid and overdue, with totals for each cutoff.
struct MonthView: View {
    @Query(sort: \BillInstance.dueDate) private var instances: [BillInstance]
    @Query(sort: \Profile.sortOrder) private var profiles: [Profile]
    @AppStorage(selectedProfileKey) private var selectedProfileID = ""

    /// True while swiping and for a moment after, so lifting your finger doesn't tap the day under it.
    @State private var ignoreDayTaps = false
    @State private var month = MonthView.startOfMonth(.now)
    /// The month named in the header and used for the totals below. It changes together with `month`.
    @State private var titleMonth = MonthView.startOfMonth(.now)
    @State private var slideEdge: Edge = .trailing
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
        visible.filter { calendar.isDate($0.dueDate, equalTo: titleMonth, toGranularity: .month) }
    }

    private func instancesByDay(in monthDate: Date) -> [Int: [BillInstance]] {
        let inMonth = visible.filter { calendar.isDate($0.dueDate, equalTo: monthDate, toGranularity: .month) }
        return Dictionary(grouping: inMonth) { calendar.component(.day, from: $0.dueDate) }
    }

    private var monthTotal: Decimal {
        monthInstances.reduce(0) { $0 + ($1.amount ?? 0) }
    }

    /// Paydays only make sense for a single profile; "All" mixes different schedules.
    private var selectedProfile: Profile? {
        profiles.first { $0.id.uuidString == selectedProfileID }
    }

    /// Follows the header's month, so the cards below change along with the slide.
    private var cutoffs: [Cutoff] { cutoffs(in: titleMonth) }

    private func cutoffs(in monthDate: Date) -> [Cutoff] {
        guard let paydays = selectedProfile?.paydays else { return [] }
        return CutoffCalculator.cutoffs(paydays: paydays, in: monthDate)
    }

    /// Days of a month that are paydays. A cutoff can end in the next month, so check the month.
    private func paydayDays(in monthDate: Date) -> Set<Int> {
        Set(
            cutoffs(in: monthDate).compactMap { $0.payday }
                .filter { calendar.isDate($0, equalTo: monthDate, toGranularity: .month) }
                .map { calendar.component(.day, from: $0) }
        )
    }

    private var selectedInstances: [BillInstance] {
        visible.filter { calendar.isDate($0.dueDate, inSameDayAs: selectedDate) }
    }

    /// The month's days, preceded by empty cells so the 1st lands on the right weekday.
    private func gridDays(in monthDate: Date) -> [Date?] {
        guard let days = calendar.range(of: .day, in: .month, for: monthDate) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: monthDate)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let dates: [Date?] = days.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: monthDate) }
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
        .ownsTopOfScreen()
        .navigationDestination(for: Bill.self) { BillDetailView(bill: $0) }
    }

    // MARK: Header and calendar

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                // The name slides out the way you're swiping and the next one slides in behind it.
                ZStack(alignment: .leading) {
                    Text(titleMonth.formatted(.dateTime.month(.wide)).uppercased())
                        .font(.barlow(60, weight: .medium, relativeTo: .largeTitle))
                        .foregroundStyle(strong)
                        .id(titleMonth)
                        .transition(.push(from: slideEdge))
                }
                .clipped()
                Spacer()
                Eyebrow(titleMonth.formatted(.dateTime.year()), color: strong)
                    .contentTransition(.numericText())
            }
            .padding(.top, 8)
            .padding(.bottom, -8)

            HStack {
                Text("\(monthInstances.count) \(monthInstances.count == 1 ? "BILL" : "BILLS") · \(monthTotal.pesoString)")
                    .contentTransition(.numericText())
                    .font(.barlow(22, weight: .semibold, relativeTo: .title3))
                    .tracking(1.2)
                    .foregroundStyle(Theme.ink)
                Spacer()
                ProfileSwitcher(selectedID: $selectedProfileID)
                    .font(.outfit(14, weight: .semibold, relativeTo: .subheadline))
                    .secondaryButton(tint: strong)
            }

            DashedDivider(color: strong.opacity(0.4))

            swipeableCalendar

            legend
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { Theme.monthTint.padding(.top, -400) }
    }

    /// Swipe left for the next month, right for the previous. The calendar slides once the swipe is
    /// done, rather than following the finger, which keeps scrolling smooth.
    private var swipeableCalendar: some View {
        ZStack(alignment: .top) {
            calendarGrid(for: month)
                .id(month)
                .transition(.push(from: slideEdge))
        }
        .frame(maxWidth: .infinity)
        // A 4-, 5- or 6-week month needs a different height, which animates with the slide.
        .frame(height: height(of: month), alignment: .top)
        .clipped()
        // It only reacts to clearly sideways drags, so taps on a day and scrolling still work.
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onChanged { value in
                    if abs(value.translation.width) > abs(value.translation.height) { ignoreDayTaps = true }
                }
                .onEnded { value in
                    let sideways = value.translation.width
                    let vertical = value.translation.height
                    if abs(sideways) > 60, abs(sideways) > abs(vertical) * 1.5 {
                        changeMonth(by: sideways < 0 ? 1 : -1)
                    }
                    // The day under your finger may still receive the release, so keep ignoring briefly.
                    Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        ignoreDayTaps = false
                    }
                }
        )
    }

    private func height(of monthDate: Date) -> CGFloat {
        let rows = CGFloat((gridDays(in: monthDate).count + 6) / 7)
        // The weekday row, then one row of 50 per week, with the grid's spacing between them.
        return Self.weekdayRowHeight + 8 + rows * 50 + (rows - 1) * 6
    }

    private static let weekdayRowHeight: CGFloat = 16

    private func calendarGrid(for monthDate: Date) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let days = gridDays(in: monthDate)
        let bills = instancesByDay(in: monthDate)
        let paydays = paydayDays(in: monthDate)
        return VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdaySymbols.indices, id: \.self) { index in
                    Text(weekdaySymbols[index])
                        .font(.outfit(12, weight: .semibold, relativeTo: .caption))
                        .foregroundStyle(strong)
                        .frame(height: Self.weekdayRowHeight)
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(days.indices, id: \.self) { index in
                    if let date = days[index] {
                        dayCell(date, bills: bills, paydays: paydays)
                    } else {
                        Color.clear.frame(height: 50)
                    }
                }
            }
        }
    }

    private func dayCell(_ date: Date, bills byDay: [Int: [BillInstance]], paydays: Set<Int>) -> some View {
        let day = calendar.component(.day, from: date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let bills = byDay[day] ?? []

        return Button {
            guard !ignoreDayTaps else { return }
            selectedDate = date
        } label: {
            VStack(spacing: 2) {
                Text("\(day)")
                    .font(.outfit(16, weight: .semibold, relativeTo: .body))
                HStack(spacing: 3) {
                    ForEach(bills.prefix(3)) { bill in
                        Circle().fill(dotColor(for: bill, selected: isSelected)).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
                Text(paydays.contains(day) ? "PAY" : " ")
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

    /// Slides to the next or previous month. The calendar, the month name, the day's bills and the
    /// cutoff totals all change in the same animation.
    private func changeMonth(by value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: month) else { return }
        // The calendar and the name slide in from the side you're moving towards.
        slideEdge = value > 0 ? .trailing : .leading
        withAnimation(.snappy) {
            month = next
            titleMonth = next
            selectedDate = defaultSelection(in: next)
        }
    }

    /// Keep a day selected: today if it's in this month, otherwise the 1st.
    private func defaultSelection(in monthDate: Date) -> Date {
        calendar.isDate(monthDate, equalTo: .now, toGranularity: .month)
            ? calendar.startOfDay(for: .now)
            : monthDate
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
            .animation(.snappy, value: titleMonth)
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
                .contentTransition(.numericText())
            Text(summary.total.pesoString)
                .font(.barlow(30, weight: .medium, relativeTo: .title))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text("\(summary.paidCount) of \(summary.count) paid")
                .font(.outfit(13, relativeTo: .footnote))
                .foregroundStyle(Theme.mutedInk)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    // MARK: Selected day

    private var dayDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Each day's content fades and drifts in, and the card grows or shrinks to fit it.
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
            .id(selectedDate)
            .transition(.opacity.combined(with: .offset(y: 10)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .animation(.snappy, value: selectedDate)
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
