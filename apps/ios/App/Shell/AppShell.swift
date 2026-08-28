import SwiftUI
import Domain

/// Matches web's `APP_VERSION` in AppShell.tsx.
private let appVersion = "0.1.0"

/**
 The app shell: banners, the utility row, the floating bottom bar, and the
 overlays that hang off it.

 Replaces `MainTabView` + `DrawerMenuView`. Those were a drawer, despite the
 name — a hand-rolled offset animation over a tab switch — and web's phone
 layout has never had one. It has this: a bottom bar with four user-customizable
 slots, a raised centre "+", and a grouped More sheet.

 Full spec, with every value traced back to `globals.css`:
 `docs/mobile/screen-specs/app-shell.md`.
 */
struct AppShell<Content: View>: View {
    @State private var viewModel = ShellViewModel()
    @StateObject private var connectivity = ConnectivityMonitor()
    @StateObject private var navPrefs = NavPrefs.shared

    /// Survives backgrounding and process death — the tab you were on is part
    /// of where you were, not incidental state (plan §7 R1).
    @SceneStorage("shell.currentTab") private var storedTab: String = NavTab.dashboard.rawValue

    @State private var pageAction: AddAction?
    @State private var moreOpen = false
    @State private var customizeOpen = false
    @State private var addOpen = false
    /// A guest tapping "Create an account". `LoginView` is normally the auth
    /// gate ABOVE this shell (`SanvyaApp`), so a guest -- who is signed in --
    /// could never reach it. Web links both guest chips to `/login`.
    @State private var signInOpen = false
    @State private var pageBack: (() -> Void)?

    /**
     The two flows the "+" opens.

     They live HERE, not on the dashboard, because the "+" is the shell's. They
     used to be dashboard state reachable only from a second FAB that the
     dashboard drew on top of the bottom bar — so iOS had two "+" affordances,
     web has one, and the shell's own menu item for a receipt selected a nil tab
     and did nothing at all.
     */
    @State private var showingNewTransaction = false
    @State private var showingReceiptCapture = false
    @State private var reviewingScanId: String?

    /// The Feedback entry in the More sheet and the side nav used to be wired
    /// to a closure that closed the sheet and did nothing else — a visible
    /// control that lied, and the app's only error-report channel.
    @State private var feedbackOpen = false

    @Environment(\.sanvyaWindowClass) private var windowClass
    @Environment(\.colorScheme) private var colorScheme

    let content: (Binding<NavTab>) -> Content

    private var currentTab: NavTab {
        NavTab(rawValue: storedTab) ?? .dashboard
    }

    /// Handed to the screens so one of them can send you somewhere without
    /// knowing anything about the shell. Writing through it goes via
    /// `select`, so the overlays close exactly as they do on a bar tap —
    /// a screen must not be able to navigate and leave the More sheet open.
    private var tabBinding: Binding<NavTab> {
        Binding(get: { currentTab }, set: { select($0) })
    }

    /// Web's `bare` routes — decisions, not destinations, and they render with
    /// no app chrome at all.
    private var isBare: Bool { false }

    private var action: AddAction { pageAction ?? defaultAddAction(canScan: viewModel.canScan) }

