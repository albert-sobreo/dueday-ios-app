import Foundation
import SwiftData
import SwiftUI

/// A biller the user created themselves, for anything not in the bundled `presets.json`.
/// Saved so it can be picked again for later bills.
@Model
final class CustomProvider {
    var id: UUID = UUID()
    var name: String = ""
    var category: BillCategory = BillCategory.other
    var amountType: AmountType = AmountType.fixed
    /// What this biller calls the account number, e.g. "Member Number". Optional.
    var accountNumberLabel: String?
    var colorHex: String = Profile.palette[0]
    /// A logo the user uploaded for this provider, as a small square image.
    @Attribute(.externalStorage) var logoData: Data?

    init(name: String = "", category: BillCategory = .other) {
        self.name = name
        self.category = category
    }

    /// Prefix that tells a custom provider's id apart from a bundled preset's id.
    static let idPrefix = "custom-"

    /// The same shape as a bundled preset, so pickers and forms can treat both alike.
    var asPreset: BillPreset {
        BillPreset(
            id: Self.idPrefix + id.uuidString,
            name: name,
            category: category,
            icon: category.symbol,
            colorHex: colorHex,
            amountType: amountType,
            accountNumberLabel: accountNumberLabel,
            keywords: nil
        )
    }
}
