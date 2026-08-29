import SwiftUI

/**
 The "goal achieved" moment — web's apps/web/src/goals/GoalCelebration.tsx.

 Web builds a real CSS 3D box with `transform-style: preserve-3d`: the goal tile
 IS the cake's top face, six faces rotate together, and candles stand out of the
 top face in the same 3D space. SwiftUI's `rotation3DEffect` transforms one view
 at a time and does not compose a shared 3D scene across siblings.

 So the scene is decomposed instead of faked, and it is decomposed around the
 SAME angle web animates. `boxRotX` is web's `rotateX` on the box, and every
 other quantity is derived from it:

 - the TILE is one `rotation3DEffect` at `-(boxRotX + 90)`, so it is face-on at
   -90 (web's start: you are looking down at the tile) and foreshortened to
   `|sin(boxRotX)|` at -22 (web's settled pose);
 - the cake BODY is drawn at `|cos(boxRotX)|` of its height, so it is invisible
   at -90 and nearly full at -22 — the body grows out from under the tile
   exactly as the box turns;
 - the CANDLES stand at the tile's far edge, which is `tileHeight *
   |sin(boxRotX)|` above the cake, so they follow the same turn.

 Everything else is web's, unchanged: the 2.5s rise/turn on
 `cubic-bezier(0.22,0.9,0.24,1)`, the two confetti bursts at 520ms and 950ms
 with 170 and 110 particles, gravity and fade over 7s, drag-to-orbit handed over
 at 2.6s (which also cancels the auto-close), the 9s / 4.2s auto-dismiss, and
 the flat reduced-motion card.

 Mirrors `apps/android/.../ui/goals/GoalCelebration.kt`.
 */
struct GoalCelebrationView: View {
    let name: String
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var start = Date()
    @State private var interactive = false
    @State private var orbited = false
    @State private var rotX: Double = -22
    @State private var rotY: Double = 0
    @State private var lastDrag: CGSize = .zero
    @State private var confetti: [Confetto] = buildConfetti()

    var body: some View {
        ZStack {
            // rgba(20,18,16,0.6) — web's scrim exactly.
            Color(.sRGB, red: 0.078, green: 0.071, blue: 0.063, opacity: 0.6)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            if reduceMotion {
                reducedCard
            } else {
                scene
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(S.Goals.celebrationAria(name: name))
        .task {
            // Control is handed over once the entrance has settled — web's
            // 2600ms.
            try? await Task.sleep(for: .milliseconds(2600))
            interactive = true
        }
        .task(id: orbited) {
            // Restarting with `orbited == true` is what cancels the auto-close:
            // the user who is playing with the cake has said they are not done.
            // Web's reduced branch closes at 4.2s where the full one runs to 9s
            // — there is no animation to sit through, only words to read.
            if orbited { return }
            try? await Task.sleep(for: .seconds(reduceMotion ? 4.2 : 9))
            if !Task.isCancelled { onDismiss() }
        }
    }

    /// Web's `if (reduced)` branch: the same words, no motion.
    private var reducedCard: some View {
        VStack(spacing: 8) {
            Text("🎂").font(.system(size: 72))
            Text(S.Goals.achieved.uppercased())
                .font(.system(size: 12, weight: .bold))
                .kerning(1.7)
                .foregroundStyle(Color.accent)
            Text(S.Goals.celebrationName(name: name))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.text)
                .multilineTextAlignment(.center)
            Text(S.Goals.celebrationBody)
                .font(.subheadline)
                .foregroundStyle(Color.text2)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.border, lineWidth: 1))
        .padding(28)
    }

    private var scene: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            let p = celebrationEase(min(1, elapsed / 2.5))
            let boxRotX = interactive ? rotX : entranceTilt(p)
            let spin = interactive ? rotY : entranceSpin(p)

