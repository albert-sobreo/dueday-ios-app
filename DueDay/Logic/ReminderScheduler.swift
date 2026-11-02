import Foundation
import SwiftData
import UserNotifications

/// When reminders go off, shared by the scheduler and the screens that show it.
enum ReminderSettings {
    static let minutesKey = "reminderMinutes"
    /// 9:00 AM, as minutes after midnight.
    static let defaultMinutes = 9 * 60

    static var minutes: Int {
        UserDefaults.standard.object(forKey: minutesKey) as? Int ?? defaultMinutes
    }

    /// The time of day on a given date.
    static func date(on day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
    }
}

/// Schedules local notifications for unpaid bills and for variable accounts that are waiting for a bill.
/// iOS keeps only 64 pending notifications per app, so the soonest ones are scheduled and the rest
/// are topped up each time the app opens or goes to the background.
@MainActor
enum ReminderScheduler {
    static let billCategory = "BILL_REMINDER"
    static let markPaidAction = "MARK_PAID"
    private static let limit = 60

    private static var center: UNUserNotificationCenter { .current() }

    /// Registers the "Mark paid" button shown on bill reminders.
    static func registerCategories() {
        let markPaid = UNNotificationAction(identifier: markPaidAction, title: "Mark paid", options: [])
        let category = UNNotificationCategory(identifier: billCategory, actions: [markPaid], intentIdentifiers: [])
        center.setNotificationCategories([category])
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Asks for permission the first time. Does nothing if the person has already answered.
    @discardableResult
    static func requestAuthorizationIfNeeded() async -> Bool {
        let status = await authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    /// Replaces all pending reminders with ones built from the current bills.
    static func reschedule(in context: ModelContext) async {
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            center.removeAllPendingNotificationRequests()
            return
        }

        let calendar = Calendar.current
        let now = Date.now
        var pending: [(date: Date, request: UNNotificationRequest)] = []

        let profileCount = (try? context.fetchCount(FetchDescriptor<Profile>())) ?? 0
        let bills = (try? context.fetch(FetchDescriptor<Bill>())) ?? []

        for bill in bills where !bill.isArchived {
            let prefix = profileCount > 1 ? (bill.profile.map { "\($0.name) · " } ?? "") : ""

            // Reminders before each unpaid bill is due.
            for instance in bill.instances ?? [] where !instance.isPaid {
                for offset in Set(bill.reminderOffsets) {
                    guard let day = calendar.date(byAdding: .day, value: -offset, to: instance.dueDate) else { continue }
                    let fireDate = ReminderSettings.date(on: day, calendar: calendar)
                    guard fireDate > now else { continue }

                    let content = UNMutableNotificationContent()
                    content.title = prefix + bill.name
                    content.body = body(for: instance, daysBefore: offset)
                    content.sound = .default
                    content.categoryIdentifier = billCategory
                    content.userInfo = ["instanceID": instance.id.uuidString]
                    pending.append((fireDate, request(
                        id: "bill-\(instance.id.uuidString)-\(offset)", content: content, date: fireDate, calendar: calendar
                    )))
                }
            }

            // A nudge for a variable account whose bill hasn't been added yet this month.
            if let nudge = nudgeDate(for: bill, now: now, calendar: calendar) {
                let content = UNMutableNotificationContent()
                content.title = prefix + bill.name
                content.body = "Has this month's bill arrived? Add the amount and due date."
                content.sound = .default
                pending.append((nudge, request(
                    id: "nudge-\(bill.id.uuidString)", content: content, date: nudge, calendar: calendar
                )))
            }
        }

        center.removeAllPendingNotificationRequests()
        for item in pending.sorted(by: { $0.date < $1.date }).prefix(limit) {
            try? await center.add(item.request)
        }
    }

    // MARK: Helpers

    private static func request(id: String, content: UNNotificationContent, date: Date, calendar: Calendar) -> UNNotificationRequest {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    private static func body(for instance: BillInstance, daysBefore: Int) -> String {
        let when: String
        switch daysBefore {
        case 0: when = "Due today"
        case 1: when = "Due tomorrow"
        default: when = "Due in \(daysBefore) days"
        }
        if let amount = instance.amount { return "\(when) · \(amount.currencyString)" }
        return when
    }

    /// The next time to nudge: the account's usual arrival day, this month if it's still ahead and no
    /// bill was added yet, otherwise next month.
    private static func nudgeDate(for bill: Bill, now: Date, calendar: Calendar) -> Date? {
        guard bill.amountType == .variable, let day = bill.expectedDay else { return nil }
        let addedThisMonth = (bill.instances ?? []).contains {
            calendar.isDate($0.createdAt, equalTo: now, toGranularity: .month)
        }

        for monthOffset in addedThisMonth ? [1] : [0, 1] {
            guard let month = calendar.date(byAdding: .month, value: monthOffset, to: now),
                  let monthStart = calendar.dateInterval(of: .month, for: month)?.start,
                  let length = calendar.range(of: .day, in: .month, for: monthStart)?.count,
                  let target = calendar.date(byAdding: .day, value: min(day, length) - 1, to: monthStart)
            else { continue }
            let fireDate = ReminderSettings.date(on: target, calendar: calendar)
            if fireDate > now { return fireDate }
        }
        return nil
    }
}

/// Handles taps on notifications, including the "Mark paid" button.
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    var container: ModelContainer?

    /// Show reminders as banners even while the app is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == ReminderScheduler.markPaidAction,
              let idString = response.notification.request.content.userInfo["instanceID"] as? String,
              let id = UUID(uuidString: idString)
        else { return }
        await markPaid(instanceID: id)
    }

    /// Pays the bill with its known amount and usual method, then refreshes the reminders.
    private func markPaid(instanceID: UUID) async {
        guard let context = container?.mainContext else { return }
        let descriptor = FetchDescriptor<BillInstance>(predicate: #Predicate { $0.id == instanceID })
        guard let instance = (try? context.fetch(descriptor))?.first, !instance.isPaid else { return }
        if instance.quickPay(in: context) {
            try? context.save()
            await ReminderScheduler.reschedule(in: context)
        }
    }
}
