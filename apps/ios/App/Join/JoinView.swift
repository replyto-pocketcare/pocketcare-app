import SwiftUI
import Factory
import Data

/**
 An invite token held while the user signs in, then consumed.

 Web keeps this in `localStorage` under the same key, for the same reason:
 accepting an invite needs a session, so the token has to survive the trip out
 to the auth provider and back — and on a phone that trip can outlive the
 process. Device-local and never synced: it is a few seconds of state about one
 tap, not ledger data.

 Mirrors Android's `Prefs.pendingInvite`.
 */
enum PendingInvite {
    private static let key = "pendingInvite"

    static func read(_ defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: key)
    }

    static func write(_ token: String?, _ defaults: UserDefaults = .standard) {
        if let token { defaults.set(token, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}

/**
 Accept a split-group invite — ported from `apps/web/app/join/page.tsx`.

 A centred card with no chrome, because it is a landing for a link from outside
 the app rather than a place inside it. Every visit ends by leaving: into the
 group, or into sign-in.

 The page is one effect and three outcomes, and this is the same three:

 * no token → say so, stop.
 * no session → stash the token and ask them to sign in.
 * session → clear the stash FIRST, then accept, then hand the group id back.

 Clearing before accepting is web's own ordering and it matters: the token is
 being consumed, so leaving it stashed would send the user back here on the next
 launch to accept an invite that is already spent.

 Android puts this logic in a `JoinViewModel` because an Android view model
 survives configuration changes; here it is view state, which is what every
 other small screen in this app does.

 Mirrors Android's JoinScreen.kt + JoinViewModel.kt.
 */
struct JoinView: View {
    let token: String?
    let onJoined: (String) -> Void
    let onSignIn: () -> Void
    let onDismiss: () -> Void

    @Injected(\.invitesRepository) private var invitesRepository
    @Injected(\.authRepository) private var authRepository

    @State private var message: String?
    @State private var needsAuth = false
    @State private var started = false

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            SanvyaCard(padding: 32) {
                VStack(spacing: 12) {
                    SanvyaIconView(SanvyaIcons.groups, size: 28, tint: Color.accent)
                    Text(S.Join.title)
                        .font(.system(size: 22, weight: .semibold))
                        .multilineTextAlignment(.center)
                    if let message {
                        Text(message)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.text2)
                            .multilineTextAlignment(.center)
                    }
                    if needsAuth {
                        SanvyaButton { onSignIn() } label: {
                            Text(S.Join.signInCreate)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 420)
            .padding(16)
        }
        .task { await start() }
        // A landing with no way out is a trap on a phone, where there is no
        // browser back button. Web does not need this; the cover does.
        .overlay(alignment: .topLeading) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.text2)
                    .padding(16)
            }
        }
    }

    private func start() async {
        guard !started else { return }
        started = true

        guard let token, !token.isEmpty else {
            message = S.Join.missingToken
            return
        }
        if authRepository.currentUserId == nil {
            PendingInvite.write(token)
            needsAuth = true
            message = S.Join.needAuth
            return
        }

        message = S.Join.opening
        // Cleared UP FRONT: there is a session and the token is being consumed,
        // so it must not trigger another join on the next launch.
        PendingInvite.write(nil)
        do {
            let groupId = try await invitesRepository.acceptInvite(token: token)
            onJoined(groupId)
        } catch let error as InviteError {
            message = error.message
        } catch {
            message = error.localizedDescription
        }
    }
}

/**
 The token from an invite URL, or nil.

 Two shapes are accepted. `https://sanvya.app/join?token=…` is the real link —
 the one in a WhatsApp message — and needs Universal Links VERIFICATION to reach
 the app at all (see docs/mobile/ABSENT-BY-DECISION.md).
 `<authRedirectScheme>://join?token=…` needs no server-side anything and works
 today, which is what makes the screen testable before that verification exists.

 Mirrors Android's `MainActivity.inviteTokenFrom`.
 */
func inviteTokenFromURL(_ url: URL) -> String? {
    guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    let isJoin = (parts.scheme == "https" && (parts.path == "/join" || parts.path.hasPrefix("/join/")))
        || (parts.scheme != "https" && parts.host == "join")
    guard isJoin else { return nil }
    let token = parts.queryItems?.first { $0.name == "token" }?.value
    return (token?.isEmpty ?? true) ? nil : token
}
