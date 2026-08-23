import SwiftUI

/// One nav group in the More sheet, matching web's `NAV_GROUPS`.
private struct NavGroup: Identifiable {
    let id = UUID()
    let title: String
    let items: [NavEntry]
}

private struct NavEntry: Identifiable {
    let id = UUID()
    let tab: NavTab
    let label: String
    let glyph: String
}

/**
 Web's `NAV_GROUPS`, verbatim.

 The Money group has one "Shared & owed" entry, not two: `/groups` now redirects
 to `/friends`, because Groups and Splits were one screen's worth of information
 split across two.
 */
private let navGroups: [NavGroup] = [
    NavGroup(title: "Money", items: [
        NavEntry(tab: .accounts, label: "Accounts", glyph: SanvyaIcons.accountBalance),
        NavEntry(tab: .transactions, label: "Transactions", glyph: SanvyaIcons.swapHoriz),
        NavEntry(tab: .cards, label: "Cards", glyph: SanvyaIcons.creditCard),
        NavEntry(tab: .splits, label: "Shared & owed", glyph: SanvyaIcons.groups),
        NavEntry(tab: .search, label: "Search", glyph: SanvyaIcons.search),
    ]),
    NavGroup(title: "Planning", items: [
        NavEntry(tab: .budgets, label: "Budgets", glyph: SanvyaIcons.donutSmall),
        NavEntry(tab: .goals, label: "Goals", glyph: SanvyaIcons.flag),
        NavEntry(tab: .recurring, label: "Recurring", glyph: SanvyaIcons.autorenew),
        NavEntry(tab: .loans, label: "Loans", glyph: SanvyaIcons.requestQuote),
    ]),
    NavGroup(title: "Growth", items: [
        NavEntry(tab: .investments, label: "Investments", glyph: SanvyaIcons.trendingUp),
        NavEntry(tab: .reflect, label: "Reflect", glyph: SanvyaIcons.volunteerActivism),
        NavEntry(tab: .insights, label: "Insights", glyph: SanvyaIcons.insights),
        NavEntry(tab: .statements, label: "Statements", glyph: SanvyaIcons.description),
    ]),
    NavGroup(title: "", items: [
        NavEntry(tab: .assistant, label: "Ask Sanvya", glyph: SanvyaIcons.autoAwesome),
        NavEntry(tab: .settings, label: "Settings", glyph: SanvyaIcons.settings),
        NavEntry(tab: .help, label: "Help & FAQ", glyph: SanvyaIcons.help),
    ]),
]

/**
 Every destination that is not in the bottom bar.

 Web's footer also offers "Install app"; that is a PWA affordance and is
 deliberately not ported — this app is already installed.
 */
struct MoreSheet: View {
    let currentTab: NavTab
    let unreadCount: Int
    let isGuest: Bool
    let guestDaysLeft: Int?
    let appVersion: String
    let onSelect: (NavTab) -> Void
    let onCustomize: () -> Void
    let onFeedback: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SanvyaH2("Sanvya")
                Spacer()
                HStack(spacing: 8) {
                    RoundIconButton(glyph: SanvyaIcons.edit, label: "Customize bottom bar", action: onCustomize)
                    RoundIconButton(glyph: SanvyaIcons.close, label: "Close", action: onClose)
                }
            }
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    MoreNavItem(
                        glyph: SanvyaIcons.notifications,
                        label: "Notifications",
                        isActive: currentTab == .notifications,
                        badge: unreadCount,
                        action: { onSelect(.notifications) }
                    )
                    ForEach(navGroups) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            if !group.title.isEmpty {
                                SanvyaEyebrow(group.title)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 2)
                            }
                            ForEach(group.items) { entry in
                                MoreNavItem(
                                    glyph: entry.glyph,
                                    label: entry.label,
                                    isActive: currentTab == entry.tab,
                                    action: { onSelect(entry.tab) }
                                )
                            }
                        }
                        .padding(.top, 10)
                    }
                }
            }
            .frame(maxHeight: 360)

            VStack(alignment: .leading, spacing: 8) {
                if isGuest {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(guestDaysLeft.map { "Guest · \($0) days until data is deleted" } ?? "Guest")
                            .sanvyaStyle(SanvyaType.statLabel)
                            .foregroundStyle(Color.text)
                        Text("Create account →")
                            .sanvyaStyle(SanvyaType.statLabel)
                            .foregroundStyle(Color.accent)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentGhost)
                    .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.row, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: SanvyaRadius.row, style: .continuous)
                            .strokeBorder(Color.accentSoft, lineWidth: 1)
                    )
                }
                SanvyaButton(ghost: true, action: onFeedback) {
                    SanvyaIconView(SanvyaIcons.chatBubble, size: 16, tint: .text)
                    Text("Feedback")
                }
                .frame(maxWidth: .infinity)
                Text("Sanvya v\(appVersion)")
                    .sanvyaStyle(SanvyaType.navLabel)
                    .foregroundStyle(Color.text2)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 12)
        }
    }
}

