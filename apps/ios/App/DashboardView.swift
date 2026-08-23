import SwiftUI
import Factory

/// Wraps a `String` for `.fullScreenCover(item:)`, which needs `Identifiable`
/// -- used to present ReceiptReviewView keyed by scan id (task #62).
private struct IdentifiableString: Identifiable {
    let value: String
    var id: String { value }
}

struct DashboardView: View {
    @Binding var isDrawerOpen: Bool
    @State private var viewModel = Container.shared.dashboardViewModel()
    // Hide-amounts is a real, load-bearing toggle (Settings > "Hide Amounts",
    // apps/web's useMoneyFmt()) -- was missing entirely from this screen
    // until 2026-08-05 (found auditing for the Accounts screen pass, fixed
    // here since it's the same hero/accounts-strip code this file already
    // owns). Mirrors Android's Prefs.amountsHidden the same way.
    @StateObject private var prefs = Prefs.shared
    // Both the empty-state CTA and the header "+ Account" button open the
    // same sheet -- matches AccountsView.swift's existing
    // showingCreateSheet/CreateAccountView() pattern (no dedicated NavTab
    // exists for "create account", so every other screen that offers this
    // action does it the same way).
    @State private var showingCreateAccountSheet = false
    // Speed dial -- real port of AddSpeedDial (apps/web/app/AppShell.tsx),
    // Dashboard-only on web (`pathname === "/"`), and the first quick-add
    // control on either mobile platform (task #62 -- verified by grep, no
    // FAB/SpeedDial symbol existed before this). See
    // docs/mobile/screen-specs/receipt-scan.md.
    @State private var speedDialOpen = false
    @State private var showingAddTransactionSheet = false
    @State private var showingReceiptCapture = false
    @State private var reviewingScanId: String?

