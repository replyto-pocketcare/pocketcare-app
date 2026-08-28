import SwiftUI
import Factory
import Domain

struct DashboardView: View {
    /// A tile's "more details" tap writes here, the same channel Insights and
    /// Cards already use. The shell owns navigation; nothing here pushes its
    /// own NavigationStack.
    @Binding var currentTab: NavTab

    @State private var viewModel = Container.shared.dashboardViewModel()
    /// Entitlement gates the five premium tiles. The shell already computes it
    /// for the receipt-scan lock, so this asks it rather than re-deriving
    /// isPaid() — the same reason the chart palettes moved into FormOptions.
    @State private var shellViewModel = ShellViewModel()
    @State private var editing = false
    @State private var addOpen = false
    // Hide-amounts is a real, load-bearing toggle (Settings > "Hide Amounts",
    // apps/web's useMoneyFmt()) -- was missing entirely from this screen
    // until 2026-08-05 (found auditing for the Accounts screen pass, fixed
    // here since it's the same hero/accounts-strip code this file already
    // owns). Mirrors Android's Prefs.amountsHidden the same way.
    @StateObject private var prefs = Prefs.shared
    // Both the empty-state CTA and the accounts strip's "Add" tile open the
    // same sheet -- matches AccountsView.swift's existing
    // showingCreateSheet/CreateAccountView() pattern (no dedicated NavTab
    // exists for "create account", so every other screen that offers this
    // action does it the same way).
    @State private var showingCreateAccountSheet = false
    // The speed dial that used to live here is gone. It was a second "+" drawn
    // over the bottom bar's own, which web does not have -- web renders
    // `AddSpeedDial` INSIDE the shell, once. Both of its actions moved to
    // `AppShell`, which is where the "+" already was.

    /// The first-run walkthrough. Mounted here, not in the shell, because that
    /// is where web mounts it (`apps/web/app/page.tsx` renders `<Walkthrough />`
    /// in both of the dashboard's branches) — and it is the right place: the
    /// dashboard is where a new user actually lands and stalls.
    @State private var walkthrough = WalkthroughGate()
    /// A guest tapping step 7's "Create an account". `AppShell` owns the same
    /// cover for its guest chips, but the walkthrough is presented FROM this
    /// view, so it has to be the one to present what comes after it.
    @State private var showingLogin = false

