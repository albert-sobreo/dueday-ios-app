import Foundation
import UIKit

/// Hands a paid bill to Katherine: Expense Tracker, which opens a new expense already filled in.
/// Nothing is shared or synced between the apps: the link carries this one payment, and Katherine
/// matches the payee and payment method to its own names (and remembers your corrections).
enum KatherineLink {
    /// True when Katherine is installed. Needs "katherine" under LSApplicationQueriesSchemes in Info.plist.
    @MainActor static var isAvailable: Bool {
        UIApplication.shared.canOpenURL(URL(string: "katherine://log")!)
    }

    static func url(payee: String, amount: Decimal, date: Date, method: String?, note: String?) -> URL? {
        var c = URLComponents()
        c.scheme = "katherine"
        c.host = "log"
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        var items = [
            URLQueryItem(name: "payee", value: payee),
            URLQueryItem(name: "amount", value: NSDecimalNumber(decimal: amount).stringValue),
            URLQueryItem(name: "date", value: f.string(from: date)),
        ]
        if let method, !method.isEmpty { items.append(URLQueryItem(name: "method", value: method)) }
        if let note, !note.isEmpty { items.append(URLQueryItem(name: "note", value: note)) }
        c.queryItems = items
        return c.url
    }
}