            ZStack {
                Canvas { context, size in
                    drawConfetti(context: context, size: size, particles: confetti, elapsed: elapsed)
                }
                .allowsHitTesting(false)

                VStack(spacing: 18) {
                    ZStack(alignment: .bottom) {
                        Canvas { context, size in
                            drawCakeAndCandles(context: context, size: size, boxRotX: boxRotX, elapsed: elapsed)
                        }
                        .frame(width: stageWidth, height: stageHeight)

                        GoalTileView(name: name)
                            .frame(width: stageWidth, height: tileHeight)
                            // -(boxRotX + 90): face-on at web's -90 start,
                            // foreshortened to the lid at web's -22 finish.
                            .rotation3DEffect(
                                .degrees(-(boxRotX + 90)),
                                axis: (x: 1, y: 0, z: 0),
                                anchor: .bottom,
                                perspective: 0.6
                            )
                            // Rides the cake's growing top edge, against the
                            // same base line the Canvas draws to.
                            .offset(y: -(stageHeight * (1 - baseLine) + cakeThickness * CGFloat(abs(cos(radians(boxRotX))))))
                    }
                    .frame(width: stageWidth, height: stageHeight)
                    .rotation3DEffect(.degrees(spin), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    .offset(y: entranceRise(p))
                    .gesture(orbitGesture)

                    caption
                }
            }
        }
    }

    private var orbitGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard interactive else { return }
                orbited = true
                // `DragGesture` reports a CUMULATIVE translation where web's
                // pointermove reports a delta, so the previous translation is
                // subtracted to get one. Web's own constants follow: 0.4
                // degrees per point, pitch clamped to +/-85 so the scene never
                // flips.
                let dx = value.translation.width - lastDrag.width
                let dy = value.translation.height - lastDrag.height
                lastDrag = value.translation
                rotY += dx * 0.4
                rotX = min(85, max(-85, rotX - dy * 0.4))
            }
            .onEnded { _ in lastDrag = .zero }
    }

    private var caption: some View {
        VStack(spacing: 4) {
            Text(S.Goals.achieved.uppercased())
                .font(.system(size: 13, weight: .bold))
                .kerning(1.8)
                // #f0c419 — web's caption gold, which is not a theme token on
                // either side. See `confettiColors`.
                .foregroundStyle(Color(.sRGB, red: 0.941, green: 0.769, blue: 0.098, opacity: 1))
            Text(S.Goals.celebrationName(name: name))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(interactive ? S.Goals.celebrationHintDrag : S.Goals.celebrationHint)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }
}

/// The goal card that becomes the cake's lid. Web's "TOP FACE = the goal tile".
private struct GoalTileView: View {
    let name: String

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(name).font(.system(size: 18, weight: .bold)).foregroundStyle(Color.text)
                Spacer()
                Text(S.Goals.celebrationTileTag)
                    .font(.system(size: 12, weight: .bold))
                    .kerning(1)
                    .foregroundStyle(Color.accent)
            }
            Spacer()
            VStack(spacing: 8) {
                HStack {
                    Text(S.Goals.celebrationTileFunded).font(.system(size: 13)).foregroundStyle(Color.text2)
                    Spacer()
                    Text(S.Goals.celebrationTilePct).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.text)
                }
                Capsule()
                    .fill(LinearGradient(colors: [Color.sage, Color.accent], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 10)
            }
        }
        .padding(22)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.border, lineWidth: 1))
    }
}

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

private let stageWidth: CGFloat = 300
private let tileHeight: CGFloat = 190
private let cakeThickness: CGFloat = 88
private let candleHeight: CGFloat = 46
/// Tall enough for the tile face-on at the start, which is its largest pose.
private let stageHeight: CGFloat = tileHeight + cakeThickness
/**
 Where the cake's base sits inside the stage.

 Not the very bottom: at rest the candles reach about 200pt above the base, and
 pinning the base to the floor would leave all the slack above the flames and
 none below the plate, so the settled scene reads as sliding off the bottom of
 its own box.
 */
private let baseLine: CGFloat = 0.86

private func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

// ---------------------------------------------------------------------------
// The entrance, from web's `pc-cake-rise` keyframes. Percentages are web's.
// ---------------------------------------------------------------------------

private let riseBreak = 0.22

private func lerp(_ from: Double, _ to: Double, _ t: Double) -> Double {
    from + (to - from) * min(max(t, 0), 1)
}

/// translateY: 44pt below, overshooting to -18pt, settling at 0.
private func entranceRise(_ p: Double) -> CGFloat {
    CGFloat(p < riseBreak ? lerp(44, -18, p / riseBreak) : lerp(-18, 0, (p - riseBreak) / (1 - riseBreak)))
}

/// rotateX: flat on its back until the rise finishes, then up to web's -22.
private func entranceTilt(_ p: Double) -> Double {
    p < riseBreak ? -90 : lerp(-90, -22, (p - riseBreak) / (1 - riseBreak))
}

/// rotateY: a full turn during the same segment.
private func entranceSpin(_ p: Double) -> Double {
    p < riseBreak ? 0 : lerp(0, 360, (p - riseBreak) / (1 - riseBreak))
}

/**
 Web's `cubic-bezier(0.22, 0.9, 0.24, 1)`.

 Hand-solved rather than handed to `Animation.timingCurve`, because the tilt is
 read INSIDE a `Canvas` to size the cake, and SwiftUI does not expose the
 in-flight value of an animation it is driving. Android reaches for Compose's
 `CubicBezierEasing` for the same curve, so the two entrances match.

 Newton-Raphson on x(u) = t, six iterations — the curve is well behaved and this
 converges to well under a pixel of error.
 */