    var body: some View {
        NavigationStack {
            Group {
                // While the local read has not returned OR the first sync from
                // the server has not landed, show widget-shaped placeholders --
                // never the "add your first account" screen. page.tsx guards the
                // same way and says why: that screen flashed during the initial
                // sync, which tells a returning user their money is gone. Both
                // ports used to accept the two-state simplification; they no
                // longer do, on the same day, on both platforms.
                if viewModel.accounts.isEmpty && (!viewModel.accountsLoaded || viewModel.syncPending) {
                    DashboardSkeletonView()
                } else if viewModel.accounts.isEmpty {
                    // Empty/onboarding state -- apps/web/app/page.tsx's
                    // `balances.length === 0` early return, matching Android's
                    // EmptyDashboard (DashboardScreen.kt).
                    DashboardEmptyStateView(onAddAccount: { showingCreateAccountSheet = true })
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Web's `.dash-header`: the time-of-day greeting as
                            // an eyebrow, the person's name as the page's h1,
                            // and the control row beside it. This is why the
                            // shell skips its shared utility row on this tab
                            // (AppShell.swift) -- the bell belongs here.
                            DashboardHeaderView(
                                displayName: viewModel.displayName,
                                editing: editing,
                                hidden: prefs.amountsHidden,
                                unreadCount: shellViewModel.unreadCount,
                                onToggleEditing: { editing.toggle() },
                                onToggleHidden: { prefs.amountsHidden.toggle() },
                                onNotifications: { currentTab = .notifications }
                            )

                            // Net-worth hero -- ported from apps/web/app/page.tsx's
                            // NetWorthHero per docs/mobile/screen-specs/dashboard.md.
                            // Replaces this file's previous flat Color.accent card
                            // with an invented "Assets/Liabilities" split that never
                            // existed in the web source (found + fixed 2026-08-05,
                            // see AUDIT_HISTORY.md).
                            NetWorthHeroView(
                                state: viewModel.hero,
                                hidden: prefs.amountsHidden,
                                onToggle: { viewModel.toggleShowAvailable() }
                            )

                            // Accounts Section
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(S.Translation.navAccounts)
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(Color.text)
                                    Spacer()
                                    // Web's "View all", with the total appended
                                    // only once the strip has stopped showing
                                    // them all -- the number is there to say
                                    // "there are more", not to count what is
                                    // already visible. A chevron used to sit
                                    // here wired to an empty action; this is
                                    // the link it was pretending to be.
                                    Button {
                                        currentTab = .accounts
                                    } label: {
                                        Text(viewModel.accounts.count > 8
                                             ? S.Dashboard.viewAllCount(n: String(viewModel.accounts.count))
                                             : S.Dashboard.viewAll)
                                            .font(.system(size: 13))
                                            .foregroundColor(Color.accent)
                                    }
                                    .buttonStyle(SanvyaPressStyle())
                                }

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        // Per docs/mobile/screen-specs/dashboard.md
                                        // "Accounts card": colored chip per account
                                        // (account.color or colorForId(id)), not a
                                        // flat PocketCard -- matches web exactly.
                                        ForEach(viewModel.accounts.prefix(8), id: \.account.id) { acctWithBal in
                                            let balanceCents = acctWithBal.balance.amount
                                            let balanceFormatted = prefs.amountsHidden ? "••••••" : formatCents(balanceCents)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(acctWithBal.account.type.replacingOccurrences(of: "_", with: " "))
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.white.opacity(0.85))
                                                    .lineLimit(1)
                                                Text(acctWithBal.account.name)
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(.white)
                                                    .lineLimit(1)
                                                Text(balanceFormatted)
                                                    .font(.system(size: 14.5, weight: .heavy))
                                                    .foregroundColor(.white)
                                                    .lineLimit(1)
                                            }
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 9)
                                            .frame(width: 112, alignment: .leading)
                                            .background(accountColor(explicit: acctWithBal.account.color, id: acctWithBal.account.id))
                                            .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusSm, style: .continuous))
                                        }

                                        // The add-account tile, last in the strip
                                        // and the same footprint as an account:
                                        // outlined instead of filled, exactly as
                                        // web draws it. Without it the only way to
                                        // add a second account was to leave for the
                                        // Accounts screen first -- two screens for
                                        // the one action this strip is about.
                                        AddAccountTile { showingCreateAccountSheet = true }
                                    }
                                }
                            }

                            // Tile catalog (recent/spending/trends/budgets/goals/
                            // etc.) -- matches Android's DashboardTileGrid exactly
                            // (found missing on iOS 2026-08-06, Akhilesh: "I don't
                            // see an option to add widgets").
                            DashboardTileGrid(
                                editing: editing,
                                isPaid: shellViewModel.canScan,
                                onOpen: { currentTab = $0 }
                            )
                            if editing {
                                SanvyaButton { addOpen = true } label: {
                                    Text(S.Dashboard.addWidget)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color.bg.ignoresSafeArea())
            // Web's dashboard has no chrome above the greeting: the greeting IS
            // the page header, and the controls that used to sit in this bar
            // (Customize, hide/show) now sit beside it, with the bell they were
            // always meant to be next to. A "+Account" is still skipped for the
            // reason Android skipped it: account creation is one tap away from
            // the strip's own Add tile.
            .toolbar(.hidden, for: .navigationBar)
        }
        .sanvyaFormPresentation(isPresented: $showingCreateAccountSheet) {
            CreateAccountView()
        }
        .sanvyaModal(isPresented: $addOpen, label: S.Dashboard.addWidget) {
            AddWidgetSheet(isPaid: shellViewModel.canScan, onClose: { addOpen = false })
        }
        // The design system's dialog, which is the port of web's `Modal` — the
        // walkthrough is a dialog there too, and a plain `.fullScreenCover`
        // would be a different presentation with different metrics.
        //
        // A scrim tap resolves to skip(), matching web's `onClose={skip}`: a
        // tap outside is "not now", never "done".
        .sanvyaModal(isPresented: Binding(
            get: { walkthrough.isOpen },
            set: { if !$0 { walkthrough.skip() } }
        ), label: S.Onboarding.wtDialogLabel) {
            WalkthroughView(
                onFinish: { walkthrough.finish() },
                onSkip: { walkthrough.skip() },
                onNavigateToLogin: { showingLogin = true },
                onNavigateToPlans: { currentTab = .settings }
            )
        }
        .fullScreenCover(isPresented: $showingLogin) { LoginView() }
        .task { shellViewModel.start() }
        .onAppear {
            viewModel.start()
            walkthrough.start()
        }
        .onDisappear {
            viewModel.cancel()
        }
    }

    /// Amounts here are in the user's base currency, not always INR — the old
    /// local formatter hardcoded both the currency and ÷100.
    private func formatCents(_ cents: Int64) -> String {
        formatMoneyUnmasked(Domain.money(cents, baseCurrencyNow()))
    }
}

