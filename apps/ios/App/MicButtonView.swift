import Domain
import SwiftUI

/**
 The composer's mic — ported from `apps/web/src/assistant/MicButton.tsx`.

 Tap to start, tap to stop. Web's own summary of the behaviour, kept: "Inserts
 text into the composer — the assistant still replies in text."

 Three things it does NOT do, each on purpose:

  * **It draws nothing when there is no recogniser.** Web returns `null` for
    `status === "unsupported"`; so does this. A mic that cannot listen is a dead
    control.
  * **It does not ask for the microphone until tapped.** Web cannot ask early
    either — `getUserMedia` prompts on use — and two permission dialogs on the
    way into a chat screen are a worse first impression than two on the way into
    dictation.
  * **It says nothing when a dictation fails.** Web's `onError` returns the
    button to idle and leaves the composer alone. The one exception is a REFUSED
    permission, which is not a failure the user can retry their way out of —
    that one gets a line, because the fix is in Settings and nothing else on
    this screen would ever say so.

 Mirrors Android's MicButton.kt.
 */
struct MicButtonView: View {
    @Binding var value: String
    let enabled: Bool
    let onDenied: (String) -> Void

    @State private var dictation = PlatformSpeechDictation()
    @State private var status: VoiceStatus = .idle
    @State private var supportChecked = false
    /// The composer's contents at the moment the mic was tapped. Web captures
    /// the same thing in `baseRef` and merges against it on every partial, so
    /// the dictation replaces itself as it grows instead of appending to itself.
    @State private var base = ""
    @State private var pulsing = false

    var body: some View {
        Group {
            if status == .unsupported {
                EmptyView()
            } else {
                button
            }
        }
        .onAppear {
            guard !supportChecked else { return }
            supportChecked = true
            status = dictation.isAvailable() ? .idle : .unsupported
        }
        .onDisappear { dictation.cancel() }
    }

    private var button: some View {
        Button(action: tapped) {
            ZStack {
                Circle()
                    .fill(voiceActive(status) ? Color.accent : Color.clear)
                icon
            }
            .frame(width: 40, height: 40)
            // Web's `micPulse` keyframes: a 1.4s ring that grows and fades.
            // SwiftUI has no box-shadow, so the pulse is the button itself
            // breathing — the same 1.4s, the same ease-in-out, and the same
            // "only while active".
            .scaleEffect(pulsing && voiceActive(status) ? 1.08 : 1)
            .animation(
                voiceActive(status)
                    ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                    : .default,
                value: pulsing
            )
        }
        .buttonStyle(SanvyaPressStyle())
        .disabled(!enabled || !voiceTappable(status))
        .accessibilityLabel(micLabel)
        .onChange(of: status) { _, new in pulsing = voiceActive(new) }
    }

    @ViewBuilder
    private var icon: some View {
        switch status {
        // Web shows a percentage while Whisper downloads and runs. There is no
        // download here and no progress to report, so it shows the ellipsis web
        // falls back to when it has no number either.
        case .transcribing:
            Text(verbatim: "…")
                .sanvyaStyle(SanvyaType.chip)
                .foregroundStyle(Color.text2)
        case .listening:
            // Web's stop indicator: a 12pt white square with a 3pt radius.
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.white)
                .frame(width: 12, height: 12)
        default:
            SanvyaMicIconView(size: 19, tint: Color.text2)
        }
    }

    private var micLabel: String {
        switch voiceLabelKey(status) {
        case "micStop": return S.Assistant.micStop
        case "micTranscribing": return S.Assistant.micTranscribing
        default: return S.Assistant.micSpeak
        }
    }

    private func tapped() {
        switch status {
        case .idle:
            Task {
                if let error = await dictation.requestAuthorization() {
                    if error == .permissionDenied { onDenied(S.Assistant.micDenied) }
                    return
                }
                begin()
            }
        case .listening:
            // Set here as well as from the engine: the tap IS the moment speech
            // ended, and waiting for a callback would leave the button on
            // LISTENING while the recogniser finishes.
            status = .transcribing
            dictation.stop()
        default:
            break
        }
    }

    private func begin() {
        base = value
        status = .listening
        dictation.start(
            onPartial: { value = mergeDictation(base: base, spoken: $0) },
            onSpeechEnded: { if status == .listening { status = .transcribing } },
            onFinal: { value = mergeDictation(base: base, spoken: $0) },
            onDone: { error in
                status = .idle
                if error == .permissionDenied { onDenied(S.Assistant.micDenied) }
            }
        )
    }
}
