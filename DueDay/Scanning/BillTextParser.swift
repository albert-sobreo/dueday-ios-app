import Foundation

/// What could be read from a bill. Anything that wasn't found is nil, and the person fills it in.
struct ScannedBill: Hashable {
    var presetID: String?
    var providerName: String?
    var accountNumber: String?
    var amount: Decimal?
    var dueDate: Date?
    var billingPeriod: String?
}

/// Finds the biller, amount due, due date, account number and billing period in a bill's text.
/// It looks for the label a biller prints, like "Total Amount Due", and reads what's beside or below it.
enum BillTextParser {
    // Labels, most specific first. Matching ignores case.
    private static let amountLabels = [
        "total amount due", "total amount payable", "amount payable", "amount due", "total due",
        "amount to pay", "please pay", "balance due",
    ]
    private static let dueDateLabels = [
        "payment due date", "due date", "pay on or before", "please pay on or before", "pay before", "due on", "due by",
    ]
    private static let accountLabels = [
        "customer account number", "contract account number", "account number", "account no", "acct no",
        "acct. no", "account #", "customer no",
    ]
    private static let periodLabels = ["billing period", "bill period", "statement period", "service period", "period covered"]

    static func parse(lines rawLines: [String], presets: [BillPreset], calendar: Calendar = .current) -> ScannedBill {
        let lines = rawLines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var result = ScannedBill()

        if let preset = matchPreset(in: lines, presets: presets) {
            result.presetID = preset.id
            result.providerName = preset.name
        }
        result.amount = findAmount(in: lines)
        result.dueDate = findDueDate(in: lines, calendar: calendar)
        result.accountNumber = findAccountNumber(in: lines)
        result.billingPeriod = findPeriod(in: lines)
        return result
    }

    // MARK: Biller

    /// The preset whose keyword appears in the text, preferring the longest keyword. Short keywords like
    /// "SKY" or "BDO" must stand alone as words, so they don't match inside other words.
    private static func matchPreset(in lines: [String], presets: [BillPreset]) -> BillPreset? {
        let text = lines.joined(separator: "\n").uppercased()
        var best: (preset: BillPreset, length: Int)?
        for preset in presets {
            for keyword in preset.keywords ?? [] {
                let key = keyword.uppercased()
                let matches = key.count <= 4
                    ? text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: key))\\b", options: .regularExpression) != nil
                    : text.contains(key)
                if matches, key.count > (best?.length ?? 0) {
                    best = (preset, key.count)
                }
            }
        }
        return best?.preset
    }

    // MARK: Amount

    private static let moneyPattern = "(?:PHP|PhP|Php|P|₱)?\\s?([0-9]{1,3}(?:,[0-9]{3})+(?:\\.[0-9]{2})?|[0-9]+\\.[0-9]{2})"

    private static func findAmount(in lines: [String]) -> Decimal? {
        for label in amountLabels {
            for (index, line) in lines.enumerated() {
                guard let range = line.range(of: label, options: .caseInsensitive) else { continue }
                // The amount is on the same line after the label, or on one of the next two lines.
                let candidates = [String(line[range.upperBound...])] + lines.dropFirst(index + 1).prefix(2)
                for candidate in candidates {
                    if let text = firstMatch(moneyPattern, in: candidate),
                       let amount = Decimal(string: text.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US")),
                       amount > 0 {
                        return amount
                    }
                }
            }
        }
        return nil
    }

    // MARK: Dates

    private static func findDueDate(in lines: [String], calendar: Calendar) -> Date? {
        for label in dueDateLabels {
            for (index, line) in lines.enumerated() {
                guard let range = line.range(of: label, options: .caseInsensitive) else { continue }
                let candidates = [String(line[range.upperBound...])] + lines.dropFirst(index + 1).prefix(2)
                for candidate in candidates {
                    if let date = findDate(in: candidate, calendar: calendar) { return date }
                }
            }
        }
        return nil
    }

    private static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    private static func month(named name: String) -> Int? {
        monthNames.firstIndex(of: String(name.lowercased().prefix(3))).map { $0 + 1 }
    }

    /// "Nov 15, 2026", "November 15, 2026", "15 Nov 2026", "15-Nov-2026" or "11/15/2026".
    static func findDate(in text: String, calendar: Calendar = .current) -> Date? {
        func make(_ year: Int, _ month: Int, _ day: Int) -> Date? {
            let fullYear = year < 100 ? 2000 + year : year
            guard (1...12).contains(month), (1...31).contains(day) else { return nil }
            return calendar.date(from: DateComponents(year: fullYear, month: month, day: day))
        }

        // "Nov 15, 2026"
        if let parts = groups("([A-Za-z]{3,9})\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?,?\\s+(\\d{4})", in: text),
           let m = month(named: parts[0]), let day = Int(parts[1]), let year = Int(parts[2]) {
            return make(year, m, day)
        }
        // "15 Nov 2026", "15-Nov-2026"
        if let parts = groups("(\\d{1,2})[\\s-]+([A-Za-z]{3,9})\\.?,?[\\s-]+(\\d{4})", in: text),
           let day = Int(parts[0]), let m = month(named: parts[1]), let year = Int(parts[2]) {
            return make(year, m, day)
        }
        // "11/15/2026": month first, as Philippine bills usually print it.
        if let parts = groups("(\\d{1,2})/(\\d{1,2})/(\\d{2,4})", in: text),
           let m = Int(parts[0]), let day = Int(parts[1]), let year = Int(parts[2]) {
            return make(year, m, day)
        }
        return nil
    }

    // MARK: Account number and period

    private static func findAccountNumber(in lines: [String]) -> String? {
        for label in accountLabels {
            for (index, line) in lines.enumerated() {
                guard let range = line.range(of: label, options: .caseInsensitive) else { continue }
                let candidates = [String(line[range.upperBound...])] + lines.dropFirst(index + 1).prefix(1)
                for candidate in candidates {
                    if let number = firstMatch("([0-9][0-9\\- ]{5,22}[0-9])", in: candidate) {
                        return number.replacingOccurrences(of: " ", with: "")
                    }
                }
            }
        }
        return nil
    }

    private static func findPeriod(in lines: [String]) -> String? {
        for label in periodLabels {
            for (index, line) in lines.enumerated() {
                guard let range = line.range(of: label, options: .caseInsensitive) else { continue }
                var rest = String(line[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " :-–"))
                if rest.count < 4, index + 1 < lines.count { rest = lines[index + 1] }
                rest = rest.trimmingCharacters(in: .whitespaces)
                if rest.count >= 4 { return String(rest.prefix(40)) }
            }
        }
        return nil
    }

    // MARK: Regex helpers

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        groups(pattern, in: text)?.first
    }

    /// The capture groups of the first match, or nil if there's none.
    private static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        var result: [String] = []
        for index in 1..<max(match.numberOfRanges, 2) {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
            result.append(String(text[swiftRange]))
        }
        return result
    }
}
