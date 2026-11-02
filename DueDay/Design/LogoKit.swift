import SwiftUI
import PhotosUI
import UIKit

enum LogoProcessing {
    /// Crops an image to a square and shrinks it, so logos stay small to store and sync.
    static func squareLogoData(from data: Data, side: CGFloat = 256) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { _ in
            // Scale to fill the square, centred, then let the renderer crop the overflow.
            let scale = max(side / image.size.width, side / image.size.height)
            let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(
                x: (side - drawn.width) / 2, y: (side - drawn.height) / 2,
                width: drawn.width, height: drawn.height
            ))
        }
        // PNG keeps the transparency of logos that have it.
        return rendered.pngData()
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
            if let logo, let image = UIImage(data: logo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .background(Color.white)
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
