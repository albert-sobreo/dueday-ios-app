import SwiftUI
import UIKit
import CoreText

// MARK: - Colours

extension Color {
    /// A colour that switches between light and dark appearance. Values are 0xRRGGBB.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Design tokens. Each screen has its own pastel header tint, with a darker variant for dark mode.
enum Theme {
    // Surfaces
    static let background = Color(light: 0xF8F6F2, dark: 0x141311)
    static let card = Color(light: 0xFCFBF8, dark: 0x24211E)
    static let cardBorder = Color(light: 0xE8E4DC, dark: 0x3D3934)
    static let track = Color(light: 0xE4E2DA, dark: 0x3F3B36)

    // Text
    static let ink = Color(light: 0x1B1A17, dark: 0xF7F3EC)
    static let mutedInk = Color(light: 0x6B6960, dark: 0xB8B3A8)

    // Accent
    /// The app's accent is plain black on light backgrounds and white on dark ones.
    static let accent = Color(light: 0x000000, dark: 0xFFFFFF)
    /// Text and icons on a filled accent: white on the black fill, black on the white fill.
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x000000)
    /// A soft neutral background, such as for unselected chips.
    static let accentSoft = Color(light: 0xEBEBEB, dark: 0x2C2C2E)
    /// Selected tab colour.
    static let tabTint = accent
    /// The "on" colour of switches: the standard iOS green, whatever the app's tint is.
    static let toggleOn = Color(uiColor: .systemGreen)

    // Per-screen header tints, plus the strong colour used for text on them. In dark mode the
    // tints are lighter and the text brighter, so there's more contrast with the page.
    static let todayTint = Color(light: 0xE3F0FB, dark: 0x214466)
    static let todayStrong = Color(light: 0x0B3C5D, dark: 0xBFE0FA)
    static let detailTint = Color(light: 0xEFEFEF, dark: 0x2C2C2E)
    static let detailStrong = Color(light: 0x1A1A1A, dark: 0xF2F2F2)
    static let monthTint = Color(light: 0xEEE9FB, dark: 0x382F66)
    static let monthStrong = Color(light: 0x3B2A7A, dark: 0xD9D0FA)
    static let addTint = Color(light: 0xE3F4EA, dark: 0x1F5233)
    static let addStrong = Color(light: 0x14532D, dark: 0xB5EBC8)

    // Selected tile (e.g. the chosen payment method) and chart bars
    static let selected = Color(light: 0x0B3C5D, dark: 0x9CCBEF)
    static let onSelected = Color(light: 0xFFFFFF, dark: 0x0B1B28)
    static let chartBar = Color(light: 0xD9D9D9, dark: 0x4A4A4C)

    // Status. Dark mode uses lighter, brighter shades with deeper fills behind them.
    static let paid = Color(light: 0x2E7D4F, dark: 0x7FE0A8)
    static let paidFill = Color(light: 0xD7EFE0, dark: 0x1F4A33)
    static let warning = Color(light: 0xA85A00, dark: 0xFFC266)
    static let warningFill = Color(light: 0xFCE8C8, dark: 0x4D3510)
    static let danger = Color(light: 0xB3261E, dark: 0xFF9A92)
    static let dangerFill = Color(light: 0xF9D7D3, dark: 0x54231F)
    static let info = Color(light: 0x1565A8, dark: 0x9CD0FF)
    static let infoFill = Color(light: 0xD3E6F7, dark: 0x1F3F5E)
}

// MARK: - Fonts

enum FontRegistrar {
    /// Registers the bundled Barlow Condensed and Outfit fonts. Call once at launch.
    static func registerAll() {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    /// Barlow Condensed for titles, headers, amounts and other narrow text.
    static func barlow(_ size: CGFloat, weight: Font.Weight = .bold, relativeTo style: Font.TextStyle = .title) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "BarlowCondensed-Bold"
        case .semibold: name = "BarlowCondensed-SemiBold"
        case .medium: name = "BarlowCondensed-Medium"
        case .regular: name = "BarlowCondensed-Regular"
        default: name = "BarlowCondensed-Light"
        }
        return .custom(name, size: size, relativeTo: style)
    }

    /// Outfit for regular body text.
    static func outfit(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Outfit", size: size, relativeTo: style).weight(weight)
    }
}

// MARK: - Shared components

/// Small uppercase pill such as "OVERDUE" or "PAID".
struct StatusChip: View {
    let text: String
    let foreground: Color
    let background: Color

    var body: some View {
        Text(text)
            .font(.outfit(11, weight: .bold, relativeTo: .caption))
            .tracking(1.4)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(background, in: .capsule)
    }
}

/// Small uppercase label with wide tracking, used for section captions.
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.mutedInk

    init(_ text: String, color: Color = Theme.mutedInk) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.outfit(12, weight: .semibold, relativeTo: .caption))
            .tracking(1.6)
            .foregroundStyle(color)
    }
}

struct DashedDivider: View {
    var color: Color = Theme.mutedInk.opacity(0.4)

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: 1)
            .overlay {
                GeometryReader { proxy in
                    Path { path in
                        path.move(to: .zero)
                        path.addLine(to: CGPoint(x: proxy.size.width, y: 0))
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
            }
    }
}

extension View {
    /// A surface for cards and tiles: Liquid Glass on iOS 26 and later, a solid card before that.
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat = 20, enabled: Bool = true) -> some View {
        if !enabled {
            self
        } else if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(Theme.card, in: .rect(cornerRadius: cornerRadius))
                .overlay { RoundedRectangle(cornerRadius: cornerRadius).stroke(Theme.cardBorder, lineWidth: 1) }
        }
    }

    /// For screens that draw their own header: no navigation bar, and no bar background or scroll-edge
    /// blur at the top. Otherwise the system briefly reserves space for the bar as you scroll back to
    /// the top, and the content jumps.
    @ViewBuilder
    func ownsTopOfScreen() -> some View {
        if #available(iOS 26.0, *) {
            self
                .toolbar(.hidden, for: .navigationBar)
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                .scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
                .toolbar(.hidden, for: .navigationBar)
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        }
    }

    /// A capsule of Liquid Glass on iOS 26 and later, a material capsule before that.
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .capsule)
        } else {
            self
                .background(.regularMaterial, in: .capsule)
                .overlay { Capsule().stroke(Theme.cardBorder, lineWidth: 1) }
        }
    }

    /// A circle of tinted, interactive Liquid Glass on iOS 26 and later, a solid tinted circle before that.
    @ViewBuilder
    func glassCircle(tint: Color) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint).interactive(), in: .circle)
        } else {
            self.background(tint, in: .circle)
        }
    }

    /// Rounded card used across the app.
    func cardStyle(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .glassSurface(cornerRadius: 20)
    }

    /// Main call-to-action button: tinted Liquid Glass on iOS 26 and later.
    @ViewBuilder
    func primaryButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent).tint(Theme.accent).foregroundStyle(Theme.onAccent)
        } else {
            self.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(Theme.accent)
                .foregroundStyle(Theme.onAccent)
        }
    }

    /// Secondary button: clear Liquid Glass on iOS 26 and later.
    @ViewBuilder
    func secondaryButton(tint: Color = Theme.ink) -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass).tint(tint)
        } else {
            self.buttonStyle(.bordered).buttonBorderShape(.capsule).tint(tint)
        }
    }
}
