import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// The "Scan paper bill" and "Import e-bill" buttons on the Add a bill screen. They read the bill on the
/// device and hand back a draft to check.
struct ScanTiles: View {
    let onResult: (ScanDraft) -> Void

    @State private var showingCamera = false
    @State private var showingFileImporter = false
    @State private var showingPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isReading = false
    @State private var message: String?

    var body: some View {
        HStack(spacing: 12) {
            Button(action: startScan) {
                tile("Scan paper bill", "Camera fills it in", symbol: "doc.viewfinder")
            }
            .buttonStyle(.plain)

            Menu {
                Button("PDF from Files", systemImage: "doc") { showingFileImporter = true }
                // A PhotosPicker placed inside a Menu is torn down when the menu closes, so its sheet never
                // appears. The button only flips a flag, and the picker is presented from outside the menu.
                Button("Photo or screenshot", systemImage: "photo") { showingPhotoPicker = true }
            } label: {
                tile("Import e-bill", "PDF or screenshot", symbol: "square.and.arrow.down")
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if isReading {
                ProgressView("Reading your bill…")
                    .padding(20)
                    .glassSurface(cornerRadius: 18)
            }
        }
        .disabled(isReading)
        .fullScreenCover(isPresented: $showingCamera) {
            DocumentScanner { images in
                showingCamera = false
                guard !images.isEmpty else { return }
                Task { await read(images: images) }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem, matching: .images)
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            Task { await read(pdfAt: url) }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await read(images: [image])
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

    private func tile(_ title: String, _ subtitle: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.title3)
            Text(title).font(.outfit(16, weight: .semibold))
            Text(subtitle).font(.outfit(13)).foregroundStyle(Theme.ink.opacity(0.8))
        }
        .foregroundStyle(Theme.addStrong)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassSurface(cornerRadius: 16)
        .contentShape(.rect)
    }

    // MARK: Reading

    private func startScan() {
        if DocumentScanner.isAvailable {
            showingCamera = true
        } else {
            message = "The document camera isn't available on this device. Use Import e-bill with a photo or PDF instead."
        }
    }

    private func read(images: [UIImage]) async {
        isReading = true
        defer { isReading = false }
        let lines = await TextRecognizer.lines(in: images)
        finish(lines: lines, preview: images.first)
    }

    private func read(pdfAt url: URL) async {
        isReading = true
        defer { isReading = false }
        // Files from the picker need access opened for as long as they're read.
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            message = "That file couldn't be opened."
            return
        }
        let result = await TextRecognizer.readPDF(data)
        finish(lines: result.lines, preview: result.firstPage)
    }

    private func finish(lines: [String], preview: UIImage?) {
        guard !lines.isEmpty else {
            message = "No text could be read. Try a clearer, well-lit photo, or add the bill by hand."
            return
        }
        let scanned = BillTextParser.parse(lines: lines, presets: PresetStore.all)
        onResult(ScanDraft(scanned: scanned, attachment: preview?.attachmentData()))
    }
}
