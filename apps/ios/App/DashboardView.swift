import SwiftUI
import Factory

struct DashboardView: View {
    @Binding var isDrawerOpen: Bool
    @State private var viewModel = Container.shared.dashboardViewModel()
    // Hide-amounts is a real, load-bearing toggle (Settings > "Hide Amounts",
    // apps/web's useMoneyFmt()) -- was missing entirely from this screen
    // until 2026-08-05 (found auditing for the Accounts screen pass, fixed
    // here since it's the same hero/accounts-strip code this file already
    // owns). Mirrors Android's Prefs.amountsHidden the same way.
    @StateObject private var prefs = Prefs.shared

    var body: some View {
        NavigationStack {
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

                    // Quick Actions
                    HStack(spacing: 16) {
                        Spacer()
                        QuickActionButtonView(icon: "plus", label: "Expense")
                        Spacer()
                        QuickActionButtonView(icon: "arrow.triangle.2.circlepath", label: "Transfer")
                        Spacer()
                        QuickActionButtonView(icon: "person.2", label: "Settle Up")
                        Spacer()
                    }

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

                    // Recent Activity Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Activity")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(Color.text)

                        ForEach(viewModel.recentTransactions) { txn in
                            RowTile(
                                title: txn.description,
                                subtitle: txn.date,
                                trailing: {
                                    Text(txn.amount)
                                        .font(.body)
                                        .fontWeight(.bold)
                                        .foregroundColor(txn.isIncome ? Color.positive : Color.text)
                                }
                            )
                        }
                    }
                }
                .padding(16)
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
            }
        }
        .onAppear {
            viewModel.start()
        }
        .onDisappear {
            viewModel.cancel()
        }
    }
    
    private func formatCents(_ cents: Int64) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "INR"
        fmt.maximumFractionDigits = 2
        fmt.locale = Locale(identifier: "en_IN")
        return fmt.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "₹0.00"
    }
}

struct QuickActionButtonView: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color.accent)
                .frame(width: 50, height: 50)
                .background(Color.surface)
                .clipShape(Circle())

            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(Color.text)
        }
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
    let fmt = NumberFormatter()
    fmt.numberStyle = .currency
    fmt.currencyCode = "INR"
    fmt.maximumFractionDigits = 2
    fmt.locale = Locale(identifier: "en_IN")
    return fmt.string(from: NSNumber(value: Double(minor) / 100.0)) ?? "₹0.00"
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
