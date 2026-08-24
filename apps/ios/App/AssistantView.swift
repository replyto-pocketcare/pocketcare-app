import SwiftUI

/// Sanvya AI assistant.
///
/// **What was here was a fabricated conversation.** Three hardcoded chat
/// messages — including "You've spent ₹6,400 on Food & Dining in July 2026
/// across 14 transactions. That's 80% of your ₹8,000 monthly dining budget",
/// rendered in a styled insight card with a progress figure — plus a composer
/// that appended whatever you typed to a local array and answered nothing.
///
/// Invented figures are the worst thing to leave in a finance app. They are not
/// obviously fake: they are plausible, specific, currency-formatted, and sit
/// exactly where a real answer would. A user reading that would have no way to
/// know their dining budget had not been consulted.
///
/// The real assistant is a substantial port and is not started: web's is
/// ~1,670 lines across `AssistantChat.tsx` (the streaming chat), `tools.ts`
/// (the LLM tool surface over the ledger), `richMessage.tsx` (insight cards),
/// `summary.ts` (the context it sends) and `speech.ts` + `MicButton.tsx`
/// (on-device voice — note the earlier audit claim that "web has no voice
/// input" was wrong).
///
/// Until then this says so, using the same honest placeholder Search and Help
/// already use. See `docs/mobile/ABSENT-BY-DECISION.md`.
struct AssistantView: View {
    var body: some View { PlaceholderView(title: S.Translation.navAssistant) }
}
