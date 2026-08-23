import SwiftUI

/**
 The rotating ring spinner: an `--accent-ghost` track with an `--accent` arc,
 one turn every 800ms, linear.

 Not `ProgressView()` — the system indicator is a different shape and its
 animation is platform-owned, so it would read as a different app's loader.
 */
public struct SanvyaSpinner: View {
    @State private var spinning = false
    private let size: CGFloat
    private let stroke: CGFloat

    public init(size: CGFloat = 28, stroke: CGFloat = 3) {
        self.size = size
        self.stroke = stroke
    }

    public var body: some View {
        ZStack {
            Circle().strokeBorder(Color.accentGhost, lineWidth: stroke)
            // A quarter turn of accent — web colours only `border-top-color`.
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(Color.accent, style: StrokeStyle(lineWidth: stroke, lineCap: .butt))
                .padding(stroke / 2)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: spinning)
        }
        .frame(width: size, height: size)
        .onAppear { spinning = true }
        .accessibilityHidden(true)
    }
}

/// Full-area centred loader with an optional label.
public struct SanvyaLoading: View {
    private let label: String?
    public init(label: String? = nil) { self.label = label }

    public var body: some View {
        VStack(spacing: 14) {
            SanvyaSpinner(size: 34)
            if let label {
                Text(label)
                    .sanvyaStyle(SanvyaType.chip)
                    .foregroundStyle(Color.text2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label ?? "Loading")
    }
}

/**
 `.skeleton` — a recessed block pulsing between 0.5 and 1 opacity on a 1.4s
 cycle. Web layers a sweeping gradient over it; the opacity pulse is the same
 rhythm without a shader and reads identically at list scale.
 */
public struct SanvyaSkeleton: View {
    @State private var pulsing = false
    private let height: CGFloat
    private let cornerRadius: CGFloat

    public init(height: CGFloat = 16, cornerRadius: CGFloat = 8) {
        self.height = height
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.surface2)
            .frame(height: height)
            .opacity(pulsing ? 1 : 0.5)
            .animation(
                .easeInOut(duration: SanvyaMotion.shimmerDuration / 2).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear { pulsing = true }
            .accessibilityHidden(true)
    }
}

/// Animated 0–100 bar. `color` signals threshold/over states, as on web.
public struct SanvyaProgressBar: View {
    private let pct: Double
    private let color: Color?
    private let height: CGFloat

    public init(pct: Double, color: Color? = nil, height: CGFloat = 10) {
        self.pct = pct
        self.color = color
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.surface2)
                Capsule()
                    .fill(color ?? Color.accent)
                    .frame(width: geo.size.width * min(max(pct, 0), 100) / 100)
            }
        }
        .frame(height: height)
        .animation(SanvyaMotion.standard(0.4), value: pct)
        .accessibilityValue("\(Int(min(max(pct, 0), 100)))%")
    }
}