    var body: some View {
        Group {
            if windowClass == .expanded {
                expandedBody
            } else {
                compactBody
            }
        }
        // Web renders `<GlobalLoader />` once, next to the shell rather than
        // inside it: it is about the app, not about the page. An overlay is the
        // SwiftUI equivalent, and it sits outside the window-class branch so it
        // is present at every size.
        .overlay { WriteIndicatorView() }
        // A full-screen cover, not a sheet: this is the whole login screen, and
        // a card with the app showing behind it reads as optional.
        .fullScreenCover(isPresented: $signInOpen) { LoginView() }
        // The only exit. Four of LoginView's methods finish in-screen and one
        // (Google) returns through the browser, so the cover cannot close
        // itself on a callback -- it closes when the guest stops being one.
        .onChange(of: viewModel.isGuest) { _, guest in if !guest { signInOpen = false } }
        .environment(\.addActionSetter) { pageAction = $0 }
        .environment(\.backActionSetter) { pageBack = $0 }
        // Lets a screen — or a sheet it presents — move the shell, which web
        // gets from its router. See SelectTabAction.swift.
        .environment(\.selectTab) { select($0) }
        // Both overlays belong to the bottom bar. At `.expanded` the bar is gone
        // and the sidebar shows every destination directly, so there is nothing
        // to open them from — and a sheet that can never be dismissed by its own
        // affordance is worse than no sheet.
        .sanvyaModal(isPresented: moreBinding, label: S.Translation.navMore) {
            MoreSheet(
                currentTab: currentTab,
                unreadCount: viewModel.unreadCount,
                isGuest: viewModel.isGuest,
                guestDaysLeft: viewModel.guestDaysLeft,
                appVersion: appVersion,
                onSelect: { tab in moreOpen = false; select(tab) },
                onSignIn: { moreOpen = false; signInOpen = true },
                onCustomize: { moreOpen = false; customizeOpen = true },
                onFeedback: { moreOpen = false; feedbackOpen = true },
                onClose: { moreOpen = false }
            )
        }
        .sanvyaModal(isPresented: customizeBinding, label: S.Translation.navCustomize) {
            BottomNavCustomizer(
                current: navPrefs.ids,
                onSave: { ids in navPrefs.setIds(ids); customizeOpen = false },
                onClose: { customizeOpen = false }
            )
        }
        // Not gated on the window class, unlike More and Customize: those two
        // are opened from the bottom bar and are unreachable without it, while
        // Feedback is reachable from the sidebar as well.
        .sanvyaModal(isPresented: $feedbackOpen, label: S.Feedback.title) {
            FeedbackSheet(
                route: currentTab.rawValue,
                online: !connectivity.isOffline,
                onClose: { feedbackOpen = false }
            )
        }
        .sanvyaFormPresentation(isPresented: $showingNewTransaction) {
            CreateTransactionView()
        }
        .fullScreenCover(isPresented: $showingReceiptCapture) {
            ReceiptCaptureView(
                onScanned: { scanId in
                    showingReceiptCapture = false
                    reviewingScanId = scanId
                },
                onCancel: { showingReceiptCapture = false },
                // Web's premium card links to /settings, where the plans live.
                onSeePlans: {
                    showingReceiptCapture = false
                    select(.settings)
                }
            )
        }
        .fullScreenCover(item: Binding(
            get: { reviewingScanId.map { ScanId(value: $0) } },
            set: { reviewingScanId = $0?.value }
        )) { wrapped in
            ReceiptReviewView(
                scanId: wrapped.value,
                onSaved: { _ in reviewingScanId = nil },
                onCancel: { reviewingScanId = nil }
            )
        }
        .task {
            viewModel.start()
            // Post anything that fell due while the app was closed. The view
            // model holds the once-per-session latch, so this is safe to
            // re-run on every appearance.
            viewModel.startCatchUp(todayIso: isoToday(), baseCurrency: baseCurrencyNow())
            // `failed_writes` is local-only, so there is no sync event to
            // observe. Web polls every 30s; so does this.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await viewModel.refreshFailedWrites()
            }
        }
    }

    private var moreBinding: Binding<Bool> {
        Binding(get: { moreOpen && windowClass.usesBottomBar }, set: { moreOpen = $0 })
    }

    private var customizeBinding: Binding<Bool> {
        Binding(get: { customizeOpen && windowClass.usesBottomBar }, set: { customizeOpen = $0 })
    }

    /**
     The `.expanded` layout: a persistent sidebar beside the content, and no
     floating bottom bar.

     Web turns the whole app into an inset console window at this size (a
     `--surface-2` backdrop with the app floating on it, rounded and shadowed),
     which is what stops an iPad reading as an iPhone layout stretched sideways.
     Ported literally, because on a tablet that difference is the entire
     impression the app makes.
     */
    private var expandedBody: some View {
        VStack(spacing: 0) {
            // Banners stay full-bleed above the frame: they are system messages
            // about the app, not content inside it.
            SyncProblemsBanner(count: viewModel.failedWriteCount) { select(.settings) }
            OfflineBanner(offline: connectivity.isOffline)

            HStack(spacing: 0) {
                SideNav(
                    currentTab: currentTab,
                    unreadCount: viewModel.unreadCount,
                    isGuest: viewModel.isGuest,
                    guestDaysLeft: viewModel.guestDaysLeft,
                    appVersion: appVersion,
                    onSelect: select,
                    onFeedback: { feedbackOpen = true },
                    onSignIn: { signInOpen = true }
                )

                VStack(spacing: 0) {
                    if currentTab != .dashboard {
                        UtilRow(
                            showBack: pageBack != nil,
                            unreadCount: viewModel.unreadCount,
                            onBack: { pageBack?() },
                            onNotifications: { select(.notifications) }
                        )
                    }
                    content(tabBinding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: SanvyaMetrics.Expanded.contentMaxWidth)
                .padding(.top, SanvyaMetrics.Expanded.contentPaddingTop)
                .padding(.horizontal, SanvyaMetrics.Expanded.contentPaddingH)
                // No bottom clearance: the floating bar is gone, so reserving
                // 96 for it would leave a dead strip.
                .padding(.bottom, SanvyaMetrics.Expanded.contentPaddingBottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.bg)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: SanvyaMetrics.Expanded.frameRadius,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: SanvyaMetrics.Expanded.frameRadius,
                    style: .continuous
                )
                .strokeBorder(Color.border, lineWidth: 1)
            )
            .sanvyaShadow(SanvyaShadows.shadowLg(dark: colorScheme == .dark))
            .padding(SanvyaMetrics.Expanded.frameInset)
        }
        // The backdrop the window floats on — web changes the *body*
        // background here, not the app's.
        .background(Color.surface2.ignoresSafeArea())
    }

    private var compactBody: some View {
        ZStack(alignment: .bottom) {
            Color.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Banners sit above everything, in web's z-order: problems first.
                SyncProblemsBanner(count: viewModel.failedWriteCount) { select(.settings) }
                OfflineBanner(offline: connectivity.isOffline)

                VStack(spacing: 0) {
                    // The dashboard places its own greeting and bell as the very
                    // first thing on the page, so the shared row is skipped there.
                    if currentTab != .dashboard {
                        UtilRow(
                            showBack: pageBack != nil,
                            unreadCount: viewModel.unreadCount,
                            onBack: { pageBack?() },
                            onNotifications: { select(.notifications) }
                        )
                    }
                    content(tabBinding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.top, SanvyaMetrics.Page.paddingTop)
                .padding(.horizontal, SanvyaMetrics.Page.paddingHorizontal)
                // At `.medium` the column caps and centres rather than
                // stretching an iPhone layout across an iPad, which is exactly
                // what web does above its own middle breakpoint.
                .frame(maxWidth: windowClass.capsContentWidth ? SanvyaMetrics.Page.maxWidth : .infinity)
            }
            // Web reserves 96px plus the safe area beneath the floating bar.
            .padding(.bottom, SanvyaMetrics.Page.paddingBottom)

            BottomNav(
                currentTab: currentTab,
                navIds: navPrefs.ids,
                unreadCount: viewModel.unreadCount,
                addLabel: action.label,
                moreOpen: moreOpen,
                onSelect: select,
                onAdd: runAdd,
                onMore: { moreOpen = true }
            )
            .padding(.horizontal, SanvyaMetrics.BottomNav.sideInset)
            .padding(.bottom, SanvyaMetrics.BottomNav.bottomInset)

            if addOpen, case let .menu(_, items) = action {
                AddPopover(items: items, onDismiss: { addOpen = false }, onSelect: { item in
                    addOpen = false
                    if let tab = item.tab { select(tab) }
                    if let flow = item.flow { run(flow) }
                })
            }
        }
    }

    private func select(_ tab: NavTab) {
        // Overlays never survive a navigation — web closes both on every route
        // change.
        moreOpen = false
        addOpen = false
        // The outgoing screen's Back goes with it — `onDisappear` fires too
        // late to stop it flashing on the incoming one.
        pageBack = nil
        storedTab = tab.rawValue
    }

    private func runAdd() {
        switch action {
        case let .link(_, tab): select(tab)
        case .button: break
        case .menu: addOpen.toggle()
        }
    }

    private func run(_ flow: AddAction.Flow) {
        switch flow {
        case .newTransaction: showingNewTransaction = true
        case .scanReceipt: showingReceiptCapture = true
        }
    }
}

