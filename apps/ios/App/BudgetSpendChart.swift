import SwiftUI
import Domain

/// The plot area's height. Web's `ResponsiveContainer height={120}` less the
/// row of date labels, which recharts draws inside its own 120.
private let plotHeight: CGFloat = 96

/**
 The cumulative spend-vs-limit curve on a budget card — web's
 `BudgetSpendChart` in apps/web/app/budgets/page.tsx (a recharts `AreaChart`
 with a dashed `ReferenceLine` at the limit).

 NOT added to `Components/SanvyaCharts.swift`. That file draws `VisualSpec`, the
 insight/dashboard shape, which has no reference line and no date axis; a
 budget-shaped variant there would either widen `VisualSpec` for one caller or
 sit beside it as a second unrelated API. No charting dependency either way —
 this is the same `Canvas` the rest of the chart layer uses, with its text as
 real `Text` views around it.

 Deliberate faithfulness to two of recharts' quirks:

 - **The Y domain is `[0, max(cum)]`,** recharts' default for an area whose
   values are all positive.
 - **The limit line is DISCARDED when it falls outside that domain.** That is
   recharts' `ifOverflow="discard"` default for `ReferenceLine`, and it is why
   the dashed line only appears once spending is in the neighbourhood of the
   limit. Drawing it always would rescale the axis and squash every real
   budget's curve into the bottom few pixels.

 The one addition: a tap or drag picks a point and prints its running total.
 That is the mobile equivalent of the `Tooltip` web gets from hover, and it goes
 through `formatMoney`, so the reading is masked when hide-amounts is on — web's
 tooltip prints the raw number regardless, which is the leak class
 PARITY_AUDIT trap 7 is about.

 Mirrors `apps/android/.../ui/budgets/BudgetSpendChart.kt`.
 */
struct BudgetSpendChart: View {
    let series: [SpendPoint]
    let limitMinor: Int64
    let currency: String
    let tint: Color

    @State private var selected: Int?

    private var values: [Double] {
        // `majorScale`, not `/ 100`: a JPY budget drawn against a hundredth of
        // its real limit would put every curve on the floor.
        let scale = majorScale(currency)
        return series.map { Double($0.cumulativeMinor) / scale }
    }

    private var limitMajor: Double { Double(limitMinor) / majorScale(currency) }

    /// A budget with no spend at all still draws: a flat line on the floor is
    /// the honest picture, where an auto-scaled empty domain would put a
    /// meaningless line through the middle of the card.
    private var top: Double {
        let maxValue = values.max() ?? 0
        return maxValue > 0 ? maxValue : 1
    }

    private var limitVisible: Bool { limitMinor > 0 && limitMajor <= top }

    private var dayLabels: [String] { series.map { dayMonthLabel($0.dayIso) } }

    var body: some View {
        // Web returns null below two points: one dot is not a trend, and the
        // axis has nothing to span.
        if series.count < 2 {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                plot
                axis
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(S.Budgets.spendChartAria)
        }
    }

    private var plot: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let stepX = series.count > 1 ? width / CGFloat(series.count - 1) : width
            let ys = values.map { height - CGFloat($0 / top) * height }

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let line = monotonePath(count: series.count, x: { CGFloat($0) * stepX }, y: { ys[$0] })
                    var fill = line
                    fill.addLine(to: CGPoint(x: CGFloat(series.count - 1) * stepX, y: size.height))
                    fill.addLine(to: CGPoint(x: 0, y: size.height))
                    fill.closeSubpath()

