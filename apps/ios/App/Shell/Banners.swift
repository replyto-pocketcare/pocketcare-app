import SwiftUI
import Network

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
 Live connectivity, for the offline banner.

 `NWPathMonitor` rather than a poll: connectivity genuinely is an event stream,
 unlike `failed_writes`, and the banner has to appear the moment signal drops
 rather than up to 30 seconds later.
 */
@MainActor
final class ConnectivityMonitor: ObservableObject {
    @Published private(set) var isOffline = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.sanvya.connectivity")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isOffline = path.status != .satisfied }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