private func celebrationEase(_ t: Double) -> Double {
    func bezier(_ a: Double, _ b: Double, _ u: Double) -> Double {
        let v = 1 - u
        return 3 * v * v * u * a + 3 * v * u * u * b + u * u * u
    }
    func slope(_ a: Double, _ b: Double, _ u: Double) -> Double {
        let v = 1 - u
        return 3 * v * v * a + 6 * v * u * (b - a) + 3 * u * u * (1 - b)
    }
    var u = t
    for _ in 0..<6 {
        let d = slope(0.22, 0.24, u)
        if abs(d) < 1e-6 { break }
        u -= (bezier(0.22, 0.24, u) - t) / d
    }
    return bezier(0.9, 1, min(max(u, 0), 1))
}

// ---------------------------------------------------------------------------
// The cake
// ---------------------------------------------------------------------------

/// Web's frosting band: white icing, a pink drip line at 26-34%, sponge below.
private let icingColor = Color(.sRGB, red: 1.0, green: 0.957, blue: 0.969, opacity: 1)
private let dripColor = Color(.sRGB, red: 0.953, green: 0.788, blue: 0.839, opacity: 1)
private let spongeColor = Color(.sRGB, red: 0.812, green: 0.565, blue: 0.475, opacity: 1)
private let plateColor = Color(.sRGB, red: 0.914, green: 0.894, blue: 0.863, opacity: 1)
private let candlePink = Color(.sRGB, red: 0.957, green: 0.788, blue: 0.859, opacity: 1)
private let candleBlue = Color(.sRGB, red: 0.812, green: 0.878, blue: 0.961, opacity: 1)
private let flameCore = Color(.sRGB, red: 1.0, green: 0.949, blue: 0.659, opacity: 1)
private let flameEdge = Color(.sRGB, red: 1.0, green: 0.416, blue: 0.180, opacity: 1)

/**
 Web places six candles, but at only THREE distinct x positions (34px in from
 each edge and the centre, in a front and a back row). Seen from the front those
 rows sit behind one another, so three columns is the same picture, not a
 reduction.
 */
private let candleSpots: [CGFloat] = [0.113, 0.5, 0.887]

private func drawCakeAndCandles(context: GraphicsContext, size: CGSize, boxRotX: Double, elapsed: TimeInterval) {
    // |cos| of the pitch: the front of the cake is edge-on at -90 and almost
    // square-on at -22, which is what makes the body appear as the tile turns.
    let bodyFactor = CGFloat(abs(cos(radians(boxRotX))))
    // |sin| of the same angle is how much of the tile you still see, and the
    // candles stand at its far edge.
    let tileFactor = CGFloat(abs(sin(radians(boxRotX))))
    guard bodyFactor >= 0.02 else { return }

    let cakeHeight = cakeThickness * bodyFactor
    let bottom = size.height * baseLine
    let top = bottom - cakeHeight
    let corner: CGFloat = 12

    // Plate, a shallow ellipse the cake sits on.
    context.fill(
        Path(ellipseIn: CGRect(x: -8, y: bottom - 7, width: size.width + 16, height: 14)),
        with: .color(plateColor)
    )
    // Web's side faces are `borderRadius: "0 0 12px 12px"` — round at the BASE
    // only. So the bands are painted bottom-up: the sponge carries the rounding
    // and is stretched upward by one corner radius, and each band above it
    // paints over that overhang.
    context.fill(
        Path(roundedRect: CGRect(x: 0, y: top + cakeHeight * 0.34 - corner, width: size.width, height: cakeHeight * 0.66 + corner), cornerRadius: corner),
        with: .color(spongeColor)
    )
    context.fill(
        Path(CGRect(x: 0, y: top + cakeHeight * 0.26, width: size.width, height: cakeHeight * 0.08)),
        with: .color(dripColor)
    )
    context.fill(
        Path(CGRect(x: 0, y: top, width: size.width, height: cakeHeight * 0.26)),
        with: .color(icingColor)
    )

    // Candles rise from the tile's far edge, so they travel with the turn.
    let candleBase = top - tileHeight * tileFactor
    let candleH = candleHeight * bodyFactor
    let candleW: CGFloat = 8
    for (i, fraction) in candleSpots.enumerated() {
        let x = size.width * fraction - candleW / 2
        context.fill(
            Path(roundedRect: CGRect(x: x, y: candleBase - candleH, width: candleW, height: candleH), cornerRadius: 4),
            with: .color(i % 2 == 0 ? candlePink : candleBlue)
        )
        // The flame: a squashed blob that breathes on web's 0.9s cycle, offset
        // per candle so the three are never in step.
        let phase = (elapsed / 0.9 + Double(i) * 0.17).truncatingRemainder(dividingBy: 1)
        let flameH = 18 * (1 + 0.12 * CGFloat(sin(phase * 2 * .pi)))
        let rect = CGRect(x: x + candleW / 2 - 6, y: candleBase - candleH - flameH, width: 12, height: flameH)
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: [flameCore, flameEdge]),
                center: CGPoint(x: rect.midX, y: rect.midY),
                startRadius: 0,
                endRadius: max(rect.width, rect.height) / 2
            )
        )
    }
}

