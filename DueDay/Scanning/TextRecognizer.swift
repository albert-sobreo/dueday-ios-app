import UIKit
import ImageIO
import Vision
import PDFKit

/// Reads text from photos, screenshots and PDFs, entirely on the device.
enum TextRecognizer {
    /// Text lines from an image in reading order. Words on the same row, like a label and its amount,
    /// are joined into one line.
    nonisolated static func lines(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = cgOrientation(image.imageOrientation)

        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            guard (try? handler.perform([request])) != nil else { return [] }
            return mergeRows(request.results ?? [])
        }.value
    }

    /// Text from every image, in order.
    nonisolated static func lines(in images: [UIImage]) async -> [String] {
        var all: [String] = []
        for image in images {
            all += await lines(in: image)
        }
        return all
    }

    /// Text from a PDF. If its text can't be selected, the pages are an image, so they're read as one.
    /// Also returns the first page as an image to keep with the bill.
    nonisolated static func readPDF(_ data: Data) async -> (lines: [String], firstPage: UIImage?) {
        guard let document = PDFDocument(data: data) else { return ([], nil) }

        var pages: [UIImage] = []
        for index in 0..<min(document.pageCount, 4) {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 0 else { continue }
            let scale = 1600 / bounds.width
            pages.append(page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox))
        }

        let embedded = (0..<min(document.pageCount, 4))
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
        if embedded.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 {
            let lines = embedded.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
            return (lines.filter { !$0.isEmpty }, pages.first)
        }
        return (await self.lines(in: pages), pages.first)
    }

    // MARK: Helpers

    private nonisolated static func cgOrientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: .up
        case .upMirrored: .upMirrored
        case .down: .down
        case .downMirrored: .downMirrored
        case .left: .left
        case .leftMirrored: .leftMirrored
        case .right: .right
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }

    /// Sorts recognised text top to bottom and joins pieces that sit on the same row, left to right.
    private nonisolated static func mergeRows(_ observations: [VNRecognizedTextObservation]) -> [String] {
        let items = observations.compactMap { observation -> (text: String, box: CGRect)? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return (text, observation.boundingBox)
        }
        // Vision's origin is the bottom left, so higher y is nearer the top.
        let sorted = items.sorted { $0.box.midY > $1.box.midY }

        var rows: [[(text: String, box: CGRect)]] = []
        for item in sorted {
            if let last = rows.last?.first, abs(last.box.midY - item.box.midY) < 0.012 {
                rows[rows.count - 1].append(item)
            } else {
                rows.append([item])
            }
        }
        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ")
        }
    }
}

extension UIImage {
    /// A smaller JPEG to keep with a bill: at most 1600 points on the long side.
    nonisolated func attachmentData(maxSide: CGFloat = 1600, quality: CGFloat = 0.7) -> Data? {
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxSide / longest)
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
