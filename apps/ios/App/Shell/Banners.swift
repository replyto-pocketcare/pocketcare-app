import SwiftUI
import Domain

/**
 The app-wide banners, in web's z-order: sync problems above offline, both above
 everything else. Full-width strips rather than page content, so they read as
 system messages.
 */

/**
 Shown whenever connectivity is lost.

 The copy is web's, verbatim — it is doing real work. Telling someone their data
 is safe on the device is the difference between "the app is broken" and "the
 app is waiting".
 */
struct OfflineBanner: View {
    let offline: Bool

    var body: some View {
        if offline {
            HStack(spacing: SanvyaMetrics.Banner.gap) {
                Circle().fill(Color.white.opacity(0.9)).frame(width: 7, height: 7)
                Text("You're offline — changes are saved on this device and will sync when you're back online.")
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, SanvyaMetrics.Banner.paddingH)
            .padding(.vertical, SanvyaMetrics.Banner.paddingV)
            .background(Color.warning)
            .accessibilityElement(children: .combine)
        }
    }
}

/**
 Shown while any write sits quarantined in `failed_writes`.

 Discoverability is the entire point. The failure this covers is silent by
 design — the upload queue unblocks, everything else syncs, and the app looks
 perfectly healthy while a few of someone's expenses sit in limbo. A recovery
 screen buried in Settings is only ever found by someone who already suspects
 something is wrong. So the app says so, unprompted, until it is dealt with.
 */
struct SyncProblemsBanner: View {
    let count: Int
    let onReview: () -> Void

    var body: some View {
        if count > 0 {
            Button(action: onReview) {
                Text(count == 1
                     ? "1 change couldn't be saved — tap to review"
                     : "\(count) changes couldn't be saved — tap to review")
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, SanvyaMetrics.Banner.paddingH)
                    .padding(.vertical, SanvyaMetrics.Banner.paddingV)
                    .background(Color.negative)
            }
            .buttonStyle(.plain)
        }
    }
}

/**
 The in-flow sync status strip — web's `AppShell.tsx` block just above
 `<TrialNotice />`.

 Not pinned above the page, unlike the two banners above: it is a sentence about
 the state of the app, not a problem sitting on top of the content. It scrolls
 away with the page, exactly as web's does.

 **iOS never had one at all.** Android's equivalent existed and had zero call
 sites; this platform did not even have the view — so the one place web explains
 an unreachable server said nothing on either port.

 The decision is ``SyncNotice`` from Domain (`syncNotice`), vector-pinned, and
 the words come from the `sync` namespace. Web's own copy is two English literals
 inline, which is why the port could not simply reuse it.

 **Force Sync is deliberately absent**, and this is the one thing the strip is
 short of web's. Web's button is `disconnect()` then `connect(connector)`;
 neither native app calls `connect()` ANYWHERE, so wiring it here would make a
 status strip the app's only sync-connection call and quietly paper over a
 bootstrap bug that should be fixed where the database is created. Report Issue
 is here because it is real: it opens the Feedback sheet the shell already owns,
 which is the app's actual support channel.

 **The OFFLINE branch never renders on mobile, deliberately.** Web shows the
 offline message TWICE when you are offline — once in the sticky `OfflineBanner`
 and again, in different words, in this in-flow strip. On a browser that is
 redundant; on a phone it is two of the six visible rows saying the same thing
 on every screen. The banner is the better of the two (it is pinned, so it
 survives scrolling), so the strip keeps only TROUBLE — the state the banner has
 nothing to say about. Recorded as a web defect rather than reproduced.
 */
struct SyncStatusStrip: View {
    let notice: SyncNotice
    /// Nil hides the action, which is also what the offline branch wants.
    let onReportIssue: (() -> Void)?

    private var isWarning: Bool { notice == .trouble }

    var body: some View {
        if notice == .trouble {
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(isWarning ? Color.warning : Color.text2)
                    .frame(width: 8, height: 8)
                Text(isWarning ? S.Sync.trouble : S.Sync.offline)
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(isWarning ? Color.text : Color.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Only on the warn branch, matching web: the offline note is
                // informational and has nothing to act on.
                if isWarning, let onReportIssue {
                    Button(action: onReportIssue) {
                        Text(S.Sync.reportIssue)
                            .sanvyaStyle(SanvyaType.statLabel)
                            .foregroundStyle(Color.accent)
                    }
                    .buttonStyle(SanvyaPressStyle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isWarning ? Color.accentGhost : Color.surface2)
            .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SanvyaRadius.row, style: .continuous)
                    .strokeBorder(isWarning ? Color.warning : Color.border, lineWidth: 1)
            )
            .padding(.bottom, 16)
            .accessibilityElement(children: .combine)
        }
    }
}
