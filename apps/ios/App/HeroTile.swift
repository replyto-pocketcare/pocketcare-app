import SwiftUI

/**
 The "showpiece" tiles — light content on an earthy gradient.

 Web gives four tiles this treatment (Budgets, Goals, Subscriptions, Cashflow)
 and only those four. Ported with the same gradients, because the colour is what
 distinguishes one from another at a glance on a busy dashboard; a single
 accent-coloured card for all four would lose that.

 The gradients are hardcoded here, matching web, and NOT generated. They are
 four two-stop CSS gradients in one file with no other consumer — the kind of
 value the catalogue exists to hold only once there is a second reader. If a
 fifth hero tile ever appears, that is the moment to move them.

 Mirrors `apps/android/.../ui/dashboard/HeroTile.kt`.
 */
enum HeroTint {
    case cashflow, budgets, goals, subs

    /// `linear-gradient(150deg, start, end)`
    var colors: [Color] {
        switch self {
        case .cashflow: return [Color(hex: "#b06a4f")!, Color(hex: "#8f533c")!]
        case .budgets: return [Color(hex: "#c08a3e")!, Color(hex: "#a8503a")!]
        case .goals: return [Color(hex: "#2f6f6a")!, Color(hex: "#3e4a38")!]
        case .subs: return [Color(hex: "#7a4a6b")!, Color(hex: "#4f3a54")!]
        }
    }
}

/// `#f6f0e7`, and web's `HERO_MUTED` at 0.82.
let heroInk = Color(hex: "#f6f0e7")!
let heroInkMuted = Color(hex: "#f6f0e7")!.opacity(0.82)

struct HeroTile<Trailing: View, Content: View>: View {
    let title: String
    let tint: HeroTint
    let onOpen: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Text(title.uppercased())
                    .sanvyaStyle(SanvyaType.eyebrow)
                    .foregroundStyle(heroInk.opacity(0.72))
                Spacer(minLength: 0)
                trailing()
            }
            content()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            // 150deg in CSS runs top-left-ish to bottom-right-ish.
            LinearGradient(colors: tint.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture { onOpen?() }
    }
}

extension HeroTile where Trailing == EmptyView {
    init(
        title: String,
        tint: HeroTint,
        onOpen: (() -> Void)?,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(title: title, tint: tint, onOpen: onOpen, trailing: { EmptyView() }, content: content)
    }
}

/**
 Web's `LightBar` — a progress track on a hero tile.

 Its track is white at 18% rather than a design token: the tile behind it is a
 gradient, so a surface-coloured track would be invisible on one end of it and
 wrong on the other.
 */
struct LightBar: View {
    let pct: Double
    var color: Color = heroInk

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * min(max(pct, 0), 100) / 100)
            }
        }
        .frame(height: 8)
    }
}
