import Foundation

/// Finds a saved billing account that a scanned or typed bill belongs to, so the same account isn't
/// saved twice.
enum AccountMatcher {
    /// The digits of an account number, so "2011-4589-321" and "20114589321" compare equal.
    static func digits(_ number: String?) -> String {
        (number ?? "").filter(\.isNumber)
    }

    /// An existing account for this bill, or nil. In order of confidence:
    /// 1. The same account number (at least 4 digits), whatever the biller was recognised as.
    /// 2. The same biller, when neither account has a number or the numbers agree.
    /// 3. The same name for a custom biller, on the same terms.
    /// Archived accounts and accounts in other profiles are never matched.
    static func find(
        in accounts: [Bill],
        presetID: String?,
        name: String,
        accountNumber: String?,
        profileID: UUID?
    ) -> Bill? {
        let candidates = accounts.filter { !$0.isArchived && $0.profile?.id == profileID }
        let number = digits(accountNumber)

        // 1. The account number is the strongest sign.
        if number.count >= 4,
           let byNumber = candidates.first(where: { digits($0.accountNumber) == number }) {
            return byNumber
        }

        // 2 and 3. The same biller, as long as the numbers don't contradict each other.
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        return candidates.first { account in
            let sameBiller: Bool
            if let presetID {
                sameBiller = account.presetID == presetID
            } else {
                sameBiller = !trimmedName.isEmpty
                    && account.name.caseInsensitiveCompare(trimmedName) == .orderedSame
            }
            guard sameBiller else { return false }
            let existing = digits(account.accountNumber)
            return number.isEmpty || existing.isEmpty || existing == number
        }
    }
}
