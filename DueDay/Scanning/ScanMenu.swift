import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Turns a photo, scan or PDF into what could be read from it, entirely on the device.
enum BillReader {
    static func read(images: [UIImage]) async -> ScanDraft? {
        let lines = await TextRecognizer.lines(in: images)
        return draft(lines: lines, preview: images.first)
    }

    static func read(pdfData data: Data) async -> ScanDraft? {
        let result = await TextRecognizer.readPDF(data)
        return draft(lines: result.lines, preview: result.firstPage)
    }

    /// Nil when there was no text to read.
    private static func draft(lines: [String], preview: UIImage?) -> ScanDraft? {
        guard !lines.isEmpty else { return nil }
        let scanned = BillTextParser.parse(lines: lines, presets: PresetStore.all)
        return ScanDraft(scanned: scanned, attachment: preview?.attachmentData())
    }
}

/// A button that offers the camera, a PDF or a photo, reads the bill, and hands back what it found.
/// The label is yours, so it can look like any button.
struct ScanMenu<MenuLabel: View>: View {
    let onResult: (ScanDraft) -> Void
    @ViewBuilder let label: () -> MenuLabel

    @State private var showingCamera = false
    @State private var showingFileImporter = false
    @State private var showingPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isReading = false
    @State private var message: String?

    var body: some View {
        Menu {
            Button("Scan with camera", systemImage: "doc.viewfinder", action: startScan)
            Button("PDF from Files", systemImage: "doc") { showingFileImporter = true }
            // A PhotosPicker placed inside a Menu is torn down when the menu closes, so its sheet never
            // appears. The button only flips a flag, and the picker is presented from outside the menu.
            Button("Photo or screenshot", systemImage: "photo") { showingPhotoPicker = true }
        } label: {
            label()
        }
        .disabled(isReading)
        .overlay {
            if isReading { ProgressView() }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            DocumentScanner { images in
                showingCamera = false
                guard !images.isEmpty else { return }
                Task { await finish(await BillReader.read(images: images)) }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem, matching: .images)
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            Task { await readPDF(at: url) }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await finish(await BillReader.read(images: [image]))
                } else {
                    message = "That photo couldn't be opened."
                }
                photoItem = nil
            }
        }
        .alert("DueDay", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func startScan() {
        if DocumentScanner.isAvailable {
            showingCamera = true
        } else {
            message = "The document camera isn't available on this device. Choose a photo or PDF instead."
        }
    }

    private func readPDF(at url: URL) async {
        isReading = true
        // Files from the picker need access opened for as long as they're read.
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            isReading = false
            message = "That file couldn't be opened."
            return
        }
        await finish(await BillReader.read(pdfData: data))
    }

    private func finish(_ draft: ScanDraft?) async {
        isReading = false
        guard let draft else {
            message = "No text could be read. Try a clearer, well-lit photo."
            return
        }
        onResult(draft)
    }
}
