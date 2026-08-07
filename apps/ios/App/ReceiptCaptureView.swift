import SwiftUI
import UIKit
import Vision

/// Receipt capture -- real port of apps/web/app/receipts/new/page.tsx's
/// camera path (task #62). Replaces the old ReceiptScanView.swift entirely
/// (that file showed a hardcoded "Olive Garden Restaurant" fixture with
/// static line items -- no camera, no OCR, no repository wiring at all).
/// See docs/mobile/screen-specs/receipt-scan.md for the documented scope
/// cuts (camera-only, no AI escalation, text-only OCR).
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

    @State private var viewModel = ReceiptCaptureViewModel()
    @State private var showingPicker = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                switch viewModel.stage {
                case .idle:
                    if showingPicker {
                        CameraPicker(
                            onImage: { image in
                                showingPicker = false
                                viewModel.onCaptureStarted()
                                recognizeText(in: image)
                            },
                            onCancel: onCancel
                        )
                        .ignoresSafeArea()
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
                case .error(let message):
                    VStack(spacing: 12) {
                        Text(message).foregroundColor(.white).multilineTextAlignment(.center).padding(.horizontal, 24)
                        Button("Try again") { viewModel.retake(); showingPicker = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel).foregroundColor(.white)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onChange(of: viewModel.savedScanId) { _, newValue in
            if let id = newValue { onScanned(id) }
        }
    }

    private var stageLabel: String {
        switch viewModel.stage {
        case .reading: return "Reading…"
        case .understanding: return "Making sense of it…"
        default: return "Preparing…"
        }
    }

    @ViewBuilder
    private func mismatchCard(reason: String) -> some View {
        VStack(spacing: 14) {
            Text("We couldn't read this cleanly").font(.headline).fontWeight(.bold).foregroundColor(.text)
            Text(viewModel.mismatchMessage(reason)).font(.caption).foregroundColor(.text2).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Edit it myself") { viewModel.editManually() }
                    .buttonStyle(.borderedProminent)
                Button("Retake") { viewModel.retake(); showingPicker = true }
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
            viewModel.onCaptureFailed("Couldn't read that photo.")
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
