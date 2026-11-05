import Foundation
import SwiftData

/// The quick filters on the Bills tab.
enum BillFilter: String, CaseIterable, Identifiable {
    // The order here is the order of the chips: cutoffs first, then accounts, then the rest, and All last.
    case currentCutoff, nextCutoff, laterCutoffs, accounts, overdue, dueSoon, paid, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .overdue: "Overdue"
        case .dueSoon: "Due soon"
        case .currentCutoff: "This cutoff"
        case .nextCutoff: "Next cutoff"
        case .laterCutoffs: "Later"
        case .paid: "Paid"
        case .accounts: "Accounts"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .overdue: "exclamationmark.circle"
        case .dueSoon: "clock"
        case .currentCutoff: "calendar.badge.clock"
        case .nextCutoff: "arrow.right.circle"
        case .laterCutoffs: "calendar"
        case .paid: "checkmark.circle"
        case .accounts: "person.text.rectangle"
        }
    }

    /// These need the profile's paydays to mean anything.
    var needsCutoffs: Bool {
        self == .currentCutoff || self == .nextCutoff || self == .laterCutoffs
    }

    /// Filters that list individual bills, as opposed to the full overview or the account list.
    var listsBills: Bool { self != .all && self != .accounts }
}

/// A variable account's upcoming due date while that month's bill hasn't been added yet, shown as
/// "No bill yet" in the cutoff it falls in.
struct AwaitedBill: Identifiable {
    let bill: Bill
    let dueDate: Date
    var id: String { "\(bill.id.uuidString)-\(dueDate.timeIntervalSinceReferenceDate)" }
}

/// Works out which bills belong under each filter. `instances` should already be limited to the
/// selected profile and to active (not archived) accounts.
struct BillFilterEngine {
    let instances: [BillInstance]
    let paydays: [Int]
    let now: Date
    let calendar: Calendar

    /// How many days ahead counts as "due soon".
    static let dueSoonDays = 7

    // These are worked out once, when the engine is made. The Bills tab asks for them many times
    // (every filter chip, every cutoff group), and each one reads every bill's data.
    let unpaid: [BillInstance]
    let overdue: [BillInstance]
    /// Unpaid bills that aren't overdue.
    let upcoming: [BillInstance]
    /// The cutoff we're in, then the ones that follow, oldest first. Empty without paydays.
    let cutoffs: [Cutoff]
    /// Bills paid in the current month, most recent first.
    let paidThisMonth: [BillInstance]
    let dueSoon: [BillInstance]
    /// Variable accounts still waiting for a bill, by their usual due date, soonest first.
    let awaited: [AwaitedBill]

    /// `accounts` are the active accounts, used to find variable ones still waiting for a bill.
    init(
        instances: [BillInstance],
        paydays: [Int],
        accounts: [Bill] = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        self.instances = instances
        self.paydays = paydays
        self.now = now
        self.calendar = calendar

        let today = calendar.startOfDay(for: now)

        let unpaid = instances.filter { !$0.isPaid }.sorted { $0.dueDate < $1.dueDate }
        // Unpaid and not overdue means due today or later, which is read once per bill here.
        let overdue = unpaid.filter { calendar.startOfDay(for: $0.dueDate) < today }
        let upcoming = unpaid.filter { calendar.startOfDay(for: $0.dueDate) >= today }
        self.unpaid = unpaid
        self.overdue = overdue
        self.upcoming = upcoming

        if let end = calendar.date(byAdding: .day, value: Self.dueSoonDays, to: today) {
            dueSoon = upcoming.filter { $0.dueDate <= end }
        } else {
            dueSoon = []
        }

        paidThisMonth = instances
            .filter { instance in
                guard instance.isPaid else { return false }
                let paidOn = instance.latestPayment?.paidDate ?? instance.dueDate
                return calendar.isDate(paidOn, equalTo: now, toGranularity: .month)
            }
            .sorted {
                ($0.latestPayment?.paidDate ?? $0.dueDate) > ($1.latestPayment?.paidDate ?? $1.dueDate)
            }

        awaited = accounts
            .flatMap { bill in
                bill.awaitedDueDates(now: now, calendar: calendar).map { AwaitedBill(bill: bill, dueDate: $0) }
            }
            .sorted { $0.dueDate < $1.dueDate }

        if paydays.isEmpty {
            cutoffs = []
        } else {
            var seen = Set<Date>()
            var result: [Cutoff] = []
            for offset in 0...3 {
                guard let month = calendar.date(byAdding: .month, value: offset, to: today) else { continue }
                for cutoff in CutoffCalculator.cutoffs(paydays: paydays, in: month, calendar: calendar)
                where cutoff.endDate >= today && seen.insert(cutoff.startDate).inserted {
                    result.append(cutoff)
                }
            }
            cutoffs = result.sorted { $0.startDate < $1.startDate }
        }
    }