// ---------------------------------------------------------------------------
// Confetti
// ---------------------------------------------------------------------------

/**
 Web's `CONFETTI_COLORS`, copied rather than mapped onto the chart palette.

 These are not design tokens — no CSS variable backs any of them, and the
 generated `chartColors` is the earthy INSIGHT_PALETTE, which would make the one
 celebratory moment in the app read like a bar chart.
 */
private let confettiColors: [Color] = [
    Color(.sRGB, red: 0.910, green: 0.639, blue: 0.239, opacity: 1),
    Color(.sRGB, red: 0.612, green: 0.682, blue: 0.557, opacity: 1),
    Color(.sRGB, red: 0.788, green: 0.541, blue: 0.447, opacity: 1),
    Color(.sRGB, red: 0.427, green: 0.353, blue: 0.812, opacity: 1),
    Color(.sRGB, red: 0.824, green: 0.227, blue: 0.369, opacity: 1),
    Color(.sRGB, red: 0.247, green: 0.478, blue: 0.416, opacity: 1),
    Color(.sRGB, red: 0.941, green: 0.769, blue: 0.098, opacity: 1),
]

private let confettiLife: TimeInterval = 7

/**
 One particle, in web's units: velocities are per FRAME at 60fps, which is what
 web's per-frame integration means, and the draw below converts elapsed seconds
 into frames rather than re-deriving the physics.
 */
private struct Confetto {
    let offsetX: CGFloat
    let offsetY: CGFloat
    let vx: CGFloat
    let vy: CGFloat
    let rotation: Double
    let spin: Double
    let size: CGFloat
    let color: Color
    let square: Bool
    let birth: TimeInterval
}

/// Web's two bursts: 170 particles at 520ms, another 110 at 950ms.
///
/// Seeded (mulberry32, the same generator the golden-vector exporter uses for
/// its own determinism) rather than `Double.random`, so the burst is identical
/// on every run and a screenshot diff of this screen means something.
private func buildConfetti() -> [Confetto] {
    var state: UInt32 = 0x9E37_79B9
    func next() -> Double {
        state = state &+ 0x6D2B_79F5
        var z = state
        z = (z ^ (z >> 15)) &* (z | 1)
        z ^= z &+ ((z ^ (z >> 7)) &* (z | 61))
        return Double((z ^ (z >> 14)) % 1_000_000) / 1_000_000
    }
    func burst(_ count: Int, _ birth: TimeInterval) -> [Confetto] {
        (0..<count).map { _ in
            let angle = next() * 2 * .pi
            let speed = 2 + next() * 9
            return Confetto(
                offsetX: CGFloat((next() - 0.5) * 60),
                offsetY: CGFloat((next() - 0.5) * 40),
                vx: CGFloat(cos(angle) * speed),
                vy: CGFloat(sin(angle) * speed - 4),
                rotation: next() * 180,
                spin: (next() - 0.5) * 17,
                size: CGFloat(5 + next() * 7),
                color: confettiColors[Int(next() * Double(confettiColors.count)) % confettiColors.count],
                square: next() < 0.5,
                birth: birth
            )
        }
    }
    return burst(170, 0.52) + burst(110, 0.95)
}

private func drawConfetti(context: GraphicsContext, size: CGSize, particles: [Confetto], elapsed: TimeInterval) {
    guard elapsed < confettiLife else { return }
    let alpha = max(0, 1 - elapsed / confettiLife)
    let centerX = size.width / 2
    let centerY = size.height / 2

    for p in particles {
        let age = elapsed - p.birth
        if age < 0 { continue }
        // Frames, at web's 60fps integration step.
        let t = CGFloat(age * 60)
        // x = x0 + vx*t, y = y0 + vy*t + 0.06*t^2 — the closed form of web's
        // `p.vy += 0.12` per frame. Its 0.99 horizontal drag is dropped: over
        // seven seconds it moves a particle a few points, and a closed form
        // keeps this identical to Android frame-for-frame.
        let x = centerX + p.offsetX + p.vx * t
        let y = centerY + p.offsetY + p.vy * t + 0.06 * t * t
        if y > size.height + 40 { continue }

        var layer = context
        layer.translateBy(x: x, y: y)
        layer.rotate(by: .degrees(p.rotation + p.spin * Double(t)))
        let shading = GraphicsContext.Shading.color(p.color.opacity(alpha))
        if p.square {
            layer.fill(Path(CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)), with: shading)
        } else {
            layer.fill(Path(ellipseIn: CGRect(x: -p.size / 2, y: -p.size / 2, width: p.size, height: p.size)), with: shading)
        }
    }
}
