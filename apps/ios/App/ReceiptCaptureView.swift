import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Vision
import Factory
import Domain

/// Receipt capture -- real port of apps/web/app/receipts/new/page.tsx's
/// camera path (task #62). Replaces the old ReceiptScanView.swift entirely
/// (that file showed a hardcoded "Olive Garden Restaurant" fixture with
/// static line items -- no camera, no OCR, no repository wiring at all).
/// **Extended 2026-08-28** with the three halves that were missing: the
/// entitlement gate, file upload, and PDF bills. Only the AI escalation is
/// still absent (it needs the image bytes plumbed to an edge function; tracked
/// as its own item).
///
/// The PDF path matters more than it sounds. An emailed bill is the single most
/// accurate input this feature accepts — it has a real text layer, so it skips
/// OCR entirely and is near-perfect where a photograph is a guess. Web treats
/// it as the special case worth having; a camera-only port had thrown away the
/// best input and kept the worst.
///
/// Mirrors Android's ReceiptCaptureScreen.kt.
///
/// Uses `UIImagePickerController` (sourceType `.camera`) rather than a
/// hand-rolled `AVCaptureSession` preview -- this is the first camera
/// feature in the app (verified: no prior AVFoundation code anywhere), and
/// the picker gives the native camera UI, the permission prompt (via
/// `NSCameraUsageDescription`), and an in-memory `UIImage` for free. The
/// photo is handed to Vision and never passed to `UIImageWriteToSavedPhotosAlbum`
/// or any Photos API -- it is never saved, matching the feature's privacy
/// claim more strictly than even web (web's `image_path` column is null;
/// here there is no persistence step to skip in the first place).
struct ReceiptCaptureView: View {
    let onScanned: (String) -> Void
    let onCancel: () -> Void
    /// Web's premium card links to /settings; native routes there the same way.
    var onSeePlans: () -> Void = {}

    @Injected(\.pdfTextExtractor) private var pdfExtractor

    @State private var viewModel = ReceiptCaptureViewModel()
    /// Starts CLOSED. Web's capture screen shows two buttons, not a camera —
    /// auto-opening the camera made "Upload a file" unreachable, which is
    /// exactly how the PDF path went missing in the first place.
    @State private var showingPicker = false
    @State private var showingImporter = false
    /// Kept so the password form can re-read the SAME file — web keeps the
    /// `File` for exactly this reason.
    @State private var pendingPdf: Data?
    @State private var password = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if !viewModel.canScan {
                    // Web shows a plan card rather than letting the request
                    // reach the server and come back rejected. The gate itself
                    // is server-side; this is the courtesy that makes a paid
                    // feature read as paid rather than as broken.
                    premiumCard
                } else {
                    stageBody
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(S.Translation.commonCancel, action: onCancel).foregroundColor(.white)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task { viewModel.watchEntitlement() }
        .onDisappear { viewModel.stopWatching() }
        .fileImporter(
            isPresented: $showingImporter,
            // The same pair web's upload input accepts: any image, plus PDF.
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: false
        ) { outcome in
            handlePickedFile(outcome)
        }
        .onChange(of: viewModel.savedScanId) { _, newValue in
            if let id = newValue { onScanned(id) }
        }
    }

