import SwiftUI
import Domain

/**
 The chart primitives — bars, area, donut, gauge, progress.

 All five lived `private` inside `InsightsView.swift`, which is why this audit
 kept finding things blocked on them: the Recurring direction screen's category
 donut has been recorded as absent since 2026-08-24 for exactly this reason, and
 six of the dashboard's fourteen tiles need bars or an area. Nothing was wrong
 with the charts. They were simply unreachable.

 They take `SeriesPoint` and `VisualSpec` from `Domain`, which both already
 lived there, so moving the drawing here creates no new coupling — it only
 removes the accident that the drawing lived inside one screen.

 Mirrors `apps/android/.../ui/components/Charts.kt`.
 */

func resolveChartColor(_ token: String?, _ index: Int, _ fallback: Color) -> Color {
    switch token {
    case "positive": return Color.positive
    case "warning": return Color.warning
    case "negative": return Color.negative
    case "forest": return Color.forest
    case "accent": return Color.accent
    case "border": return Color.border
    case nil: return chartColors[index % chartColors.count]
    default: return fallback
    }
}

struct SanvyaVisualChart: View {
    let visual: VisualSpec
    let accent: Color

    var body: some View {
        switch visual {
        case .bars(let series, let unit, let horizontal):
            SanvyaBarsChart(series: series, unit: unit, horizontal: horizontal, accent: accent)
        case .area(let series):
            SanvyaAreaChart(series: series, accent: accent)
        case .donut(let series, let centerLabel, let centerSub):
            SanvyaDonutChart(series: series, centerLabel: centerLabel, centerSub: centerSub, accent: accent)
        case .gauge(let value, let gmax, let warnAt, let dangerAt, _, let centerLabel):
            SanvyaGaugeChart(value: value, gmax: gmax, warnAt: warnAt, dangerAt: dangerAt, centerLabel: centerLabel, accent: accent)
        case .progress(let value, let target, let centerLabel):
            SanvyaProgressChart(value: value, target: target, centerLabel: centerLabel, accent: accent)
        }
    }
}

struct SanvyaBarsChart: View {
    let series: [SeriesPoint]
    let unit: String?
    let horizontal: Bool
    let accent: Color

    var body: some View {
        if series.isEmpty {
            EmptyView()
        } else {
            let maxVal = max(series.map(\.value).max() ?? 1, 1e-9)
            GeometryReader { geo in
                if horizontal {
                    VStack(spacing: 8) {
                        ForEach(Array(series.enumerated()), id: \.offset) { i, s in
                            HStack(spacing: 8) {
                                Text(s.label).font(.system(size: 11)).foregroundColor(Color.text2).frame(width: 76, alignment: .leading)
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(resolveChartColor(s.color, i, accent))
                                    .frame(width: max(CGFloat(s.value / maxVal), 0.02) * max(geo.size.width - 84, 0))
                                Spacer(minLength: 0)
                            }
                            .frame(maxHeight: .infinity)
                        }
                    }
                } else {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(Array(series.enumerated()), id: \.offset) { i, s in
                            VStack(spacing: 4) {
                                Spacer(minLength: 0)
                                if s.value != 0 {
                                    Text(fmtCompactChartValue(s.value)).font(.system(size: 9)).foregroundColor(Color.text2)
                                }
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(resolveChartColor(s.color, i, accent))
                                    .frame(height: max(CGFloat(s.value / maxVal), 0.02) * max(geo.size.height - 24, 0))
                                Text(s.label).font(.system(size: 10)).foregroundColor(Color.text2)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: geo.size.height, alignment: .bottom)
                }
            }
        }
    }
}

struct SanvyaAreaChart: View {
    let series: [SeriesPoint]
    let accent: Color

