import Foundation

/// The currency amounts are shown in. It starts as the currency of the phone's region and can be
/// changed in Settings.
enum CurrencySetting {
    static let storageKey = "currencyCode"

    /// Currencies offered in Settings, most relevant first.
    static let choices = [
        "PHP", "USD", "EUR", "GBP", "JPY", "SGD", "HKD", "AUD", "CAD", "NZD", "AED", "SAR",
        "KRW", "CNY", "INR", "MYR", "THB", "IDR", "VND",
    ]

    /// The currency of the user's region, or pesos if it can't be told.
    static var detectedCode: String {
        Locale.current.currency?.identifier ?? "PHP"
    }

    /// The code in use: the one chosen in Settings, otherwise the region's.
    static var code: String {
        UserDefaults.standard.string(forKey: storageKey) ?? detectedCode
    }

    /// Pesos use the Philippine locale so they show as ₱; other currencies follow the phone's locale.
    static func locale(for code: String) -> Locale {
        code == "PHP" ? Locale(identifier: "en_PH") : .current
    }

    /// "₱", "$" and so on.
    static var symbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = locale(for: code)
        return formatter.currencySymbol ?? code
    }

    /// "Philippine Peso" for a code.
    static func name(for code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }
}

extension Decimal {
    /// The amount in the selected currency, such as "₱2,345.60".
    var currencyString: String {
        formatted(.currency(code: CurrencySetting.code).locale(CurrencySetting.locale(for: CurrencySetting.code)))
    }

    /// Kept for existing call sites; formats in the selected currency, not only pesos.
    var pesoString: String { currencyString }
}

extension String {
    /// Parses user input like "2,345.60" into a Decimal, ignoring commas and a currency sign.
    var parsedAmount: Decimal? {
        let cleaned = replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: CurrencySetting.symbol, with: "")
            .replacingOccurrences(of: "₱", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US"))
    }
}