    @ViewBuilder
    private var stageBody: some View {
        Group {
            switch viewModel.stage {
                case .idle:
                    if showingPicker {
                        CameraPicker(
                            onImage: { image in
                                showingPicker = false
                                viewModel.onCaptureStarted()
                                recognizeText(in: image)
                            },
                            onCancel: { showingPicker = false }
                        )
                        .ignoresSafeArea()
                    } else {
                        chooserCard
                    }
                case .preparing, .reading, .understanding:
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text(stageLabel)
                            .foregroundColor(.white)
                            .fontWeight(.semibold)
                    }
                case .mismatch(let reason):
                    mismatchCard(reason: reason)
                case .needsPassword:
                    passwordCard
                case .error(let message):
                    VStack(spacing: 12) {
                        Text(message).foregroundColor(.white).multilineTextAlignment(.center).padding(.horizontal, 24)
                        Button(S.Receipts.captureRetake) { viewModel.retake(); showingPicker = true }
                            .buttonStyle(.borderedProminent)
                    }
            }
        }
    }

    /// Web's two buttons. Shown once the camera sheet is dismissed, so
    /// "Upload a file" is reachable without taking a photo first.
    private var chooserCard: some View {
        VStack(spacing: 16) {
            Text(S.Receipts.captureTitle).font(.headline).foregroundColor(.white)
            Text(S.Receipts.captureIntro)
                .font(.caption).foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button(S.Receipts.captureTakePhoto) { showingPicker = true }
                    .buttonStyle(.borderedProminent)
                // The emailed PDF bill is the most accurate input this feature
                // takes, and a camera-only screen could not accept one at all.
                Button(S.Receipts.captureUpload) { showingImporter = true }
                    .buttonStyle(.bordered)
            }
            Text(S.Receipts.capturePrivacy)
                .font(.caption2).foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    /// Web's plan card, shown instead of the camera on a free plan.
    private var premiumCard: some View {
        VStack(spacing: 12) {
            SanvyaIconView(SanvyaIcons.lock, size: 30, tint: Color.text2)
            Text(S.Receipts.premiumTitle).font(.headline).foregroundStyle(Color.text)
            Text(S.Receipts.premiumBody)
                .font(.subheadline).foregroundStyle(Color.text2)
                .multilineTextAlignment(.center)
            Button(S.Receipts.premiumCta, action: onSeePlans).buttonStyle(.borderedProminent)
        }
        .padding(28)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusLg, style: .continuous))
        .padding(24)
    }

    /// Web's password form for an encrypted PDF.
    private var passwordCard: some View {
        VStack(spacing: 10) {
            Text(S.Receipts.capturePdfPassword).font(.headline).foregroundStyle(Color.text)
            SecureField(S.Receipts.capturePasswordPlaceholder, text: $password)
                .textFieldStyle(.roundedBorder)
            Button(S.Receipts.captureUnlock) {
                guard let data = pendingPdf else { return }
                readPdf(data, password: password)
            }
            .buttonStyle(.borderedProminent)
            .disabled(password.isEmpty)
        }
        .padding(20)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusLg, style: .continuous))
        .padding(24)
    }

    // MARK: - upload

    private func handlePickedFile(_ outcome: Result<[URL], Error>) {
        guard case .success(let urls) = outcome, let url = urls.first else { return }
        viewModel.onUploadStarted()
        // A document-picker URL is security-scoped: without this the read
        // fails with a permission error even though the user just chose it.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            viewModel.onCaptureFailed(S.Receipts.errorsUnsupportedFile)
            return
        }
        if looksLikePdf(data) {
            pendingPdf = data
            readPdf(data, password: nil)
        } else if let image = UIImage(data: data) {
            recognizeText(in: image)
        } else {
            viewModel.onCaptureFailed(S.Receipts.errorsUnsupportedFile)
        }
    }

    private func readPdf(_ data: Data, password: String?) {
        viewModel.onReadingStarted()
        do {
            let glyphs = try pdfExtractor.extract(data: data, password: password)
            viewModel.onPdfText(pdfRowsToText(groupPdfGlyphs(glyphs)))
        } catch PdfExtractionError.passwordRequired {
            viewModel.onPasswordRequired()
        } catch {
            viewModel.onCaptureFailed(S.Receipts.errorsPdfUnreadable)
        }
    }

    private var stageLabel: String {
        switch viewModel.stage {
        case .reading: return S.Receipts.stageReading
        case .understanding: return S.Receipts.stageUnderstanding
        default: return S.Data.preparing
        }
    }

    @ViewBuilder
    private func mismatchCard(reason: String) -> some View {
        VStack(spacing: 14) {
            Text(S.Receipts.captureUnclearTitle).font(.headline).fontWeight(.bold).foregroundColor(.text)
            Text(viewModel.mismatchMessage(reason)).font(.caption).foregroundColor(.text2).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button(S.Receipts.captureEditManually) { viewModel.editManually() }
                    .buttonStyle(.borderedProminent)
                Button(S.Receipts.captureRetake) { viewModel.retake(); showingPicker = true }
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusLg, style: .continuous))
        .padding(24)
    }

    /// On-device OCR (Vision `VNRecognizeTextRequest`, `.accurate`
    /// recognition level). Text-only: joins recognized lines with `\n` and
    /// feeds `parseReceiptText` -- see receipt-scan.md scope note #3 for why
    /// this doesn't build per-word bounding boxes for `groupIntoLines`.
    ///
    /// Bridges Vision's completion-handler API into `async`/`await` via
    /// `withCheckedThrowingContinuation` rather than raw `DispatchQueue.main
    /// .async` callbacks -- this app's Debug config builds under Swift 6
    /// strict concurrency (`SWIFT_VERSION = 6`, project.pbxproj), where a
    /// plain GCD completion closure calling a `@MainActor`-isolated
    /// ViewModel method is a real isolation error, not just a style
    /// preference. A `Task` created here inherits `ReceiptCaptureView`'s
    /// `@MainActor` isolation (SwiftUI's `View` protocol is `@MainActor`),
    /// so `viewModel.onTextRecognized(...)` after the `await` is safe.
    private func recognizeText(in image: UIImage) {
        viewModel.onReadingStarted()
        guard let cgImage = image.cgImage else {
            viewModel.onCaptureFailed(S.Receipts.errorsUnsupportedFile)
            return
        }
        let orientation = cgOrientation(from: image.imageOrientation)
        Task {
            do {
                let text = try await Self.performTextRecognition(cgImage: cgImage, orientation: orientation)
                viewModel.onTextRecognized(text)
            } catch {
                viewModel.onCaptureFailed(error.localizedDescription)
            }
        }
    }

    private static func performTextRecognition(cgImage: CGImage, orientation: CGImagePropertyOrientation) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private func cgOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
    switch orientation {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
}

/// Thin `UIImagePickerController` wrapper, camera-only. No `.editing`, no
/// `allowsEditing` crop step -- one tap from shutter to OCR, matching web's
/// "take photo" flow (no crop step there either).
private struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}

/// `%PDF` — the magic number.
///
/// The UTI from a document picker is not always the file's real type: an
/// attachment saved out of a mail client can arrive typed as plain data. Web
/// never sees this because a browser's file input reports the real type.
/// Sniffing the first four bytes is cheap and it is the difference between
/// reading an emailed bill and telling the user their bill is not supported.
private func looksLikePdf(_ data: Data) -> Bool {
    data.count >= 4 && data[data.startIndex] == 0x25 && data[data.startIndex + 1] == 0x50
        && data[data.startIndex + 2] == 0x44 && data[data.startIndex + 3] == 0x46
}
