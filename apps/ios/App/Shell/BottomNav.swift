import SwiftUI

/**
 The floating bottom bar — web's only navigation on a phone.

 Seven slots, balanced three-and-three around a raised "+":
 `Home · slot · slot · + · slot · slot · More`.

 Hand-built rather than `TabView`, because `TabView` cannot produce either of
 the two things that define this design: a capsule floating inset from the
 screen edges, and a centre button that rises above its own container. It also
 fixes its item count and ordering, where four of these seven are chosen by the
 user at runtime.

 Every number is a generated token — see `docs/mobile/screen-specs/app-shell.md`
 for the mapping back to `globals.css`.
 */
struct BottomNav: View {
    @Environment(\.sanvyaWindowClass) private var windowClass
    let currentTab: NavTab
    let navIds: [String]
    let unreadCount: Int
    let addLabel: String
    let moreOpen: Bool
    let onSelect: (NavTab) -> Void
    let onAdd: () -> Void
    let onMore: () -> Void

    private var items: [NavCatalogItem] { NavPrefs.shared.items(for: navIds) }

    /// Web hides the labels below 640px, which is every iPhone. iPad and
    /// landscape-regular cross it, so this asks the size class rather than
    /// assuming.
    // One source of truth: the shell's window class, not a second size-class
    // check that could drift from it.
    private var compact: Bool { !windowClass.showsNavLabels }

    var body: some View {
        HStack(spacing: SanvyaMetrics.BottomNav.itemGap) {
            NavItem(
                glyph: SanvyaIcons.spaceDashboard,
                label: S.Translation.navHome,
                isActive: currentTab == .dashboard,
                compact: compact,
                action: { onSelect(.dashboard) }
            )

            ForEach(items.prefix(2)) { item in
                NavItem(
                    glyph: item.glyph,
                    label: item.label(),
                    isActive: currentTab == item.tab,
                    compact: compact,
                    action: { onSelect(item.tab) }
                )
            }

            AddButton(label: addLabel, compact: compact, action: onAdd)

            ForEach(items.dropFirst(2).prefix(2)) { item in
                NavItem(
                    glyph: item.glyph,
                    label: item.label(),
                    isActive: currentTab == item.tab,
                    compact: compact,
                    action: { onSelect(item.tab) }
                )
            }

            NavItem(
                glyph: SanvyaIcons.moreHoriz,
                label: S.Translation.navMore,
                isActive: moreOpen,
                compact: compact,
                badgeDot: unreadCount > 0,
                action: onMore
            )
        }
        .padding(.horizontal, SanvyaMetrics.BottomNav.paddingH)
        .padding(.vertical, SanvyaMetrics.BottomNav.paddingV)
        .background(Color.surface)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.border, lineWidth: 1))
        .sanvyaShadow(SanvyaShadows.shadowLg(dark: false))
        .frame(maxWidth: SanvyaMetrics.BottomNav.maxWidth)
    }
}

private struct NavItem: View {
    let glyph: String
    let label: String
    let isActive: Bool
    let compact: Bool
    var badgeDot: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 2) {
                    SanvyaIconView(glyph, size: 22, tint: isActive ? .accent : .text2)
                    if !compact {
                        Text(label)
                            .sanvyaStyle(SanvyaType.navLabel)
                            .foregroundStyle(isActive ? Color.accent : Color.text2)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: compact ? SanvyaMetrics.BottomNav.itemHeightCompact : SanvyaMetrics.BottomNav.itemHeight)
                .background(isActive ? Color.accentGhost : Color.clear)
                .clipShape(Capsule())

                if badgeDot {
                    Circle()
                        .fill(Color.negative)
                        .frame(width: 8, height: 8)
                        .offset(x: -6, y: 2)
                }
            }
        }
        .buttonStyle(SanvyaPressStyle())
        // One label for the whole item — the icon is decorative beside it.
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

/**
 The raised "+".

 The negative offset is web's `margin-top: -14px`: the button sits above the
 bar's own bounds, and the `--surface` ring is what reads as a cut-out in the
 bar behind it.
 */
private struct AddButton: View {
    let label: String
    let compact: Bool
    let action: () -> Void

    private var size: CGFloat {
        compact ? SanvyaMetrics.BottomNav.addSizeCompact : SanvyaMetrics.BottomNav.addSize
    }

    var body: some View {
        Button(action: action) {
            SanvyaIconView(SanvyaIcons.add, size: 24, tint: .white)
                .frame(width: size - SanvyaMetrics.BottomNav.addRingWidth * 2,
                       height: size - SanvyaMetrics.BottomNav.addRingWidth * 2)
                .background(Color.accent)
                .clipShape(Circle())
                .padding(SanvyaMetrics.BottomNav.addRingWidth)
                .background(Color.surface)
                .clipShape(Circle())
                .sanvyaShadow(SanvyaShadows.shadowAccent(dark: false))
        }
        .buttonStyle(SanvyaPressStyle())
        .padding(.horizontal, SanvyaMetrics.BottomNav.addSideMargin)
        .offset(y: -SanvyaMetrics.BottomNav.addOverhang)
        .accessibilityLabel(label)
    }
}
