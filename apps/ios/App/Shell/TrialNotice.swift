import SwiftUI

/**
 Whether the one-time trial welcome dialog has been shown to this account.

 Keyed by email, exactly as web's `trialWelcomeSeenKey` is
 (`sanvya:trial-welcome:<email>`, `"anon"` when there is none), so the two
 clients mean the same thing by it. Signing in as somebody else is a different
 key and therefore a different first run — which is the point of keying it at
 all.

 Device-local, never synced: it records that a dialog was dismissed on this
 device, not anything about the account.
 */
enum TrialWelcomeSeen {
    /// Web's `trialWelcomeSeenKey(email)`, character for character.
    private static func key(_ email: String?) -> String {
        "sanvya:trial-welcome:\(email ?? "anon")"
    }

    static func read(_ email: String?) -> Bool {
        UserDefaults.standard.bool(forKey: key(email))
    }

    static func mark(_ email: String?) {
        UserDefaults.standard.set(true, forKey: key(email))
    }
}

/**
 Trial onboarding — a port of `apps/web/src/ui/TrialNotice.tsx`.

 Two things, and they are two because they answer different questions:

  * a **persistent banner** counting the trial down, so nobody is surprised on
    day fifteen by features quietly disappearing, and
  * a **one-time welcome dialog** right after registration, which says what is
    unlocked and, more usefully, what is NOT free afterwards.

 Only for registered users actually on the trial: not guests (they have their own
 three-day countdown on the bottom bar) and not paid subscribers. That gate is
 web's `session && !session.isGuest && e.isTrial`, and it is why the caller passes
 all three in rather than this view guessing from one of them.

 **The features listed are hardcoded on web as an array of English strings.**
 They are four i18n keys here, and they are a LIST rather than one sentence for
 the same reason web made them one: "you will lose Ask Sanvya, Insights,
 Statements and more" scans as marketing, four bullets scan as an inventory.

 Mirrors apps/android/.../ui/shell/TrialNotice.kt.
 */
struct TrialNotice: View {
    let onTrial: Bool
    let daysLeft: Int
    let email: String?
    let onSeePlans: () -> Void

    @State private var welcomeOpen = false

    private var dayLabel: String { S.Dashboard.trialDays(count: daysLeft) }

    private var loseOnFree: [String] {
        [
            S.Dashboard.trialLoseAssistant,
            S.Dashboard.trialLoseInsights,
            S.Dashboard.trialLoseAutomation,
            S.Dashboard.trialLoseCsv,
        ]
    }

    private func openWelcomeIfUnseen() {
        guard let email, !email.isEmpty else { return }
        if !TrialWelcomeSeen.read(email) { welcomeOpen = true }
    }

    var body: some View {
        if onTrial {
            banner
                .onAppear { openWelcomeIfUnseen() }
                // `email` arrives ASYNCHRONOUSLY from `refreshGuest()`. Without
                // waiting for it the first render reads the key for a nil
                // email, shows the dialog, and marks THAT key on dismissal --
                // then the real address lands, the key changes, and the same
                // person is welcomed a second time. Android already gates on a
                // non-nil email; this is the same rule.
                .onChange(of: email) { _, _ in openWelcomeIfUnseen() }
                .sanvyaModal(
                    isPresented: Binding(
                        get: { welcomeOpen },
                        // A scrim tap is a dismissal, and a dismissal is
                        // permanent: web writes the flag on every exit from this
                        // dialog, including the close button.
                        set: { if !$0 { dismissWelcome() } }
                    ),
                    label: S.Dashboard.trialWelcomeTitle
                ) {
                    welcome
                }
        }
    }

    private var banner: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle().fill(Color.accent).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(S.Dashboard.trialBannerTitle(days: dayLabel))
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.text)
                Text(S.Dashboard.trialBannerBody)
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SanvyaButton(action: onSeePlans) {
                Text(S.Dashboard.trialUpgrade)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.accentGhost)
        .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SanvyaRadius.row, style: .continuous)
                .strokeBorder(Color.accentSoft, lineWidth: 1)
        )
        .padding(.bottom, 16)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(S.Dashboard.trialWelcomeTitle)
                .sanvyaStyle(SanvyaType.h2)
                .foregroundStyle(Color.text)
            Text(S.Dashboard.trialWelcomeSubtitle(days: dayLabel))
                .sanvyaStyle(SanvyaType.statLabel)
                .foregroundStyle(Color.text2)
            Text(S.Dashboard.trialWelcomeIntro)
                .sanvyaStyle(SanvyaType.body)
                .foregroundStyle(Color.text)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(loseOnFree, id: \.self) { feature in
                    HStack(alignment: .top, spacing: 8) {
                        // Web draws a "✦" glyph in `--accent`. A small filled dot
                        // says the same thing without shipping a decorative
                        // character no font here is guaranteed to have.
                        Circle()
                            .fill(Color.accent)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        Text(feature)
                            .sanvyaStyle(SanvyaType.statLabel)
                            .foregroundStyle(Color.text)
                    }
                }
            }

            Text(S.Dashboard.trialWelcomeFooter(days: dayLabel))
                .sanvyaStyle(SanvyaType.statLabel)
                .foregroundStyle(Color.text2)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                SanvyaButton(ghost: true, action: dismissWelcome) {
                    Text(S.Dashboard.trialLater)
                }
                SanvyaButton(action: {
                    dismissWelcome()
                    onSeePlans()
                }) {
                    Text(S.Dashboard.trialSeePlans)
                }
            }
        }
    }

    private func dismissWelcome() {
        TrialWelcomeSeen.mark(email)
        welcomeOpen = false
    }
}
