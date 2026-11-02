import Foundation

/// The stretch between two paydays: it starts the day after one payday and ends on the next.
/// With paydays on the 10th and 25th the cutoffs are the 26th–10th and the 11th–25th, so one can
/// begin in the previous month.
struct Cutoff: Equatable {
    let startDate: Date
    let endDate: Date
    let startDay: Int
    let endDay: Int
    /// The payday that ends this cutoff.
    let payday: Date?

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= startDate && day <= endDate
    }

    /// "26–10" or "11–25": the days of the month it starts and ends on.
    var rangeTitle: String { "\(startDay)–\(endDay)" }

    /// "Nov 11–25", or "Oct 26–Nov 10" when it spans two months.
    func longTitle(calendar: Calendar = .current) -> String {
        let startMonth = startDate.formatted(.dateTime.month(.abbreviated))
        let endMonth = endDate.formatted(.dateTime.month(.abbreviated))
        if calendar.isDate(startDate, equalTo: endDate, toGranularity: .month) {
            return "\(startMonth) \(startDay)–\(endDay)"
        }
        return "\(startMonth) \(startDay)–\(endMonth) \(endDay)"
    }
}

enum CutoffCalculator {
    /// The cutoffs that overlap the month containing `date`, oldest first. Each runs from the day
    /// after one payday to the next payday. Paydays past the end of a short month move to its last day.
    static func cutoffs(paydays: [Int], in date: Date, calendar: Calendar = .current) -> [Cutoff] {
        guard !paydays.isEmpty,
              let month = calendar.dateInterval(of: .month, for: date),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: month.end)
        else { return [] }

        let dates = paydayDates(paydays, around: month.start, calendar: calendar)
        var result: [Cutoff] = []

        for index in 1..<max(dates.count, 1) {
            let previous = dates[index - 1]
            let end = dates[index]
            guard let start = calendar.date(byAdding: .day, value: 1, to: previous) else { continue }
            // Keep the cutoffs that touch this month.
            guard end >= month.start, start <= lastDay else { continue }
            result.append(Cutoff(
                startDate: start, endDate: end,
                startDay: calendar.component(.day, from: start),
                endDay: calendar.component(.day, from: end),
                payday: end
            ))
        }
        return result
    }

    static func cutoff(containing date: Date, paydays: [Int], calendar: Calendar = .current) -> Cutoff? {
        cutoffs(paydays: paydays, in: date, calendar: calendar).first { $0.contains(date, calendar: calendar) }
    }

    /// Every payday from two months before to two months after, sorted.
    private static func paydayDates(_ paydays: [Int], around monthStart: Date, calendar: Calendar) -> [Date] {
        var dates: [Date] = []
        for offset in -2...2 {
            guard let start = calendar.date(byAdding: .month, value: offset, to: monthStart),
                  let length = calendar.range(of: .day, in: .month, for: start)?.count
            else { continue }
            let days = Set(paydays.map { min(max($0, 1), length) })
            for day in days {
                if let date = calendar.date(byAdding: .day, value: day - 1, to: start) {
                    dates.append(date)
                }
            }
        }
        return dates.sorted()
    }
}

/// Totals for the bills falling in one cutoff.
struct CutoffSummary {
    let cutoff: Cutoff
    let count: Int
    let paidCount: Int
    let total: Decimal
    let paidTotal: Decimal

    /// Still to set aside before the payday.
    var leftToCover: Decimal { total - paidTotal }

    init(cutoff: Cutoff, instances: [BillInstance]) {
        self.cutoff = cutoff
        let inCutoff = instances.filter { cutoff.contains($0.dueDate) }
        count = inCutoff.count
        paidCount = inCutoff.filter(\.isPaid).count
        total = inCutoff.reduce(0) { $0 + ($1.amount ?? 0) }
        paidTotal = inCutoff.filter(\.isPaid).reduce(0) { $0 + ($1.amount ?? 0) }
    }
}
