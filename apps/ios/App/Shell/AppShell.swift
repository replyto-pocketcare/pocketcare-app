import SwiftUI

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
                            showBack: false,
                            unreadCount: viewModel.unreadCount,
                            onBack: {},
                            onNotifications: { select(.notifications) }
                        )
                    }
                    content(tabBinding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.top, SanvyaMetrics.Page.paddingTop)
                .padding(.horizontal, SanvyaMetrics.Page.paddingHorizontal)
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
                })
            }
        }
        .environment(\.addActionSetter) { pageAction = $0 }
        .sanvyaModal(isPresented: $moreOpen, label: "More") {
            MoreSheet(
                currentTab: currentTab,
                unreadCount: viewModel.unreadCount,
                isGuest: viewModel.isGuest,
                guestDaysLeft: viewModel.guestDaysLeft,
                appVersion: appVersion,
                onSelect: { tab in moreOpen = false; select(tab) },
                onCustomize: { moreOpen = false; customizeOpen = true },
                onFeedback: { moreOpen = false },
                onClose: { moreOpen = false }
            )
        }
        .sanvyaModal(isPresented: $customizeOpen, label: "Customize bottom bar") {
            BottomNavCustomizer(
                current: navPrefs.ids,
                onSave: { ids in navPrefs.setIds(ids); customizeOpen = false },
                onClose: { customizeOpen = false }
            )
        }
        .task {
            viewModel.start()
            // `failed_writes` is local-only, so there is no sync event to
            // observe. Web polls every 30s; so does this.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await viewModel.refreshFailedWrites()
            }
        }
    }

    private func select(_ tab: NavTab) {
        // Overlays never survive a navigation — web closes both on every route
        // change.
        moreOpen = false
        addOpen = false
        storedTab = tab.rawValue
    }

    private func runAdd() {
        switch action {
        case let .link(_, tab): select(tab)
        case .button: break
        case .menu: addOpen.toggle()
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