// MARK: - Header

/**
 Web's `.dash-header`: the time-of-day greeting as an eyebrow, the person's name
 as the page's h1, and the control row beside it.

 Rendered in the page rather than in the navigation bar, because that is where
 web puts it — and it is why `AppShell` skips its shared utility row on this tab.
 Drawing the bell in both places would put two of them on the one screen that
 carries its own.
 */
struct DashboardHeaderView: View {
    let displayName: String
    let editing: Bool
    let hidden: Bool
    let unreadCount: Int
    let onToggleEditing: () -> Void
    let onToggleHidden: () -> Void
    let onNotifications: () -> Void

    /// Refreshed on appear, not read inside `body`.
    ///
    /// Reading a clock inside `body` makes what a frame renders depend on when
    /// the frame happened to run. But this is a TAB, and `@State` outlives a
    /// tab switch and a backgrounding -- initialising once meant a session
    /// opened at 11:55 still said "Good morning" at three in the afternoon.
    @State private var hour = Calendar.current.component(.hour, from: Date())

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                SanvyaEyebrow(timeGreeting(hour: hour))
                // `compact: false` — web's is clamp(24px, 6.5vw, 30px), i.e. the
                // full h1, not the tightened one lists use.
                SanvyaH1(displayName.isEmpty ? S.Dashboard.greetingFallback : displayName, compact: false)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            SanvyaChip(
                editing ? S.Translation.commonDone : S.Dashboard.customize,
                isActive: editing,
                action: onToggleEditing
            )
            HideAmountsButton(hidden: hidden, action: onToggleHidden)
            NotifBell(unreadCount: unreadCount, action: onNotifications)
        }
        .onAppear { hour = Calendar.current.component(.hour, from: Date()) }
    }
}

/**
 The eye toggle, icon-only.

 Web's is a chip with the word "Hide"/"Show" beside the icon. At phone width
 three labelled chips plus the bell do not fit next to a name, so this keeps the
 icon and moves the words into the accessibility label — where a screen reader
 still gets them, which is the half that was load-bearing.
 */
private struct HideAmountsButton: View {
    let hidden: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: hidden ? "eye" : "eye.slash")
                .font(.system(size: 15))
                .foregroundStyle(Color.text)
                .frame(width: SanvyaMetrics.UtilRow.buttonSize,
                       height: SanvyaMetrics.UtilRow.buttonSize)
                .background(Color.surface)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.border, lineWidth: 1))
        }
        .buttonStyle(SanvyaPressStyle())
        .accessibilityLabel(hidden ? S.Dashboard.showAmountsA11y : S.Dashboard.hideAmountsA11y)
    }
}

