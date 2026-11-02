import SwiftUI

/// A bundled biller template. Presets live in `presets.json`, not in the database.
struct BillPreset: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: BillCategory
    let icon: String
    let colorHex: String
    let amountType: AmountType
    let accountNumberLabel: String?
    /// Words that identify this biller on a scanned bill (used by scanning in phase 2).
    let keywords: [String]?

    var color: Color { Color(hex: colorHex) }
}

enum PresetStore {
    static let all: [BillPreset] = load()

    static func preset(withID id: String?) -> BillPreset? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    private static func load() -> [BillPreset] {
        guard let url = Bundle.main.url(forResource: "presets", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let presets = try? JSONDecoder().decode([BillPreset].self, from: data)
        else {
            assertionFailure("presets.json is missing or invalid")
            return []
        }
        return presets
    }
}

extension Color {
    /// Creates a color from a hex string such as "E8590C".
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x808080
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