private struct RoundIconButton: View {
    let glyph: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SanvyaIconView(glyph, size: 15, tint: .text)
                .frame(width: 34, height: 34)
                .background(Color.surface2)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.border, lineWidth: 1))
        }
        .buttonStyle(SanvyaPressStyle())
        .accessibilityLabel(label)
    }
}

private struct MoreNavItem: View {
    let glyph: String
    let label: String
    let isActive: Bool
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SanvyaIconView(glyph, size: 20, tint: isActive ? .accent : .text)
                Text(label)
                    .sanvyaStyle(SanvyaType.body)
                    .foregroundStyle(isActive ? Color.accent : Color.text)
                Spacer()
                if badge > 0 {
                    Text(badge > 9 ? "9+" : "\(badge)")
                        .sanvyaStyle(SanvyaType.navLabel)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Color.negative)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? Color.accentGhost : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.row, style: .continuous))
        }
        .buttonStyle(SanvyaPressStyle())
    }
}

/**
 Pick which four destinations sit in the bar.

 When four are chosen the rest go **disabled**, not silently evicting whoever
 was picked first — web ignores the extra tap rather than bumping someone — and
 Save stays disabled until exactly four are selected.
 */
struct BottomNavCustomizer: View {
    let current: [String]
    let onSave: ([String]) -> Void
    let onClose: () -> Void

    @State private var picked: [String]

    init(current: [String], onSave: @escaping ([String]) -> Void, onClose: @escaping () -> Void) {
        self.current = current
        self.onSave = onSave
        self.onClose = onClose
        _picked = State(initialValue: current)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SanvyaH2("Customize bottom bar")
                .padding(.bottom, 4)
            Text("Pick \(NavPrefs.slots) to keep one tap away. Home and More always stay put.")
                .sanvyaStyle(SanvyaType.statLabel)
                .foregroundStyle(Color.text2)
                .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(NavPrefs.catalog) { item in
                        row(for: item)
                    }
                }
            }
            .frame(maxHeight: 300)

            HStack(spacing: 8) {
                Spacer()
                SanvyaButton(ghost: true, action: onClose) { Text("Cancel") }
                SanvyaButton(action: { onSave(picked) }) { Text("Save") }
                    .disabled(picked.count != NavPrefs.slots)
            }
            .padding(.top, 16)
        }
    }

    @ViewBuilder
    private func row(for item: NavCatalogItem) -> some View {
        let isActive = picked.contains(item.id)
        let isDisabled = !isActive && picked.count >= NavPrefs.slots

        Button {
            picked = isActive ? picked.filter { $0 != item.id } : picked + [item.id]
        } label: {
            HStack(spacing: 10) {
                SanvyaIconView(item.glyph, size: 20, tint: isDisabled ? .text3 : .text)
                Text(item.label)
                    .sanvyaStyle(SanvyaType.body)
                    .foregroundStyle(isDisabled ? Color.text3 : Color.text)
                Spacer()
                ZStack {
                    Circle()
                        .fill(isActive ? Color.accent : Color.clear)
                        .overlay(
                            Circle().strokeBorder(
                                isActive ? Color.accent : Color.borderStrong,
                                lineWidth: 1.5
                            )
                        )
                    if isActive {
                        SanvyaIconView(SanvyaIcons.check, size: 13, tint: .white)
                    }
                }
                .frame(width: 20, height: 20)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? Color.accentGhost : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.row, style: .continuous))
            .opacity(isDisabled ? 0.55 : 1)
        }
        .buttonStyle(SanvyaPressStyle())
        .disabled(isDisabled)
    }
}