/**
 Good morning / afternoon / evening / night, on page.tsx's own boundaries:
 < 5 night, < 12 morning, < 17 afternoon, < 21 evening, else night.

 Web's `timeGreeting()` returns four hardcoded English strings — the greeting is
 the one line on its dashboard that never translates. Recorded in
 docs/mobile/PARITY_AUDIT.md under the web defects; both ports use real keys.
 */
private func timeGreeting(hour: Int) -> String {
    switch hour {
    case ..<5: return S.Dashboard.greetingNight
    case ..<12: return S.Dashboard.greetingMorning
    case ..<17: return S.Dashboard.greetingAfternoon
    case ..<21: return S.Dashboard.greetingEvening
    default: return S.Dashboard.greetingNight
    }
}

// MARK: - Accounts strip

/// The dashed "Add" tile that closes web's accounts strip, at the same 112pt
/// footprint as an account so the row does not step at its last item.
private struct AddAccountTile: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 16))
                Text(S.Dashboard.accountsAdd)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.text2)
            .frame(width: 112, minHeight: 58)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .overlay(
                RoundedRectangle(cornerRadius: SanvyaRadius.radiusSm, style: .continuous)
                    .strokeBorder(Color.borderStrong, lineWidth: 1.5)
            )
        }
        .buttonStyle(SanvyaPressStyle())
        .accessibilityLabel(S.Dashboard.accountsAddA11y)
    }
}

// MARK: - Loading

/**
 Widget-shaped placeholders for the first seconds of a returning user's first
 launch — page.tsx's own skeleton block, block for block: a hero, the accounts
 card with six chips, one full-width tile and a pair of half ones.
 */
struct DashboardSkeletonView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SanvyaSkeleton(height: 132, cornerRadius: SanvyaRadius.radiusLg)
                SanvyaCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SanvyaSkeleton(height: 18).frame(width: 120)
                        ForEach(0..<2, id: \.self) { _ in
                            HStack(spacing: 8) {
                                ForEach(0..<3, id: \.self) { _ in
                                    SanvyaSkeleton(height: 58, cornerRadius: SanvyaRadius.radiusSm)
                                }
                            }
                        }
                    }
                }
                SanvyaSkeleton(height: 190, cornerRadius: SanvyaRadius.radiusLg)
                HStack(spacing: 16) {
                    ForEach(0..<2, id: \.self) { _ in
                        SanvyaSkeleton(height: 150, cornerRadius: SanvyaRadius.radiusLg)
                    }
                }
            }
            .padding(16)
        }
    }
}

/// Matches apps/web/app/page.tsx's `balances.length === 0` early return and
/// Android's `EmptyDashboard` (DashboardScreen.kt) copy exactly -- see
/// docs/mobile/screen-specs/dashboard.md "States" #2. Reached only once the
/// local read HAS returned and the first sync HAS landed -- see
/// `DashboardSkeletonView` above, which holds the screen until then.
struct DashboardEmptyStateView: View {
    let onAddAccount: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(S.Onboarding.wtIntroTitle)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(Color.text)
                .multilineTextAlignment(.center)
            Text("Start by adding your first account — just your own note of somewhere your money sits. Nothing here connects to your bank; you type the amounts in yourself.")
                .font(.system(size: 14))
                .foregroundColor(Color.text2)
                .multilineTextAlignment(.center)
            Button(action: onAddAccount) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add your first account")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.accent)
                .foregroundColor(Color.surface)
                .clipShape(Capsule())
            }
        }
        .padding(36)
        .frame(maxWidth: 460)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusLg, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(Color.bg.ignoresSafeArea())
    }
}

#Preview {
    DashboardView(currentTab: .constant(.dashboard))
}

// MARK: - Net-worth hero
// Ported from apps/web/app/page.tsx's NetWorthHero, byte-for-byte on colors/
// copy where SwiftUI can express them directly -- see
// docs/mobile/screen-specs/dashboard.md. Same design, same source, as
// Android's NetWorthHero composable (DashboardScreen.kt), added same session.

