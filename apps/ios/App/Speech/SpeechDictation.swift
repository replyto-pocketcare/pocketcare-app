import AVFoundation
import Foundation
import Speech

/**
 Why dictation ended badly.

 Only the two the UI reacts to differently are named. Everything else is
 `.other`: web's `onError` handler does not branch either — it returns the
 button to idle and leaves the composer alone, on the reasoning that a failed
 dictation the user can simply retry does not deserve an error message.

 Mirrors Android's `SpeechError`.
 */
enum SpeechError: Equatable {
    case permissionDenied
    case noMatch
    case other
}

/**
 Live dictation, behind a protocol.

 The protocol exists for the same reason `PdfTextExtracting`'s does: the thing
 behind it can be unavailable at runtime and that must not be a crash. A device
 with no recogniser for the current locale, or one where the user refused
 speech recognition, reports unavailable and the mic button is then not drawn at
 all rather than drawn and dead — which is exactly what web does when
 `voiceSupported()` is false.

 Mirrors Android's `SpeechDictation`.
 */
@MainActor
protocol SpeechDictating: AnyObject {
    /// False means: do not draw the button.
    func isAvailable() -> Bool

    /**
     Ask for whatever has not been granted yet.

     Separate from `start` because iOS needs TWO grants — speech recognition and
     the microphone — and asking for both in sequence is a two-dialog flow that
     belongs in one place. Returns nil on success, or why it failed.
     */
    func requestAuthorization() async -> SpeechError?

    /**
     Begin listening.

     `onPartial` fires repeatedly with the best guess so far; `onFinal` once with
     the recogniser's answer; `onDone` exactly once, whatever happened, so the
     caller can return to idle from one place. `onSpeechEnded` marks the gap
     where the recogniser has stopped hearing and has not answered yet — web
     calls that state "transcribing".
     */
    func start(
        onPartial: @escaping (String) -> Void,
        onSpeechEnded: @escaping () -> Void,
        onFinal: @escaping (String) -> Void,
        onDone: @escaping (SpeechError?) -> Void
    )

    /// Stop listening and take whatever has been heard. Web's `rec.stop()`.
    func stop()

    /// Stop listening and discard. Web's `rec.abort()`.
    func cancel()
}

/**
 `SFSpeechRecognizer` over `AVAudioEngine`.

 On-device is PREFERRED, not required. `requiresOnDeviceRecognition` never
 leaves the phone but is only supported for languages the device has downloaded,
 and returns an error for the rest; asking for it only when
 `supportsOnDeviceRecognition` says yes gets the private path where it exists
 and the server path where it does not. Web's own comment makes the same trade
 in the other direction — it prefers Whisper "private default" and falls back to
 a browser service that may be remote. Privacy that turns dictation off for most
 of the world is not the choice this product makes.

 Everything here is `@MainActor`: `SFSpeechRecognizer`'s callbacks arrive on an
 arbitrary queue, so each one hops back before touching state or calling the
 handlers, which run inside SwiftUI.
 */
@MainActor
final class PlatformSpeechDictation: SpeechDictating {
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finished = false
    /// Held so `stop()` can announce the gap between "stopped hearing" and
    /// "answered" — the state web calls transcribing. Android gets that moment
    /// from the platform (`onEndOfSpeech`); here the tap IS the moment.
    private var speechEndedHandler: (() -> Void)?

    func isAvailable() -> Bool {
        // `isAvailable` is false while the device is offline AND the locale has
        // no on-device model — the same condition web's `voiceSupported()`
        // stands in for, and the one that decides whether the button exists.
        guard let recognizer else { return false }
        return recognizer.isAvailable
    }

    func requestAuthorization() async -> SpeechError? {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status) }
        }
        guard speech == .authorized else { return .permissionDenied }

        let mic = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in continuation.resume(returning: granted) }
        }
        return mic ? nil : .permissionDenied
    }

    func start(
        onPartial: @escaping (String) -> Void,
        onSpeechEnded: @escaping () -> Void,
        onFinal: @escaping (String) -> Void,
        onDone: @escaping (SpeechError?) -> Void
    ) {
        teardown()
        finished = false
        speechEndedHandler = onSpeechEnded

        // `finished` guards a real double-callback: a task that errors AFTER
        // delivering a final result calls the handler twice, and letting the
        // second one through would take the button out of a state the first had
        // already left.
        func finish(_ error: SpeechError?) {
            guard !finished else { return }
            finished = true
            teardown()
            onDone(error)
        }

        guard let recognizer, recognizer.isAvailable else {
            finish(.other)
            return
        }

        let audioRequest = SFSpeechAudioBufferRecognitionRequest()
        audioRequest.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { audioRequest.requiresOnDeviceRecognition = true }
        request = audioRequest

        do {
            let session = AVAudioSession.sharedInstance()
            // `.duckOthers` rather than interrupting: dictating one sentence
            // into a composer should quieten a podcast, not stop it.
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                audioRequest.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            finish(.other)
            return
        }

        task = recognizer.recognitionTask(with: audioRequest) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        onFinal(text)
                        finish(nil)
                        return
                    }
                    onPartial(text)
                }
                if error != nil {
                    // Everything that goes wrong AFTER authorisation lands here
                    // and is treated alike, as web treats its own `onError`:
                    // return to idle, leave the composer alone. The commonest
                    // by far is "no speech detected", which the recogniser
                    // reports as an error rather than an empty result and which
                    // is not worth a message — the user tapped the mic and said
                    // nothing.
                    finish(.noMatch)
                }
            }
        }
    }

    func stop() {
        // `endAudio`, not `cancel`: this is the tap that means "I've finished
        // speaking, transcribe it", so the recogniser must be allowed to
        // deliver a final result. Web's `rec.stop()` has the same contract.
        guard !finished else { return }
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        speechEndedHandler?()
    }

    func cancel() {
        task?.cancel()
        teardown()
    }

    private func teardown() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request = nil
        task = nil
        speechEndedHandler = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