/**
 The contextual add menu — a small floating panel above the bar, not a sheet.
 Web's is a popover, and a sheet would read as a much heavier gesture for a
 two-item choice.
 */
private struct AddPopover: View {
    let items: [AddAction.Item]
    let onDismiss: () -> Void
    let onSelect: (AddAction.Item) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            // Transparent: it dims nothing (web's popover floats above an
            // undimmed page) and exists purely as a big dismiss target.
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            SanvyaCard(padding: SanvyaMetrics.AddPopover.padding, cornerRadius: SanvyaRadius.popover) {
                VStack(spacing: SanvyaMetrics.AddPopover.gap) {
                    ForEach(items) { item in
                        Button { onSelect(item) } label: {
                            HStack(spacing: 10) {
                                SanvyaIconView(item.glyph, size: 17, tint: .text)
                                Text(item.label)
                                    .sanvyaStyle(SanvyaType.button)
                                    .foregroundStyle(Color.text)
                                Spacer()
                                if item.locked {
                                    // A lock, not a tier name: the plans are Lite
                                    // and Pro, so naming one would be either wrong
                                    // or only half the answer.
                                    SanvyaIconView(
                                        SanvyaIcons.lock,
                                        size: 13,
                                        tint: .text3,
                                        accessibilityLabel: "Paid plan required"
                                    )
                                }
                            }
                            .padding(.horizontal, SanvyaMetrics.AddPopover.itemPaddingH)
                            .padding(.vertical, SanvyaMetrics.AddPopover.itemPaddingV)
                        }
                        .buttonStyle(SanvyaPressStyle())
                    }
                }
            }
            .frame(minWidth: SanvyaMetrics.AddPopover.minWidth, maxWidth: 320)
            .padding(.horizontal, 16)
            .padding(.bottom, SanvyaMetrics.AddPopover.bottomOffset)
        }
    }
}

/// Wraps a scan id for `.fullScreenCover(item:)`, which needs `Identifiable`.
/// Moved here from `DashboardView` with the receipt flow itself.
private struct ScanId: Identifiable {
    let value: String
    var id: String { value }
}