    var body: some View {
        NavigationStack {
            Group {
                // Empty/onboarding state -- apps/web/app/page.tsx's
                // `balances.length === 0` early return, matching Android's
                // EmptyDashboard (DashboardScreen.kt). Was missing entirely
                // on iOS (found 2026-08-06, Akhilesh: "if we don't have an
                // account I am not getting the add your account first card
                // like android") -- the populated layout below rendered
                // unconditionally even with zero accounts, showing a ₹0.00
                // hero with no sparkline (correctly per spec -- fewer than 2
                // months of data -- but with nothing explaining why, since
                // there was no accounts-yet messaging at all).
                if viewModel.accounts.isEmpty {
                    DashboardEmptyStateView(onAddAccount: { showingCreateAccountSheet = true })
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
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
                                    Text("Accounts")
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(Color.text)
                                    Spacer()
                                    Button(action: {}) {
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(Color.text2)
                                    }
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
                                    }
                                }
                            }

                            // Tile catalog (recent/spending/trends/budgets/goals/
                            // etc.) is explicitly deferred -- see
                            // docs/mobile/screen-specs/dashboard.md "Explicitly
                            // deferred". This card says so instead of silently
                            // omitting the section or faking a grid -- matches
                            // Android's DashboardScreen.kt card exactly (found
                            // missing on iOS 2026-08-06, Akhilesh: "I don't see
                            // an option to add widgets").
                            WidgetsComingSoonCard()
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Sanvya")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation(.spring()) {
                            isDrawerOpen.toggle()
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .imageScale(.large)
                    }
                }
                // Hide/Show -- apps/web/app/page.tsx's header chip row has
                // Customize/Hide-Show/Account+; Android's toolbar
                // (DashboardScreen.kt) only ported the hide/show eye-toggle
                // of those three (plus Transactions/Settings icons, which
                // duplicate paths the hamburger drawer already covers on
                // both platforms). Matching Android's actual header exactly
                // here rather than the fuller web spec, so the two mobile
                // apps stay in lockstep -- "Customize" and a header
                // "+Account" are both skipped for the same reason Android
                // skipped them: account creation is already one tap away
                // (empty-state CTA when there are none, Accounts screen's
                // own "+" once there are some), and Customize has nothing
                // to open until the tile catalog itself is built.
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        prefs.amountsHidden.toggle()
                    } label: {
                        Image(systemName: prefs.amountsHidden ? "eye" : "eye.slash")
                            .foregroundColor(Color.text2)
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) { speedDial }
        .sheet(isPresented: $showingCreateAccountSheet) {
            CreateAccountView()
        }
        .sheet(isPresented: $showingAddTransactionSheet) {
            CreateTransactionView()
        }
        .fullScreenCover(isPresented: $showingReceiptCapture) {
            ReceiptCaptureView(
                onScanned: { scanId in
                    showingReceiptCapture = false
                    reviewingScanId = scanId
                },
                onCancel: { showingReceiptCapture = false }
            )
        }
        .fullScreenCover(item: Binding(
            get: { reviewingScanId.map { IdentifiableString(value: $0) } },
            set: { reviewingScanId = $0?.value }
        )) { wrapped in
            ReceiptReviewView(
                scanId: wrapped.value,
                onSaved: { _ in reviewingScanId = nil },
                onCancel: { reviewingScanId = nil }
            )
        }
        .onAppear {
            viewModel.start()
        }
        .onDisappear {
            viewModel.cancel()
        }
    }

    @ViewBuilder
    private var speedDial: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if speedDialOpen {
                speedDialAction(icon: "doc.text.viewfinder", label: "Scan bill / receipt") {
                    speedDialOpen = false
                    showingReceiptCapture = true
                }
                speedDialAction(icon: "plus", label: "Add transaction") {
                    speedDialOpen = false
                    showingAddTransactionSheet = true
                }
            }
            Button(action: { withAnimation(.spring()) { speedDialOpen.toggle() } }) {
                Image(systemName: speedDialOpen ? "xmark" : "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.accent)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            }
        }
        .padding(20)
    }

    private func speedDialAction(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label).font(.caption).fontWeight(.semibold).foregroundColor(.text)
                Image(systemName: icon).foregroundColor(.text)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.surface)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        }
    }

    /// Amounts here are in the user's base currency, not always INR — the old
    /// local formatter hardcoded both the currency and ÷100.
    private func formatCents(_ cents: Int64) -> String {
        formatMoneyUnmasked(Domain.money(cents, baseCurrencyNow()))
    }
}

/// Matches apps/web/app/page.tsx's `balances.length === 0` early return and
/// Android's `EmptyDashboard` (DashboardScreen.kt) copy exactly -- see
/// docs/mobile/screen-specs/dashboard.md "States" #2. Not gated on a
/// separate loading flag (web distinguishes loading-skeleton vs. empty to
/// avoid an initial-sync flash; Android's port already accepted that
/// simplification -- see dashboard.md "Explicitly deferred" -- matching it
/// here for cross-platform consistency rather than reintroducing a
/// three-state gate on only one platform).
struct DashboardEmptyStateView: View {
    let onAddAccount: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Welcome to Sanvya")
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

/// Stand-in for the deferred 12-tile customizable grid -- matches Android's
/// DashboardScreen.kt "More widgets coming soon" card exactly (word for
/// word), so the two platforms say the same thing rather than one being
/// silent about it.
struct WidgetsComingSoonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("More widgets coming soon")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.text)
            Text("Spending, budgets, goals, and trend tiles are on the way.")
                .font(.system(size: 13))
                .foregroundColor(Color.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusLg, style: .continuous))
    }
}

#Preview {
    DashboardView(isDrawerOpen: .constant(false))
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
                Text(state.showAvailable ? "AVAILABLE NET WORTH" : "NET WORTH")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(Color(red: 0.776, green: 0.804, blue: 0.702)) // #c6cdb3
                Spacer()
                Button(action: onToggle) {
                    Text(state.showAvailable ? "Excluding blocked" : "Including blocked")
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