    var body: some View {
        if series.count < 2 {
            EmptyView()
        } else {
            Canvas { context, size in
                let values = series.map(\.value)
                let maxV = values.max() ?? 0
                let minV = min(0, values.min() ?? 0)
                let range = max(maxV - minV, 1e-9)
                let stepX = size.width / CGFloat(series.count - 1)
                func y(_ v: Double) -> CGFloat { size.height - CGFloat((v - minV) / range) * size.height }

                var line = Path()
                var fill = Path()
                for (i, s) in series.enumerated() {
                    let x = CGFloat(i) * stepX
                    let yy = y(s.value)
                    if i == 0 {
                        line.move(to: CGPoint(x: x, y: yy))
                        fill.move(to: CGPoint(x: x, y: size.height))
                        fill.addLine(to: CGPoint(x: x, y: yy))
                    } else {
                        line.addLine(to: CGPoint(x: x, y: yy))
                        fill.addLine(to: CGPoint(x: x, y: yy))
                    }
                }
                fill.addLine(to: CGPoint(x: CGFloat(series.count - 1) * stepX, y: size.height))
                fill.closeSubpath()

                context.fill(fill, with: .color(accent.opacity(0.18)))
                context.stroke(line, with: .color(accent), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
        }
    }
}

struct SanvyaDonutChart: View {
    let series: [SeriesPoint]
    let centerLabel: String?
    let centerSub: String?
    let accent: Color

    var body: some View {
        if series.isEmpty {
            EmptyView()
        } else {
            let total = max(series.reduce(0) { $0 + $1.value }, 1e-9)
            ZStack {
                Canvas { context, size in
                    let stroke = min(size.width, size.height) * 0.16
                    let rect = CGRect(x: stroke / 2, y: stroke / 2, width: size.width - stroke, height: size.height - stroke)
                    var startAngle = -90.0
                    for (i, s) in series.enumerated() {
                        let sweep = s.value / total * 360.0
                        var arc = Path()
                        arc.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2,
                                   startAngle: .degrees(startAngle), endAngle: .degrees(startAngle + sweep * 0.96), clockwise: false)
                        context.stroke(arc, with: .color(resolveChartColor(s.color, i, accent)), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                        startAngle += sweep
                    }
                }
                .padding(12)
                if centerLabel != nil || centerSub != nil {
                    VStack(spacing: 2) {
                        if let c = centerLabel { Text(c).font(.system(size: 20, weight: .bold)).foregroundColor(Color.text) }
                        if let s = centerSub { Text(s).font(.system(size: 11)).foregroundColor(Color.text2) }
                    }
                }
            }
        }
    }
}

struct SanvyaGaugeChart: View {
    let value: Double
    let gmax: Double
    let warnAt: Double?
    let dangerAt: Double?
    let centerLabel: String?
    let accent: Color

    var body: some View {
        let ratio = gmax > 0 ? min(max(value / gmax, 0), 1) : 0
        let color: Color = {
            if value >= (dangerAt ?? gmax) { return Color.negative }
            if value >= (warnAt ?? gmax * 0.8) { return Color.warning }
            return accent
        }()
        ZStack {
            Canvas { context, size in
                let stroke = min(size.width, size.height) * 0.14
                let rect = CGRect(x: stroke / 2, y: stroke / 2, width: size.width - stroke, height: size.height - stroke)
                let start = 150.0, sweepTotal = 240.0
                var track = Path()
                track.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2, startAngle: .degrees(start), endAngle: .degrees(start + sweepTotal), clockwise: false)
                context.stroke(track, with: .color(Color.border), style: StrokeStyle(lineWidth: stroke, lineCap: .round))

                var fillArc = Path()
                fillArc.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2, startAngle: .degrees(start), endAngle: .degrees(start + sweepTotal * ratio), clockwise: false)
                context.stroke(fillArc, with: .color(color), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            }
            .padding(16)
            Text(centerLabel ?? "\(Int(ratio * 100))%").font(.system(size: 22, weight: .bold)).foregroundColor(Color.text)
        }
    }
}

struct SanvyaProgressChart: View {
    let value: Double
    let target: Double?
    let centerLabel: String?
    let accent: Color

    var body: some View {
        let ratio: Double = {
            if let t = target, t > 0 { return min(max(value / t, 0), 1) }
            return 0.5
        }()
        ZStack {
            Canvas { context, size in
                let stroke = min(size.width, size.height) * 0.13
                let rect = CGRect(x: stroke / 2, y: stroke / 2, width: size.width - stroke, height: size.height - stroke)
                var track = Path()
                track.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2, startAngle: .degrees(-90), endAngle: .degrees(270), clockwise: false)
                context.stroke(track, with: .color(Color.border), style: StrokeStyle(lineWidth: stroke, lineCap: .round))

                var fillArc = Path()
                fillArc.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * ratio), clockwise: false)
                context.stroke(fillArc, with: .color(accent), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            }
            .padding(16)
            Text(centerLabel ?? "\(Int(ratio * 100))%").font(.system(size: 22, weight: .bold)).foregroundColor(Color.text)
        }
    }
}

func fmtCompactChartValue(_ v: Double) -> String {
    if v == 0 { return "" }
    if abs(v) >= 1000 {
        let k = v / 1000
        return k == k.rounded() ? "\(Int(k))k" : String(format: "%.1fk", k)
    }
    return v == v.rounded() ? "\(Int(v))" : String(format: "%.0f", v)
}

