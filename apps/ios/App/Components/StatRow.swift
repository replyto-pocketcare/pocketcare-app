import SwiftUI
import Domain

/**
 The wide-window KPI strip — four headline figures across the top of the
 dashboard, each with a period-over-period delta. A port of
 `apps/web/src/ui/desktop/StatRow.tsx`.

 **Only at `.expanded`, and this is not an optimisation.** On an iPhone the strip
 would repeat the net-worth hero directly beneath it in a smaller font; web
 mounts it behind `useIsDesktop()` for the same reason and says so. The gate here
 is `sanvyaWindowClass` rather than a point width, because that is the app's
 existing answer to "is there room for a second layout" and web's 1024px CSS
 breakpoint is not a number an iPad is measured in.

 All four figures are MINOR units all the way to `formatMoney`; the count-up
 animates the minor integer and rounds back to an `Int64` before formatting, so a
 zero-decimal currency never gains a fractional step mid-tween.

 Mirrors apps/android/.../ui/dashboard/StatRow.kt.
 */
struct StatRow: View {
    let stats: DashboardStats
    let hidden: Bool

    private var currentNet: Int64 { stats.currentIncomeMinor - stats.currentExpenseMinor }
    private var previousNet: Int64 { stats.previousIncomeMinor - stats.previousExpenseMinor }

    private var cards: [StatCardData] {
        [
            // Net worth has no meaningful stored "last month" figure, so it
            // compares against itself minus this month's movement — i.e. where
            // it started.
            StatCardData(
                key: "net",
                label: S.Dashboard.statNetWorth,
                glyph: SanvyaIcons.accountBalance,
                tint: .forest,
                minor: stats.netMinor,
                previousMinor: stats.netMinor - currentNet
            ),
            StatCardData(
                key: "inc",
                label: S.Dashboard.statIncome,
                glyph: SanvyaIcons.trendingUp,
                tint: .positive,
                minor: stats.currentIncomeMinor,
                previousMinor: stats.previousIncomeMinor
            ),
            StatCardData(
                key: "exp",
                label: S.Dashboard.statSpending,
                glyph: SanvyaIcons.payments,
                tint: .negative,
                minor: stats.currentExpenseMinor,
                previousMinor: stats.previousExpenseMinor,
                // "Good" is not the same as "up": more spending is a worse
                // month, so the pill's colour follows the meaning while the
                // arrow follows the direction.
                inverse: true
            ),
            StatCardData(
                key: "sav",
                label: S.Dashboard.statSaved,
                glyph: SanvyaIcons.savings,
                tint: .teal,
                minor: currentNet,
                previousMinor: previousNet
            ),
        ]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(cards, id: \.key) { card in
                StatCard(card: card, base: stats.base, hidden: hidden)
            }
        }
    }
}

struct StatCardData {
    let key: String
    let label: String
    let glyph: String
    let tint: Color
    /// Current-period figure, in MINOR units.
    let minor: Int64
    /// Previous-period figure, in MINOR units — drives the delta pill.
    let previousMinor: Int64
    /// When true a RISE is bad (spending). Flips the pill's colour only.
    var inverse: Bool = false
}

private struct StatCard: View {
    let card: StatCardData
    let base: String
    let hidden: Bool

    /// Whether the device is set to reduce motion — iOS's own
    /// `prefers-reduced-motion: reduce`. Someone who asked for less movement
    /// gets the final figure immediately rather than a 900 ms tween.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Starts at zero and is raised on appear, which is what makes the number
    /// count up. Held as a `Double` because that is what SwiftUI can
    /// interpolate; it is rounded back to minor units before it is formatted.
    @State private var shown: Double = 0

    /// Null when there is nothing to divide by: a first month has no percentage,
    /// and "+100%" against zero is a lie dressed as a fact.
    private var percent: Double? {
        guard card.previousMinor != 0 else { return nil }
        return (Double(card.minor - card.previousMinor) / Double(abs(card.previousMinor))) * 100
    }

    private var rose: Bool { (percent ?? 0) >= 0 }
    private var good: Bool { card.inverse ? !rose : rose }

    private var animate: Bool { !hidden && !reduceMotion }

    var body: some View {
        SanvyaCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(card.label)
                        .sanvyaStyle(SanvyaType.statLabel)
                        .foregroundStyle(Color.text2)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    SanvyaIconView(card.glyph, size: 16, tint: card.tint)
                        .frame(width: 26, height: 26)
                        // Web tints the chip with `color-mix(... 16%,
                        // transparent)`. A 16% opacity of the same colour over
                        // the card is the same result without a colour-space
                        // function SwiftUI lacks.
                        .background(card.tint.opacity(0.16))
                        .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusSm, style: .continuous))
                }

                HStack(spacing: 8) {
                    Text(hidden ? hiddenAmount : formatMoney(Int64(shown.rounded()), base))
                        .sanvyaStyle(SanvyaType.statValue)
                        .foregroundStyle(Color.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let percent, !hidden {
                        // The arrow is direction, the colour is meaning — see
                        // `inverse` above.
                        Text("\(rose ? "▲" : "▼") \(percentText(abs(percent)))")
                            .sanvyaStyle(SanvyaType.statLabel)
                            .foregroundStyle(good ? Color.positive : Color.negative)
                    }
                }
                .padding(.top, 6)

                Text(hidden
                     ? S.Dashboard.statHidden
                     : S.Dashboard.statVsLastMonth(amount: formatMoney(card.previousMinor, base)))
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.text3)
                    .lineLimit(1)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { raise() }
        .onChange(of: card.minor) { _, _ in raise() }
        .onChange(of: hidden) { _, _ in raise() }
    }

    /// Web's easing is `easeOutExpo` over 900 ms — fast out of the gate, long
    /// settle, so it reads as "landing on" a figure rather than as an odometer
    /// roll. `.timingCurve(0.16, 1, 0.3, 1)` is the closest standard curve and
    /// is the shape the app's own page-in transition already uses.
    private func raise() {
        guard animate else {
            shown = Double(card.minor)
            return
        }
        shown = 0
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.9)) {
            shown = Double(card.minor)
        }
    }
}

/// Web's `••••••` mask, the same string the hero and the account chips use.
private let hiddenAmount = "••••••"

/// Web prints `toFixed(1)` and a percent sign.
private func percentText(_ value: Double) -> String {
    String(format: "%.1f%%", value)
}