    /// Everything unpaid that falls in a cutoff. That includes a bill already overdue, when its due
    /// date is inside the cutoff, so it's still listed where it belongs.
    func bills(in cutoff: Cutoff) -> [BillInstance] {
        unpaid.filter { cutoff.contains($0.dueDate, calendar: calendar) }
    }

    /// Variable accounts waiting for a bill that's usually due in a cutoff.
    func awaited(in cutoff: Cutoff) -> [AwaitedBill] {
        awaited.filter { cutoff.contains($0.dueDate, calendar: calendar) }
    }

    /// Cutoffs after the next one: the "Later" list.
    var laterCutoffs: [Cutoff] { Array(cutoffs.dropFirst(2)) }

    /// Bills in a later cutoff, keeping only each account's first bill across all later cutoffs.
    /// A monthly bill is made a few months ahead, so without this it would show up several times.
    func laterBills(in cutoff: Cutoff) -> [BillInstance] {
        let later = laterCutoffs
        var seen = Set<PersistentIdentifier>()
        let firsts = unpaid.filter { instance in
            guard later.contains(where: { $0.contains(instance.dueDate, calendar: calendar) }),
                  let bill = instance.bill
            else { return false }
            return seen.insert(bill.persistentModelID).inserted
        }
        return firsts.filter { cutoff.contains($0.dueDate, calendar: calendar) }
    }

    /// Variable accounts waiting for a bill in a later cutoff, each account once.
    func laterAwaited(in cutoff: Cutoff) -> [AwaitedBill] {
        let later = laterCutoffs
        var seen = Set<PersistentIdentifier>()
        let firsts = awaited.filter { item in
            later.contains { $0.contains(item.dueDate, calendar: calendar) }
                && seen.insert(item.bill.persistentModelID).inserted
        }
        return firsts.filter { cutoff.contains($0.dueDate, calendar: calendar) }
    }

    /// Overdue bills that no listed cutoff covers, because they're older than the current cutoff.
    /// Overdue bills inside a cutoff are shown there instead. Without paydays, all of them.
    var overdueBeforeCutoffs: [BillInstance] {
        guard !cutoffs.isEmpty else { return overdue }
        return overdue.filter { bill in
            !cutoffs.contains { $0.contains(bill.dueDate, calendar: calendar) }
        }
    }

    /// Bills for the filters that list bills. `.all` and `.accounts` aren't bill lists.
    func items(for filter: BillFilter) -> [BillInstance] {
        switch filter {
        case .all, .accounts: return []
        case .overdue: return overdue
        case .dueSoon: return dueSoon
        case .paid: return paidThisMonth
        case .currentCutoff: return cutoffs.first.map(bills(in:)) ?? []
        case .nextCutoff: return cutoffs.dropFirst().first.map(bills(in:)) ?? []
        case .laterCutoffs: return laterCutoffs.flatMap(laterBills(in:))
        }
    }

    /// Accounts waiting for a bill under a cutoff filter. Other filters list only real bills.
    func awaitedItems(for filter: BillFilter) -> [AwaitedBill] {
        switch filter {
        case .currentCutoff: return cutoffs.first.map(awaited(in:)) ?? []
        case .nextCutoff: return cutoffs.dropFirst().first.map(awaited(in:)) ?? []
        case .laterCutoffs: return laterCutoffs.flatMap(laterAwaited(in:))
        default: return []
        }
    }

    /// The number shown on a filter chip, or nil when it doesn't have one.
    func count(for filter: BillFilter) -> Int? {
        filter.listsBills ? items(for: filter).count + awaitedItems(for: filter).count : nil
    }
}
