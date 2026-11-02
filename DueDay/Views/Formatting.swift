import Foundation

extension Decimal {
    /// Peso amount such as "₱2,345.60".
    var pesoString: String {
        formatted(.currency(code: "PHP").locale(Locale(identifier: "en_PH")))
    }
}

extension String {
    /// Parses user input like "2,345.60" into a Decimal.
    var parsedAmount: Decimal? {
        let cleaned = replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "₱", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US"))
    }
}
