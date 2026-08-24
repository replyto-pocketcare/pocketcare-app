import SwiftUI

/**
 The persistent sidebar shown at `SanvyaWindowClass.expanded`.

 A port of web's `.side-nav` (`globals.css:633-683`), which appears at the same
 moment the floating bottom bar disappears. Both cannot be on screen at once —
 two primary navigations is one too many, and web is emphatic about it.

 It renders the **same** `navGroups` the More sheet renders, plus Home and
 Notifications above them, because at this size the More sheet is unreachable
 and anything exclusive to it would be lost.

 The bottom bar's four customizable slots have no meaning here: every
 destination is already one tap away. `NavPrefs` is left untouched and unread,
 so narrowing the window restores the bar exactly as the user arranged it.
 */
struct SideNav: View {
    let currentTab: NavTab
    let unreadCount: Int
    let isGuest: Bool
    let guestDaysLeft: Int?
    let appVersion: String
    let onSelect: (NavTab) -> Void
    let onFeedback: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SanvyaMetrics.Expanded.sidebarGap) {
            SanvyaH2(S.Translation.appName)
                .padding(.horizontal, 8)
                .padding(.bottom, SanvyaMetrics.Expanded.brandPaddingBottom)

            searchRow

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    SideNavItem(
                        glyph: SanvyaIcons.spaceDashboard,
                        label: S.Translation.navHome,
                        isActive: currentTab == .dashboard,
                        action: { onSelect(.dashboard) }
                    )
                    SideNavItem(
                        glyph: SanvyaIcons.notifications,
                        label: S.Translation.navNotifications,
                        isActive: currentTab == .notifications,
                        badge: unreadCount,
                        action: { onSelect(.notifications) }
                    )

                    ForEach(navGroups) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            if !group.title.isEmpty {
                                // Not `SanvyaEyebrow`: that is 11/600 at 0.09
                                // tracking, and the sidebar's own title is
                                // 10.5/600 at 0.07. Close enough to look like a
                                // mistake, different enough to be one.
                                Text(group.title.uppercased())
                                    .sanvyaStyle(SanvyaType.sideNavTitle)
                                    .foregroundStyle(Color.text2)
                                    .opacity(0.65)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 2)
                            }
                            ForEach(group.items) { entry in
                                SideNavItem(
                                    glyph: entry.glyph,
                                    label: entry.label(),
                                    isActive: currentTab == entry.tab,
                                    action: { onSelect(entry.tab) }
                                )
                            }
                        }
                        .padding(.top, 12)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            foot
        }
        .frame(width: SanvyaMetrics.Expanded.sidebarWidth)
        .frame(maxHeight: .infinity)
        .padding(.top, SanvyaMetrics.Expanded.sidebarPaddingTop)
        .padding(.horizontal, SanvyaMetrics.Expanded.sidebarPaddingH)
        .padding(.bottom, SanvyaMetrics.Expanded.sidebarPaddingBottom)
        .background(Color.sidebar)
        // Leading corners only, so it sits flush inside the window frame's own
        // radius rather than floating a rounded card against a corner.
        .clipShape(
            .rect(
                topLeadingRadius: SanvyaMetrics.Expanded.sidebarRadius,
                bottomLeadingRadius: SanvyaMetrics.Expanded.sidebarRadius,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .accessibilityLabel("Primary")
    }

    /**
     Search is a row, not a field.

     At this width the add affordance moves into the dashboard's own header, and
     search is the thing every screen reaches for — so it takes the primary
     slot. Tapping opens the real search screen; nothing is typed here.
     */
    private var searchRow: some View {
        Button { onSelect(.search) } label: {
            HStack(spacing: 9) {
                SanvyaIconView(
                    SanvyaIcons.search,
                    size: SanvyaMetrics.Expanded.searchIconSize,
                    tint: .text3
                )
                Text("Search anything…")
                    .sanvyaStyle(SanvyaType.sideNavSearch)
                    .foregroundStyle(Color.text3)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SanvyaMetrics.Expanded.searchPaddingH)
            .padding(.vertical, SanvyaMetrics.Expanded.searchPaddingV)
            .background(Color.surface)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: SanvyaMetrics.Expanded.searchRadius,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: SanvyaMetrics.Expanded.searchRadius,
                    style: .continuous
                )
                .strokeBorder(Color.border, lineWidth: 1)
            )
        }
        .buttonStyle(SanvyaPressStyle())
        .padding(.bottom, SanvyaMetrics.Expanded.searchMarginBottom)
    }

    private var foot: some View {
        VStack(alignment: .leading, spacing: 2) {
            Rectangle()
                .fill(Color.border)
                .frame(height: 1)
                .padding(.bottom, SanvyaMetrics.Expanded.footPaddingTop)

            if isGuest {
                Button { onSelect(.settings) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(guestDaysLeft.map { "Guest · \($0)d left" } ?? S.Settings.guestBold)
                            .sanvyaStyle(SanvyaType.sideNavGuest)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.text)
                        Text(S.Onboarding.createAccount)
                            .sanvyaStyle(SanvyaType.sideNavGuest)
                            .foregroundStyle(Color.accent)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentGhost)
                    .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.row, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: SanvyaRadius.row, style: .continuous)
                            .strokeBorder(Color.accentSoft, lineWidth: 1)
                    )
                }
                .buttonStyle(SanvyaPressStyle())
                .padding(.bottom, 4)
            }

            SideNavItem(
                glyph: SanvyaIcons.chatBubble,
                label: "Feedback",
                isActive: false,
                action: onFeedback
            )

            // Web's footer also offers "Install app". Deliberately not ported:
            // it is a PWA affordance, and this app is already installed.

            Text("Sanvya v\(appVersion)")
                .sanvyaStyle(SanvyaType.sideNavVersion)
                .foregroundStyle(Color.text2)
                .opacity(0.7)
                .padding(.horizontal, 10)
                .padding(.top, 6)
        }
        .padding(.top, SanvyaMetrics.Expanded.footPaddingTop)
    }
}

