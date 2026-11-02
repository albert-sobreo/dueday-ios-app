import SwiftUI
import UIKit

extension Color {
    /// "C4472F"-style hex for this colour, without alpha.
    var hexString: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "%02X%02X%02X",
            Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded())
        )
    }
}

extension Color {
    /// A stored colour that stays readable in dark mode: unchanged in light mode, and in dark mode
    /// lighter and a little softer. This works for any colour a user picks.
    static func adaptive(hex: String) -> Color {
        let light = UIColor(Color(hex: hex))
        return Color(uiColor: UIColor { traits in
            guard traits.userInterfaceStyle == .dark else { return light }
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            light.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            return UIColor(
                hue: hue,
                saturation: saturation * 0.78,
                brightness: min(1, 0.62 + brightness * 0.38),
                alpha: alpha
            )
        })
    }
}

extension Color {
    /// A soft, pale version of a stored colour for a header background: nearly white in light mode,
    /// a deep muted shade in dark mode.
    static func softTint(hex: String) -> Color {
        derived(hex: hex) { hue, saturation, _, isDark in
            isDark
                ? (hue, min(saturation * 0.6, 0.55), 0.30)
                : (hue, min(saturation * 0.2, 0.2), 0.97)
        }
    }

    /// A readable version of a stored colour for text and icons on `softTint`: darker in light mode,
    /// lighter in dark mode.
    static func strongText(hex: String) -> Color {
        derived(hex: hex) { hue, saturation, brightness, isDark in
            isDark
                ? (hue, saturation * 0.45, 0.96)
                : (hue, min(saturation * 1.05, 1), min(brightness, 0.9) * 0.5)
        }
    }

    private static func derived(
        hex: String,
        transform: @escaping (CGFloat, CGFloat, CGFloat, Bool) -> (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        let base = UIColor(Color(hex: hex))
        return Color(uiColor: UIColor { traits in
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            let result = transform(hue, saturation, brightness, traits.userInterfaceStyle == .dark)
            return UIColor(hue: result.0, saturation: result.1, brightness: result.2, alpha: 1)
        })
    }
}

enum ColorPalette {
    /// Colours offered for providers, bills and profiles.
    static let choices = [
        "C4472F", "E8590C", "F59F00", "2E7D32", "00838F",
        "1565C0", "3949AB", "6A1B9A", "C2185B", "5D4037",
    ]
}

/// A row of colour swatches plus a picker for any other colour.
struct ColorChoiceRow: View {
    @Binding var hex: String

    private let columns = [GridItem(.adaptive(minimum: 36, maximum: 44), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(ColorPalette.choices, id: \.self) { choice in
                    Button { hex = choice } label: {
                        Circle()
                            .fill(Color.adaptive(hex: choice))
                            .frame(width: 34, height: 34)
                            .overlay {
                                if choice.caseInsensitiveCompare(hex) == .orderedSame {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Colour \(choice)")
                }
            }

            ColorPicker(
                "Custom colour",
                selection: Binding(get: { Color(hex: hex) }, set: { hex = $0.hexString }),
                supportsOpacity: false
            )
            .font(.outfit(15))
        }
    }
}