                    context.fill(
                        fill,
                        // Web's gradient stops exactly: 0.35 at the curve, 0.02
                        // at the baseline.
                        with: .linearGradient(
                            Gradient(colors: [tint.opacity(0.35), tint.opacity(0.02)]),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: 0, y: size.height)
                        )
                    )
                    context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    // recharts discards a reference line outside the domain; so
                    // does this. See the doc comment.
                    if limitVisible {
                        let y = size.height - CGFloat(limitMajor / top) * size.height
                        var rule = Path()
                        rule.move(to: CGPoint(x: 0, y: y))
                        rule.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(
                            rule,
                            with: .color(Color.text2.opacity(0.7)),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                    }

                    if let index = selected, index < ys.count {
                        let x = CGFloat(index) * stepX
                        var marker = Path()
                        marker.move(to: CGPoint(x: x, y: 0))
                        marker.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(marker, with: .color(Color.border), style: StrokeStyle(lineWidth: 1))
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - 3, y: ys[index] - 3, width: 6, height: 6)),
                            with: .color(tint)
                        )
                    }
                }
                .contentShape(Rectangle())
                // `minimumDistance: 0` so one gesture serves both a tap and a
                // scrub — SwiftUI has no hover on a phone, and two gestures
                // would fight over the same touch.
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in selected = nearestIndex(value.location.x, width) }
                )

                if limitVisible {
                    Text(S.Budgets.spendChartLimit(amount: formatMoney(limitMinor, currency)))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.text2)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        // Just above its own line, clamped so a limit already
                        // reached does not push the label off the card.
                        .offset(y: max(0, height - CGFloat(limitMajor / top) * height - 13))
                }

                if let index = selected, index < series.count {
                    // Pinned top-leading rather than following the touch: a
                    // floating label near the right edge of a phone-width card
                    // clips, and web's tooltip has a cursor to anchor to that a
                    // finger does not.
                    Text("\(dayLabels[index]) · \(formatMoney(series[index].cumulativeMinor, currency))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.text)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.surface2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
        .frame(height: plotHeight)
    }

    /// Web's `interval="preserveStartEnd"` with `minTickGap={24}`: the ends
    /// always, and the middle one only when there is room for it. Three labels
    /// is what recharts settles on at a phone-width card, and an HStack cannot
    /// overlap them the way absolute tick positions can.
    private var axis: some View {
        HStack {
            Text(dayLabels.first ?? "")
            if dayLabels.count >= 5 {
                Spacer()
                Text(dayLabels[dayLabels.count / 2])
            }
            Spacer()
            Text(dayLabels.last ?? "")
        }
        .font(.system(size: 10))
        .foregroundStyle(Color.text2)
    }

    /// The point nearest a touch, so a tap between two days picks the closer one.
    private func nearestIndex(_ x: CGFloat, _ width: CGFloat) -> Int {
        guard series.count > 1, width > 0 else { return 0 }
        let step = width / CGFloat(series.count - 1)
        let lower = min(max(Int(x / step), 0), series.count - 1)
        // `Int()` truncates, so check the next point too rather than always
        // snapping backwards.
        let upper = min(lower + 1, series.count - 1)
        return abs(x - CGFloat(upper) * step) < abs(x - CGFloat(lower) * step) ? upper : lower
    }
}

/**
 A smooth path through the points — recharts' `type="monotone"`.

 Fritsch-Carlson monotone cubic interpolation: control points are damped so a
 segment can never overshoot its endpoints. That matters here more than it
 looks. The series is a CUMULATIVE total and so is non-decreasing, and a plain
 Catmull-Rom spline dips below a flat stretch — drawing a day on which the user
 appears to have un-spent money.

 Mirrors `monotonePath` in Android's BudgetSpendChart.kt.
 */
private func monotonePath(count: Int, x: (Int) -> CGFloat, y: (Int) -> CGFloat) -> Path {
    var path = Path()
    guard count > 0 else { return path }
    path.move(to: CGPoint(x: x(0), y: y(0)))
    guard count > 1 else { return path }

    // Secant slopes between consecutive points.
    var slopes: [CGFloat] = []
    for i in 0..<(count - 1) {
        let dx = x(i + 1) - x(i)
        slopes.append(dx == 0 ? 0 : (y(i + 1) - y(i)) / dx)
    }
    // Tangents: the average of the neighbouring secants, flattened wherever the
    // curve changes direction.
    var tangents = [CGFloat](repeating: 0, count: count)
    tangents[0] = slopes[0]
    tangents[count - 1] = slopes[count - 2]
    if count > 2 {
        for i in 1..<(count - 1) {
            tangents[i] = slopes[i - 1] * slopes[i] <= 0 ? 0 : (slopes[i - 1] + slopes[i]) / 2
        }
    }
    // Fritsch-Carlson damping: keep each tangent inside three times its secant.
    for i in 0..<(count - 1) {
        if slopes[i] == 0 {
            tangents[i] = 0
            tangents[i + 1] = 0
        } else {
            let a = tangents[i] / slopes[i]
            let b = tangents[i + 1] / slopes[i]
            let h = a * a + b * b
            if h > 9 {
                let t = 3 / sqrt(h)
                tangents[i] = t * a * slopes[i]
                tangents[i + 1] = t * b * slopes[i]
            }
        }
    }
    for i in 0..<(count - 1) {
        let x0 = x(i)
        let x1 = x(i + 1)
        let dx = (x1 - x0) / 3
        path.addCurve(
            to: CGPoint(x: x1, y: y(i + 1)),
            control1: CGPoint(x: x0 + dx, y: y(i) + tangents[i] * dx),
            control2: CGPoint(x: x1 - dx, y: y(i + 1) - tangents[i + 1] * dx)
        )
    }
    return path
}