/**
 One sidebar row.

 The active row gets a colour, a heavier weight **and** a left rail marker. The
 rail is not decoration: it is the cue that reads as "you are here" from the
 corner of the eye, without having to parse a colour difference.
 */
private struct SideNavItem: View {
    let glyph: String
    let label: String
    let isActive: Bool
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SanvyaMetrics.Expanded.itemGap) {
                SanvyaIconView(
                    glyph,
                    size: SanvyaMetrics.Expanded.itemIconSize,
                    tint: isActive ? .accent : .text
                )
                // Two whole styles rather than a weight override: the active
                // row is 650 and the resting one 500, and neither has a SwiftUI
                // `Font.Weight` constant. Inter is bundled as a VARIABLE font
                // precisely so these resolve on the `wght` axis instead of
                // rounding to semibold/medium.
                Text(label)
                    .sanvyaStyle(isActive ? SanvyaType.sideNavItemActive : SanvyaType.sideNavItem)
                    .foregroundStyle(isActive ? Color.accent : Color.text)
                Spacer(minLength: 0)
                if badge > 0 {
                    Text(badge > 9 ? "9+" : "\(badge)")
                        .sanvyaStyle(SanvyaType.sideNavBadge)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(
                            minWidth: SanvyaMetrics.Expanded.badgeMinWidth,
                            minHeight: SanvyaMetrics.Expanded.badgeHeight
                        )
                        .background(Color.negative)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, SanvyaMetrics.Expanded.itemPaddingH)
            .padding(.vertical, SanvyaMetrics.Expanded.itemPaddingV)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? Color.accentGhost : Color.clear)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: SanvyaMetrics.Expanded.itemRadius,
                    style: .continuous
                )
            )
            .overlay(alignment: .leading) {
                if isActive {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.accent)
                        .frame(
                            width: SanvyaMetrics.Expanded.railWidth,
                            height: SanvyaMetrics.Expanded.railHeight
                        )
                        .offset(x: -SanvyaMetrics.Expanded.railOffset)
                }
            }
        }
        .buttonStyle(SanvyaPressStyle())
    }
}
