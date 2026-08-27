import SwiftUI

/**
 One nav group, matching web's `NAV_GROUPS`.

 Not private: the More sheet and the expanded-layout sidebar render the **same**
 list. They have to. At `.expanded` the More sheet is unreachable, so anything
 that lived only there would simply vanish on an iPad.
 */
/// `Sendable` because `navGroups` is a global `let`, and Swift 6 requires a
/// global's type to be Sendable. That is only possible if the label closure is
/// `@Sendable` too — which it is: each one captures nothing and returns a
/// `String` from a static accessor.
struct NavGroup: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let items: [NavEntry]
}

struct NavEntry: Identifiable, Sendable {
    let id = UUID()
    let tab: NavTab
    /// Typed accessor, not a literal — see `NavCatalogItem.label`.
    let label: @Sendable () -> String
    let glyph: String
}

/**
 Web's `NAV_GROUPS`, verbatim.

 The Money group has one "Shared & owed" entry, not two: `/groups` now redirects
 to `/friends`, because Groups and Splits were one screen's worth of information
 split across two.
 */
let navGroups: [NavGroup] = [
    NavGroup(title: "Money", items: [
        NavEntry(tab: .accounts, label: { S.Translation.navAccounts }, glyph: SanvyaIcons.accountBalance),
        NavEntry(tab: .transactions, label: { S.Translation.navTransactions }, glyph: SanvyaIcons.swapHoriz),
        NavEntry(tab: .cards, label: { S.Translation.navCards }, glyph: SanvyaIcons.creditCard),
        NavEntry(tab: .splits, label: { S.Translation.navFriends }, glyph: SanvyaIcons.groups),
        NavEntry(tab: .search, label: { S.Translation.navSearch }, glyph: SanvyaIcons.search),
    ]),
    NavGroup(title: "Planning", items: [
        NavEntry(tab: .budgets, label: { S.Translation.navBudgets }, glyph: SanvyaIcons.donutSmall),
        NavEntry(tab: .goals, label: { S.Translation.navGoals }, glyph: SanvyaIcons.flag),
        NavEntry(tab: .recurring, label: { S.Translation.navRecurring }, glyph: SanvyaIcons.autorenew),
        NavEntry(tab: .loans, label: { S.Translation.navLoans }, glyph: SanvyaIcons.requestQuote),
    ]),
    NavGroup(title: "Growth", items: [
        NavEntry(tab: .investments, label: { S.Translation.navInvestments }, glyph: SanvyaIcons.trendingUp),
        NavEntry(tab: .reflect, label: { S.Translation.navReflect }, glyph: SanvyaIcons.volunteerActivism),
        NavEntry(tab: .insights, label: { S.Translation.navInsights }, glyph: SanvyaIcons.insights),
        NavEntry(tab: .statements, label: { S.Translation.navStatements }, glyph: SanvyaIcons.description),
    ]),
    NavGroup(title: "", items: [
        NavEntry(tab: .assistant, label: { S.Translation.navAssistant }, glyph: SanvyaIcons.autoAwesome),
        NavEntry(tab: .settings, label: { S.Translation.navSettings }, glyph: SanvyaIcons.settings),
        NavEntry(tab: .help, label: { S.Translation.navHelp }, glyph: SanvyaIcons.help),
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
    /// Web's `<Link href="/login">` on the guest block. This block was not
    /// tappable at all, so the one affordance a guest has for keeping their
    /// data did nothing.
    let onSignIn: () -> Void
    let onCustomize: () -> Void
    let onFeedback: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SanvyaH2(S.Translation.appName)
                Spacer()
                HStack(spacing: 8) {
                    RoundIconButton(glyph: SanvyaIcons.edit, label: S.Translation.navCustomize, action: onCustomize)
                    RoundIconButton(glyph: SanvyaIcons.close, label: S.Translation.commonClose, action: onClose)
                }
            }
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    MoreNavItem(
                        glyph: SanvyaIcons.notifications,
                        label: S.Translation.navNotifications,
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
                                    label: entry.label(),
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
                    Button(action: onSignIn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(guestDaysLeft.map { "Guest · \($0) days until data is deleted" } ?? S.Settings.guestBold)
                                .sanvyaStyle(SanvyaType.statLabel)
                                .foregroundStyle(Color.text)
                            Text(S.Onboarding.createAccount)
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
                    .buttonStyle(SanvyaPressStyle())
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
            SanvyaH2(S.Translation.navCustomize)
                .padding(.bottom, 4)
            Text(S.Translation.navCustomizeHint(n: String(NavPrefs.slots)))
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
                SanvyaButton(ghost: true, action: onClose) { Text(S.Translation.commonCancel) }
                SanvyaButton(action: { onSave(picked) }) { Text(S.Translation.commonSave) }
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
                Text(item.label())
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
