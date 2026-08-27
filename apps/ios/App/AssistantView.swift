import Data
import Domain
import SwiftUI

/**
 The assistant — ported from `apps/web/src/assistant/AssistantChat.tsx`.

 Two views behind one tab, exactly as web has them: a LANDING that starts a chat
 or reopens a saved one, and the CHAT itself. Web keeps both in one component
 because the model conversation, the quota and the pending confirmation have to
 survive moving between them; so does this.

 **What was here was a fabricated conversation** — three hardcoded messages
 including "You've spent ₹6,400 on Food & Dining… 80% of your ₹8,000 monthly
 dining budget", in a styled insight card, over a composer that answered
 nothing. It was replaced by an honest placeholder in August and is replaced by
 the real thing here.

 What is NOT here, and why:

  * **The credit-pack purchase.** Web's out-of-quota card offers three Razorpay
    top-ups. There is no in-app purchase flow anywhere in this app yet, so the
    card states the situation and stops rather than showing three buttons that
    cannot charge anyone. In ABSENT-BY-DECISION.
  * **Voice input.** `speech.ts` + `MicButton.tsx` are a separate port with
    their own permission story. Also in ABSENT-BY-DECISION.

 Mirrors Android's AssistantScreen.kt.
 */
struct AssistantView: View {
    /// The shell's current tab, so a `<ui>` action's href can move the app.
    @Binding var currentTab: NavTab
    /// A group id an action deep-linked to, handed on to `SplitsView`.
    @Binding var openGroupId: String?
    /// Filters an action deep-linked to, handed on to `SearchView`.
    @Binding var searchPrefill: SearchPrefill?

    @State private var viewModel = AssistantViewModel()
    @State private var input = ""
    @State private var payloadOpen = false
    @State private var confirmDeleteId: String?
    @State private var disclaimerOpen = false

    var body: some View {
        Group {
            // Nothing at all until the entitlement has been read once. The gate
            // and the chat are mutually exclusive, so rendering either on a
            // guess means the wrong one flashes on every open.
            if !viewModel.entitlementKnown {
                Color.clear
            } else if !viewModel.isPaid {
                premiumGate
            } else if viewModel.view == .landing {
                ScrollView { landing.padding(.horizontal, 16) }
            } else {
                chat
            }
        }
        .background(Color.bg.ignoresSafeArea())
        .task {
            viewModel.start()
            disclaimerOpen = !AiDisclaimer.read()
        }
        .onDisappear { viewModel.cancel() }
    }

    // MARK: - premium gate

