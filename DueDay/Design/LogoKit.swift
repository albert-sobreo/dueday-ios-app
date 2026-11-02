import SwiftUI
import PhotosUI
import UIKit

enum LogoProcessing {
    /// Shrinks an image so logos stay small to store and sync. The whole logo is kept, with its own
    /// shape and transparency: nothing is cropped, and no background is added.
    static func squareLogoData(from data: Data, side: CGFloat = 256) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        // Fit the longest side to `side`, but never enlarge a small image.
        let scale = min(1, side / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false   // keeps transparent areas transparent
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        // PNG keeps the transparency of logos that have it.
        return rendered.pngData()
    }
}

/// Decoded logos, kept so a list doesn't decode every picture again each time it redraws.
enum LogoImageCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for data: Data) -> UIImage? {
        // A cheap key: the size and a few bytes from each end. Logos are small PNGs, so this tells
        // different pictures apart without reading all of the data.
        let key = "\(data.count)-\(data.prefix(24).hashValue)-\(data.suffix(24).hashValue)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = UIImage(data: data) else { return nil }
        // Decode now, on first use, rather than while scrolling.
        let prepared = image.preparingForDisplay() ?? image
        cache.setObject(prepared, forKey: key)
        return prepared
    }
}

/// A provider's icon: the user's uploaded logo if there is one, otherwise a symbol on a tint.
struct LogoBadge: View {
    var logo: Data?
    let symbol: String
    let color: Color
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let logo, let image = LogoImageCache.image(for: logo) {
                // The logo as it is: fitted, never cropped, with no background behind it, so a
                // transparent PNG stays transparent.
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: size, height: size)
                    .background(color.opacity(0.16))
            }
        }
        .clipShape(.rect(cornerRadius: size * 0.27))
        .accessibilityHidden(true)
    }
}

/// Pick a logo from the photo library, preview it, and remove it.
struct LogoPickerRow: View {
    @Binding var logoData: Data?
    let symbol: String
    let color: Color

    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        HStack(spacing: 14) {
            LogoBadge(logo: logoData, symbol: symbol, color: color, size: 64)

            VStack(alignment: .leading, spacing: 8) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(logoData == nil ? "Upload logo" : "Change logo", systemImage: "photo")
                        .font(.outfit(15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 40)
                        .background(Theme.accent.opacity(0.1), in: .capsule)
                }
                if logoData != nil {
                    Button("Remove logo", role: .destructive) { logoData = nil }
                        .font(.outfit(14))
                        .foregroundStyle(Theme.danger)
                }
            }
            Spacer(minLength: 0)
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let logo = LogoProcessing.squareLogoData(from: data) {
                    logoData = logo
                }
                pickerItem = nil
            }
        }
    }
}
