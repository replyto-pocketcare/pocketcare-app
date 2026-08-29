import SwiftUI

/**
 "Ask Sanvya" on the wide-window dashboard — a card that opens into a docked chat
 panel. A port of `apps/web/src/ui/desktop/AssistantWidget.tsx`.

 **Asking never leaves the dashboard**, which is the whole point of the widget
 and the reason it is not simply a link to the Assistant tab. The panel mounts
 the app's REAL assistant view — threads, tools, quota, confirmations — so there
 is still exactly one chat implementation; it is embedded here rather than
 navigated to. The collapsed card is only a launcher: whatever you type or tap on
 it becomes the panel's opening question.

 THREE deliberate divergences from web, all recorded rather than hidden:

  * Web's card MORPHS into the panel with a shared `layoutId`. SwiftUI's
    `matchedGeometryEffect` cannot span a card in document flow and a docked
    overlay without both living in the same namespace and hierarchy, and
    hand-rolling that guards a transition nobody would miss.
  * The orb is a static gradient sphere. Web's `AssistantOrb` is animated; the
    animation is decoration on a launcher, and a permanently-running animation on
    the dashboard is a battery cost with nothing behind it.
  * The embedded view gets `.constant(nil)` for the two deep-link payloads
    (`openGroupId`, `searchPrefill`) that `ContentView` owns and the dashboard
    cannot reach. An assistant action that points at one group therefore lands on
    Splits rather than inside that group — one tap short, the same shortfall
    `AppDestinations.swift` already documents for every other deep link in this
    shell.

 Mirrors apps/android/.../ui/dashboard/AssistantWidget.kt.
 */
struct AssistantWidget: View {
    /// The shell's current tab, so an assistant action can move the app.
    @Binding var currentTab: NavTab

    /// The panel's open state, OWNED BY THE DASHBOARD.
    ///
    /// It has to live up there. `.overlay` sizes itself to the view it is
    /// attached to, and this widget is a 360pt card in the hero row — a panel
    /// presented from here would be clipped to that card rather than docked to
    /// the window edge, which is the one thing the docked layout is for.
    @Binding var panelOpen: Bool
    /// The question that opened the panel, handed to the chat as its first turn.
    @Binding var openingPrompt: String?

    @State private var draft = ""

    var body: some View {
        SanvyaCard(padding: 20) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(S.Assistant.title)
                        .sanvyaStyle(SanvyaType.h2)
                        .foregroundStyle(Color.text)
                    Spacer(minLength: 0)
                    Button {
                        openingPrompt = nil
                        panelOpen = true
                    } label: {
                        SanvyaIconView(SanvyaIcons.spaceDashboard, size: 16, tint: .text)
                            .frame(width: 32, height: 32)
                            .background(Color.surface2)
                            .clipShape(Circle())
                    }
                    .buttonStyle(SanvyaPressStyle())
                    .accessibilityLabel(S.Dashboard.askExpandA11y)
                }

                AssistantOrb()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)

                // Four openers, so the blank-page problem never happens: nobody
                // has to work out what an assistant over their own ledger is
                // even for.
                VStack(spacing: 8) {
                    ForEach(quickPrompts, id: \.label) { quick in
                        SanvyaChip(quick.label, isActive: false, action: { ask(quick.prompt) })
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack(spacing: 8) {
                    SanvyaInput(text: $draft, placeholder: S.Dashboard.askPlaceholder)
                    Button { ask(draft) } label: {
                        SanvyaIconView(SanvyaIcons.chevronRight, size: 16, tint: .accent)
                            .frame(width: 32, height: 32)
                            .background(Color.surface2)
                            .clipShape(Circle())
                    }
                    .buttonStyle(SanvyaPressStyle())
                    .accessibilityLabel(S.Dashboard.askSendA11y)
                }
                .padding(.top, 14)
            }
        }
    }

    private func ask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        openingPrompt = trimmed
        panelOpen = true
        draft = ""
    }

    private var quickPrompts: [QuickPrompt] {
        [
            QuickPrompt(label: S.Dashboard.askQuickWhereLabel, prompt: S.Dashboard.askQuickWherePrompt),
            QuickPrompt(label: S.Dashboard.askQuickBudgetLabel, prompt: S.Dashboard.askQuickBudgetPrompt),
            QuickPrompt(label: S.Dashboard.askQuickGoalLabel, prompt: S.Dashboard.askQuickGoalPrompt),
            QuickPrompt(label: S.Dashboard.askQuickFindLabel, prompt: S.Dashboard.askQuickFindPrompt),
        ]
    }
}

/// One of the four openers on the collapsed card.
private struct QuickPrompt {
    let label: String
    let prompt: String
}

struct AssistantPanel: View {
    @Binding var currentTab: NavTab
    let openingPrompt: String?
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.text.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            SanvyaCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text(S.Assistant.title)
                            .sanvyaStyle(SanvyaType.h2)
                            .foregroundStyle(Color.text)
                        Spacer(minLength: 0)
                        Button(action: onClose) {
                            SanvyaIconView(SanvyaIcons.close, size: 16, tint: .text)
                                .frame(width: 32, height: 32)
                                .background(Color.surface2)
                                .clipShape(Circle())
                        }
                        .buttonStyle(SanvyaPressStyle())
                        .accessibilityLabel(S.Dashboard.askCollapseA11y)
                    }
                    AssistantView(
                        currentTab: $currentTab,
                        openGroupId: .constant(nil),
                        searchPrefill: .constant(nil),
                        initialPrompt: openingPrompt
                    )
                }
            }
            // Two calls, not one. SwiftUI has a FIXED frame
            // (`width:height:alignment:`) and a FLEXIBLE one
            // (`minWidth:…maxHeight:alignment:`) and no overload mixing the two.
            .frame(maxWidth: 420)
            .frame(maxHeight: .infinity)
            .padding(16)
        }
    }
}

/**
 The assistant's sphere.

 Static, and web's is animated — see the note on ``AssistantWidget``. The
 gradient is the accent over the forest green the net-worth hero uses, so the two
 cards in the hero row read as one object rather than two.
 */
private struct AssistantOrb: View {
    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [.accentSoft, .accent, .forest],
                    center: UnitPoint(x: 0.35, y: 0.3),
                    startRadius: 2,
                    endRadius: 116
                )
            )
            // Web's `<AssistantOrb size={116} />`.
            .frame(width: 116, height: 116)
    }
}