    /// Web's `!isPremiumUser && !hasActiveTrial` branch.
    private var premiumGate: some View {
        ScrollView {
            SanvyaPage(S.Assistant.title) {
                SanvyaCard(padding: 28) {
                    VStack(spacing: 12) {
                        // Web draws its own stroked padlock; this is the
                        // Material Symbol of the same name, already in the
                        // bundled subset.
                        SanvyaIconView(SanvyaIcons.lock, size: 30, tint: Color.text2)
                        SanvyaH2(S.Assistant.premiumFeature)
                        SanvyaMuted(S.Assistant.premiumBody)
                            .multilineTextAlignment(.center)
                        SanvyaButton(action: { currentTab = .settings }) {
                            Text(S.Assistant.goPremium)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - landing

    private var landing: some View {
        SanvyaPage(S.Assistant.title) {
            quotaChip
            SanvyaChip(S.Assistant.help, isActive: false) { currentTab = .help }
        } content: {
            SanvyaMuted(S.Assistant.landingIntro, style: SanvyaType.body.resized(13))

            if let reset = viewModel.quota?.resetDate, !reset.isEmpty {
                SanvyaMuted(
                    S.Assistant.quotaResets(date: shortDateLabel(reset)),
                    style: SanvyaType.body.resized(12)
                )
            }

            SanvyaButton(action: { viewModel.newChat(greeting: S.Assistant.greeting) }) {
                SanvyaIconView(SanvyaIcons.autoAwesome, size: 16, tint: .white)
                Text(S.Assistant.startChat)
            }

            SanvyaCard {
                VStack(alignment: .leading, spacing: 8) {
                    SanvyaMuted(S.Assistant.continueConversation, style: SanvyaType.body.resized(12))
                    if viewModel.threads.isEmpty {
                        SanvyaMuted(S.Assistant.noChats, style: SanvyaType.body.resized(13))
                    }
                    ForEach(viewModel.threads, id: \.id) { thread in
                        HStack(spacing: 8) {
                            Button { viewModel.openThread(id: thread.id) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text((thread.title?.isEmpty == false ? thread.title! : S.Assistant.untitledChat))
                                        .sanvyaStyle(SanvyaType.body)
                                        .foregroundStyle(Color.text)
                                        .multilineTextAlignment(.leading)
                                    Text(shortDateLabel(thread.updatedAt))
                                        .sanvyaStyle(SanvyaType.body.resized(11))
                                        .foregroundStyle(Color.text2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .overlay {
                                    RoundedRectangle(cornerRadius: SanvyaRadius.radiusSm, style: .continuous)
                                        .strokeBorder(Color.border, lineWidth: 1)
                                }
                            }
                            .buttonStyle(SanvyaPressStyle())

                            Button { confirmDeleteId = thread.id } label: {
                                SanvyaIconView(SanvyaIcons.close, size: 18, tint: Color.text2)
                                    .padding(6)
                            }
                            .accessibilityLabel(S.Assistant.deleteChatAria)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .confirmationDialog(
            S.Assistant.deleteChatTitle,
            isPresented: Binding(get: { confirmDeleteId != nil }, set: { if !$0 { confirmDeleteId = nil } }),
            titleVisibility: .visible
        ) {
            Button(S.Translation.commonDelete, role: .destructive) {
                if let id = confirmDeleteId { viewModel.deleteThread(id: id) }
                confirmDeleteId = nil
            }
            Button(S.Translation.commonCancel, role: .cancel) { confirmDeleteId = nil }
        } message: {
            Text(S.Assistant.deleteChatMsg)
        }
    }

    // MARK: - chat

    private var chat: some View {
        VStack(spacing: 0) {
            // Header: back to the thread list on the left, quota + new chat on
            // the right. Stays put while the transcript below scrolls.
            HStack(spacing: 8) {
                SanvyaChip(S.Assistant.chats, isActive: false) { viewModel.backToLanding() }
                Spacer(minLength: 0)
                quotaChip
                SanvyaChip(S.Assistant.newChat, isActive: false) {
                    viewModel.newChat(greeting: S.Assistant.greeting)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        payloadPanel
                        ForEach(viewModel.bubbles) { bubble in
                            bubbleView(bubble)
                        }
                        suggestions
                        statusBlock
                        // The scroll anchor. Web keeps an empty `endRef` div at
                        // the foot of the thread for exactly this.
                        Color.clear.frame(height: 1).id(chatBottomId)
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: viewModel.bubbles.count) { _, _ in scrollToEnd(proxy) }
                .onChange(of: viewModel.busy) { _, _ in scrollToEnd(proxy) }
                .onChange(of: viewModel.pendingTool) { _, _ in scrollToEnd(proxy) }
            }

            composer
        }
        .sanvyaModal(isPresented: $disclaimerOpen, label: S.Assistant.privacyTitle) {
            VStack(alignment: .leading, spacing: 16) {
                SanvyaH2(S.Assistant.privacyTitle)
                SanvyaMuted(S.Assistant.privacyBody)
                HStack {
                    Spacer(minLength: 0)
                    SanvyaButton(action: ackDisclaimer) { Text(S.Assistant.understand) }
                }
            }
        }
        .onChange(of: disclaimerOpen) { _, open in if !open { AiDisclaimer.mark() } }
    }

    private let chatBottomId = "assistant-thread-end"

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation { proxy.scrollTo(chatBottomId, anchor: .bottom) }
    }

    private func ackDisclaimer() {
        AiDisclaimer.mark()
        disclaimerOpen = false
    }

    @ViewBuilder
    private var payloadPanel: some View {
        if let payload = viewModel.payload, !payload.isEmpty {
            SanvyaCard(padding: 14, background: Color.surface2) {
                VStack(alignment: .leading, spacing: 8) {
                    Button { payloadOpen.toggle() } label: {
                        SanvyaMuted(S.Assistant.viewData, style: SanvyaType.body.resized(12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if payloadOpen {
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(payload)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.text2)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bubbleView(_ bubble: ChatBubble) -> some View {
        switch bubble.role {
        case "action":
            SanvyaMuted(bubble.text, style: SanvyaType.body.resized(13))
        case "user":
            HStack {
                Spacer(minLength: 0)
                SanvyaCard(padding: 12, background: Color.accent) {
                    Text(bubble.text)
                        .sanvyaStyle(SanvyaType.body)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: 300, alignment: .trailing)
            }
        default:
            assistantBubble(bubble.text)
        }
    }

    /// An assistant turn: markdown prose, then the `<ui>` block if there was one.
    @ViewBuilder
    private func assistantBubble(_ raw: String) -> some View {
        let split = splitAssistantUi(raw)
        let ui = parseAssistantUiPayload(split.json)
        VStack(alignment: .leading, spacing: 10) {
            if !split.text.isEmpty {
                SanvyaCard(padding: 12) { AssistantMarkdownView(text: split.text) }
            }
            if let ui {
                AssistantUiBlockView(ui: ui, onSend: send, onOpen: open, enabled: canSend)
            }
        }
        .frame(maxWidth: ui == nil ? 320 : .infinity, alignment: .leading)
    }

    /// The suggestion chips ride along with the greeting until the first user
    /// turn, then never come back.
    @ViewBuilder
    private var suggestions: some View {
        if !viewModel.bubbles.contains(where: { $0.role == "user" }) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(S.Assistant.suggestions, id: \.self) { suggestion in
                    Button { send(suggestion) } label: {
                        Text(suggestion)
                            .sanvyaStyle(SanvyaType.body)
                            .foregroundStyle(Color.text)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusSm, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: SanvyaRadius.radiusSm, style: .continuous)
                                    .strokeBorder(Color.border, lineWidth: 1)
                            }
                    }
                    .buttonStyle(SanvyaPressStyle())
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.45)
                }
            }
            .frame(maxWidth: 320, alignment: .leading)
        }
    }

    @ViewBuilder
    private var statusBlock: some View {
        if viewModel.busy {
            SanvyaMuted(S.Assistant.thinking, style: SanvyaType.body.resized(13))
        }

        if viewModel.isOutOfQuota {
            SanvyaCard(background: Color.accentGhost) {
                // Web branches on the same `isPaid` its premium gate uses, so
                // the free copy below is unreachable there too — kept because
                // the branch is web's, and the day the gate loosens the right
                // words are already here.
                if viewModel.isPaid {
                    Text(S.Assistant.outPaidBold)
                        .sanvyaStyle(SanvyaType.body.weighted(700))
                        .foregroundStyle(Color.text)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(S.Assistant.outFreeBold)
                            .sanvyaStyle(SanvyaType.body.weighted(700))
                            .foregroundStyle(Color.text)
                        SanvyaMuted(S.Assistant.outFreeRest)
                        SanvyaButton(action: { currentTab = .settings }) {
                            Text(S.Assistant.seePlans)
                        }
                    }
                }
            }
        }

        if let tool = viewModel.pendingTool {
            SanvyaCard(background: Color.accentGhost) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(S.Assistant.confirmAction)
                        .sanvyaStyle(SanvyaType.body.weighted(700))
                        .foregroundStyle(Color.text)
                    Text(viewModel.describePending(tool))
                        .sanvyaStyle(SanvyaType.body)
                        .foregroundStyle(Color.text)
                    HStack(spacing: 8) {
                        SanvyaButton(action: { viewModel.resolvePending(confirmed: true, errorText: errorText) }) {
                            Text(S.Assistant.confirm)
                        }
                        SanvyaChip(S.Assistant.skip, isActive: false) {
                            viewModel.resolvePending(confirmed: false, errorText: errorText)
                        }
                    }
                }
            }
        }
    }

    // MARK: - composer

    /**
     A pill holding a growing text field and a round send button.

     Multiline and Return-inserts-a-newline, as web's textarea is — there is no
     "Return sends" on either platform, because a phone keyboard's return key is
     how you write a second sentence.
     */
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 0) {
            HStack(alignment: .bottom, spacing: 2) {
                TextField(S.Assistant.composerPlaceholder, text: $input, axis: .vertical)
                    .lineLimit(1...6)
                    .sanvyaStyle(SanvyaType.body)
                    .foregroundStyle(Color.text)
                    .tint(Color.accent)
                    .textFieldStyle(.plain)
                    .disabled(viewModel.busy)
                    .padding(.vertical, 9)

                Button { sendComposed() } label: {
                    SanvyaArrowUpIconView(
                        size: 19,
                        tint: canSendComposed ? .white : Color.text3
                    )
                    .frame(width: 40, height: 40)
                    .background(canSendComposed ? Color.accent : Color.surface2)
                    .clipShape(Circle())
                }
                .disabled(!canSendComposed)
                .accessibilityLabel(S.Assistant.sendAria)
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .background(Color.surface)
            .clipShape(Capsule())
            .overlay { Capsule().strokeBorder(Color.borderStrong, lineWidth: 1) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - plumbing

    private var canSend: Bool {
        !viewModel.busy && viewModel.pendingTool == nil && !viewModel.isOutOfQuota
    }

    private var canSendComposed: Bool {
        canSend && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendComposed() {
        let text = input
        input = ""
        send(text)
    }

    private func send(_ text: String) {
        viewModel.send(text, errorText: errorText)
    }

    /**
     A `<ui>` action's href, resolved.

     `parseAppLink` has already refused anything that is not an in-app
     destination, and `destination(for:)` maps what survives onto this app's own
     tabs — so an action either moves the app or was never offered.
     */
    private func open(_ href: String) {
        guard let link = parseAppLink(href), let destination = appDestination(for: link) else { return }
        if let groupId = destination.groupId { openGroupId = groupId }
        if let prefill = destination.searchPrefill { searchPrefill = prefill }
        currentTab = destination.tab
    }

    /**
     The i18n key `assistantErrorKey` returns, resolved.

     Domain returns a key rather than a string so the decision stays
     vector-pinned and the wording stays in the catalogue — neither of which a
     Domain module that formatted the sentence itself could manage.
     */
    private func errorText(_ key: String, _ raw: String) -> String {
        switch key {
        case "errNotConfigured": return S.Assistant.errNotConfigured
        case "errModel": return S.Assistant.errModel
        case "errNetwork": return S.Assistant.errNetwork
        // The only key that interpolates. Web passes the raw provider message
        // through unchanged, on the grounds that "something went wrong" with no
        // detail is not something anyone can act on.
        case "errGeneric": return S.Assistant.errGeneric(err: raw)
        default: return S.Assistant.errDefault
        }
    }

    /**
     The quota chip — `3 / 50 +12 credits queries`.

     Web writes `background: isOutOfQuota ? "var(--negative-ghost)" : "var(--surface-2)"`,
     and **`--negative-ghost` is not defined anywhere in `globals.css`** — the
     only other use of it, in `SecurityPanel.tsx`, carries an inline fallback,
     which says someone already knew. An undefined custom property makes the
     whole declaration invalid, so on web the out-of-quota chip silently keeps
     `.chip`'s own surface rather than turning red. That is reproduced here
     rather than "fixed": the token belongs in web's stylesheet, and inventing a
     colour on the phone would make the two clients disagree about a state the
     user can see. Recorded in PARITY_AUDIT as a web defect.
     */
    @ViewBuilder
    private var quotaChip: some View {
        if let quota = viewModel.quota {
            // `String(quota.purchased)`, not the Int: a non-plural argument is
            // emitted as `%@`, and `String(format:)` reads that as an object
            // pointer. An Int passed there is undefined behaviour, not a number.
            let suffix = quota.purchased > 0 ? S.Assistant.creditsSuffix(n: String(quota.purchased)) : ""
            Text("\(quota.planLeft) / \(quota.total)\(suffix) \(S.Assistant.queries)")
                .sanvyaStyle(SanvyaType.chip.resized(11))
                .lineLimit(1)
                .foregroundStyle(Color.text)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(quota.left <= 0 ? Color.surface : Color.surface2)
                .clipShape(Capsule())
                .overlay { Capsule().strokeBorder(Color.border, lineWidth: 1) }
        }
    }
}

/**
 The assistant's privacy notice has been read.

 Same key and same stored value ("true") as web's localStorage entry. It gates a
 modal that appears on the FIRST chat, so it is per-device by design on all
 three clients — a notice about what leaves this device is one this device
 should show once.
 */
enum AiDisclaimer {
    private static let key = "sanvya:ai-disclaimer"

    static func read(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: key) == "true"
    }

    static func mark(_ defaults: UserDefaults = .standard) {
        defaults.set("true", forKey: key)
    }
}
