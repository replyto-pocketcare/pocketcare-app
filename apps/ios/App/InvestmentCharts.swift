import SwiftUI
import Domain

/// The two Investments-only charts, and only the two.
///
/// The donut, the area and the plain bars all already exist in
/// `Components/SanvyaCharts.swift` and are reused as-is -- adding a charting
/// dependency for a screen the app can already draw would be the expensive way
/// to get the same picture, and the palette would stop matching Insights.
///
/// What SanvyaCharts genuinely cannot draw is a SIGNED bar. `SanvyaBarsChart`
/// scales every bar as `value / max` from a zero baseline, so a losing group
/// renders at a negative height -- which clamps to nothing, and the loss
/// disappears from a chart whose entire subject is gains and losses. Hence
/// `SignedBarsChart`.
///
/// The donut gets a LEGEND here rather than the tooltip web uses: a tooltip
/// needs a hover, and a phone has none, so on native the labels have to be on
/// the screen or they do not exist.
///
/// Mirrors Android's `ui/investments/InvestmentCharts.kt`.

/// A slice as the donut and its legend need it.
struct DonutSlice: Identifiable {
    let label: String
    let valueMajor: Double
    let amountFormatted: String
    let sharePct: Double
    var id: String { label }
}

/// Allocation donut plus an on-screen legend.
///
/// `centerLabel`/`centerValue` are web's centred total. The legend shows each
/// slice's own formatted amount rather than recomputing one, so the masking
/// rule (hide-amounts) is honoured here exactly as it is everywhere else.
struct AllocationDonut: View {
    let slices: [DonutSlice]
    let centerLabel: String
    let centerValue: String
    let emptyLabel: String

    var body: some View {
        if slices.isEmpty {
            Text(emptyLabel)
                .font(.footnote)
                .foregroundColor(Color.text3)
                .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            VStack(spacing: 12) {
                SanvyaDonutChart(
                    series: slices.map { SeriesPoint($0.label, $0.valueMajor) },
                    centerLabel: centerValue,
                    centerSub: centerLabel,
                    accent: Color.accent
                )
                .frame(height: 200)
                VStack(spacing: 6) {
                    ForEach(Array(slices.enumerated()), id: \.offset) { i, s in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(resolveChartColor(nil, i, Color.accent))
                                .frame(width: 9, height: 9)
                            Text(s.label).font(.caption).foregroundColor(Color.text).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(Int(s.sharePct.rounded()))%").font(.caption).foregroundColor(Color.text2)
                            Text(s.amountFormatted).font(.caption).fontWeight(.semibold).foregroundColor(Color.text)
                        }
                    }
                }
            }
        }
    }
}

/// One signed bar: a gain (positive) or a loss (negative).
struct SignedBar: Identifiable {
    let label: String
    let valueMajor: Double
    let amountFormatted: String
    let positive: Bool
    var id: String { label }
}

/// Diverging horizontal bars around a centre line.
///
/// Horizontal, where web is vertical, on purpose: group labels here are
/// exchange codes and scheme names, which do not fit under a vertical bar on a
/// phone without rotating them (web angles them -18 degrees, which needs the
/// width a desktop has). The information -- sign, magnitude, ranking -- is the
/// same, and this is the orientation `SanvyaBarsChart` already offers for the
/// same reason.
struct SignedBarsChart: View {
    let bars: [SignedBar]
    let emptyLabel: String

    var body: some View {
        if bars.isEmpty {
            Text(emptyLabel)
                .font(.footnote)
                .foregroundColor(Color.text3)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            // One scale for both directions, so a small loss cannot render
            // longer than a large gain. `max(..., 1)` keeps an all-zero
            // portfolio from dividing by zero rather than special-casing it.
            let peak = max(bars.map { abs($0.valueMajor) }.max() ?? 1, 1)
            VStack(spacing: 10) {
                ForEach(bars) { b in
                    let fraction = min(max(abs(b.valueMajor) / peak, 0), 1)
                    let tint = b.positive ? Color.positive : Color.negative
                    VStack(spacing: 4) {
                        HStack {
                            Text(b.label).font(.caption).foregroundColor(Color.text2).lineLimit(1)
                            Spacer()
                            Text(b.amountFormatted).font(.caption).fontWeight(.semibold).foregroundColor(tint)
                        }
                        // Two half-width tracks meeting at the middle: the left
                        // half fills leftwards for a loss, the right half
                        // rightwards for a gain, so the zero line is a real,
                        // fixed position on screen rather than wherever the
                        // data happens to put it.
                        GeometryReader { geo in
                            let half = max((geo.size.width - 1) / 2, 0)
                            HStack(spacing: 0) {
                                HStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    if !b.positive {
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(tint)
                                            .frame(width: half * fraction)
                                    }
                                }
                                .frame(width: half)
                                Rectangle().fill(Color.borderStrong).frame(width: 1)
                                HStack(spacing: 0) {
                                    if b.positive {
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(tint)
                                            .frame(width: half * fraction)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(width: half)
                            }
                        }
                        .frame(height: 10)
                    }
                }
            }
        }
    }
}
