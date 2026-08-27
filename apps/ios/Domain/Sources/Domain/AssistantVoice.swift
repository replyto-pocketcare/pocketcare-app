import Foundation

/**
 Dictating to the assistant.

 Ported from `apps/web/src/assistant/MicButton.tsx` and `speech.ts` — the
 decisions, not the engine. Web runs two engines and picks between them: Whisper
 (a model lazy-loaded from a CDN, recording locally and transcribing on-device)
 with the browser's Web Speech API as a fallback. Neither exists on a phone, and
 neither needs to: both platforms ship a speech recogniser that is on-device for
 the common locales and streams partial results, which is what web's two engines
 add up to. So the port is ONE engine per platform behind a protocol, and web's
 `recording` state — the half-second where a blob exists and Whisper has not run
 yet — has no equivalent and is not invented.

 What IS shared is here, because it is exactly the kind of rule two platforms
 drift on: how dictated text joins what the user had already typed, and which
 label the button wears.

 Mirrors Android's AssistantVoice.kt; pinned by `assistant.json`.
 */

/**
 What the mic is doing.

 `.unsupported` hides the button entirely, as web's does — a mic that cannot
 listen is the dead control this codebase keeps deleting. It is a real state
 rather than a nil status because both platforms can only answer "is speech
 available?" asynchronously, after a permission check.
 */
public enum VoiceStatus: String, Sendable, Equatable, CaseIterable {
    case unsupported = "UNSUPPORTED"
    case idle = "IDLE"
    case listening = "LISTENING"

    /**
     Speech has ended and the recogniser is still working.

     iOS reaches this between the tap and the final result; Android between
     `onEndOfSpeech` and `onResults`. Web reaches the same state by a different
     road (Whisper running over a finished recording), which is why the name is
     web's and not either platform's.
     */
    case transcribing = "TRANSCRIBING"
}

/**
 Dictated text, joined to whatever was already in the composer.

 Web's ``base ? `${base} ${t}` : t``, evaluated on EVERY partial result against
 the composer's contents at the moment the mic was tapped — so the dictation
 replaces itself as it grows rather than appending to itself. That "base is
 captured once" part belongs to the caller; this is the join.

 `spoken` is trimmed here. Web trims it one layer up, in `speech.ts`'s `onText`,
 before the join ever sees it; doing it here instead is identical for every
 input web can produce and removes a rule two platforms' recogniser adapters
 would each have had to remember.
 */
public func mergeDictation(base: String, spoken: String) -> String {
    let text = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
    return base.isEmpty ? text : "\(base) \(text)"
}

/**
 The button's accessibility label, as an i18n KEY.

 A key rather than a string, for the same reason `assistantErrorKey` returns
 one: the decision is shared and vector-pinned, the wording is per-locale and
 lives in the catalogue. Web hardcodes all four in English inside
 `MicButton.tsx`, in an app that is otherwise fully translated — see
 PARITY_AUDIT.
 */
public func voiceLabelKey(_ status: VoiceStatus) -> String {
    switch status {
    case .listening: return "micStop"
    case .transcribing: return "micTranscribing"
    default: return "micSpeak"
    }
}

/// Whether the button wears the accent fill and the stop square.
public func voiceActive(_ status: VoiceStatus) -> Bool { status == .listening }

/// Whether a tap does anything. Web disables the button while transcribing.
public func voiceTappable(_ status: VoiceStatus) -> Bool {
    status == .idle || status == .listening
}