// A fresh formatter is allocated per call rather than cached in a global
// `let` -- caching hit a real Swift 6 build error in TransactionsViewModel
// .swift's near-identical `fractionalIsoFormatter` ("not concurrency-safe
// because non-Sendable type '...' may have shared mutable state"; same root
// cause documented in Domain/Sources/Domain/SplitsInsights.swift's
// `parseIsoMillis`). `NumberFormatter` is a Foundation class formatter, same
// non-Sendable shape as `ISO8601DateFormatter` -- fixed preemptively here to
// the same pattern before the real compiler hits it too.
private func formatMinor(_ minor: Int64) -> String {
    formatMoneyAware(Domain.money(minor, baseCurrencyNow()))
}

struct NetWorthHeroView: View {
    let state: NetWorthHeroState
    var hidden: Bool = false
    let onToggle: () -> Void

    var body: some View {
        let up = state.deltaMinor >= 0
        let netText = hidden ? "••••••" : formatMinor(state.net.amount)
        let deltaText = hidden ? "••••" : formatMinor(abs(state.deltaMinor))
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(state.showAvailable ? S.Translation.netWorthAvailable : S.Translation.netWorthTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(Color(red: 0.776, green: 0.804, blue: 0.702)) // #c6cdb3
                Spacer()
                Button(action: onToggle) {
                    Text(state.showAvailable ? "Excluding blocked" : S.Translation.netWorthWithBlocked)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(red: 0.918, green: 0.941, blue: 0.855)) // #eaf0da
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Capsule())
                }
            }
            Text(netText)
                .font(.system(size: 38, weight: .heavy))
                .foregroundColor(Color(red: 0.945, green: 0.929, blue: 0.890)) // #f1ede3
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 6)
            if state.hasTrend {
                Text("\(up ? "+" : "−")\(deltaText) this month")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(up ? Color(red: 0.867, green: 0.906, blue: 0.788) : Color(red: 0.941, green: 0.847, blue: 0.788))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Capsule())
                    .padding(.top, 10)
            }
            if state.sparkline.count >= 2 {
                SparklineView(values: state.sparkline)
                    .frame(height: 56)
                    .padding(.top, 14)
            }
            Text("Base currency \(state.base)")
                .font(.system(size: 12.5))
                .foregroundColor(Color(red: 0.776, green: 0.804, blue: 0.702))
                .padding(.top, 8)
        }
        .padding(EdgeInsets(top: 26, leading: 28, bottom: 22, trailing: 28))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.373, green: 0.400, blue: 0.278), Color(red: 0.243, green: 0.290, blue: 0.220)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusLg, style: .continuous))
    }
}

struct SparklineView: View {
    let values: [Float]

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2 else { return }
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 0
            let range = (maxV - minV) == 0 ? 1 : (maxV - minV)
            let pad: CGFloat = 3
            let points: [CGPoint] = values.enumerated().map { i, v in
                let x = CGFloat(i) / CGFloat(values.count - 1) * size.width
                let y = size.height - pad - CGFloat((v - minV) / range) * (size.height - pad * 2)
                return CGPoint(x: x, y: y)
            }
            var line = Path()
            line.move(to: points[0])
            for p in points.dropFirst() { line.addLine(to: p) }

            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()

            context.fill(
                area,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.776, green: 0.804, blue: 0.702).opacity(0.5),
                        Color(red: 0.776, green: 0.804, blue: 0.702).opacity(0),
                    ]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
            context.stroke(line, with: .color(Color(red: 0.918, green: 0.941, blue: 0.855)), lineWidth: 2.2)
        }
    }
}

// accountColor()/colorForId()/Color(hex:) now shared -- see
// AccountColors.swift (extracted 2026-08-05 when the Accounts screen needed
// the same palette; this file used to have its own private copy).
