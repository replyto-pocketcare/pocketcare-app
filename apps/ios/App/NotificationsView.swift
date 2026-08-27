import SwiftUI
import Data
import Domain

/// The notification inbox — ported from apps/web/app/notifications/page.tsx.
///
/// The repository and the bell badge already existed on both platforms; this is
/// the screen the badge was pointing at, which was a placeholder.
///
/// The row's deep link is web's `n.href` — a web path like `/budgets` — handed
/// to `onOpenHref`, which resolves it through Domain's `parseAppLink`. A row
/// whose href resolves to nothing is still tappable and still marks itself read;
/// it simply does not move, which is what a dead link on web does too.
struct NotificationsView: View {
    @State private var viewModel = NotificationsViewModel()
    var onOpenSettings: (() -> Void)?
    var onOpenHref: ((String) -> Void)?

    var body: some View {
        ScrollView {
            SanvyaPage(S.Notifications.title) {
                if viewModel.unread > 0 || onOpenSettings != nil {
                    HStack(spacing: 8) {
                        if viewModel.unread > 0 {
                            SanvyaChip(S.Notifications.markAllRead, isActive: false) {
                                viewModel.markAllRead()
                            }
                        }
                        if let onOpenSettings {
                            SanvyaChip(S.Notifications.settings, isActive: false, action: onOpenSettings)
                        }
                        Spacer(minLength: 0)
                    }
                }

                if viewModel.items.isEmpty {
                    empty
                } else {
                    SanvyaCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                                if index > 0 {
                                    Rectangle()
                                        .fill(Color.border)
                                        .frame(height: 1)
                                }
                                row(item)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color.bg.ignoresSafeArea())
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.cancel() }
    }

    private var empty: some View {
        SanvyaCard(padding: 40) {
            VStack(spacing: 8) {
                SanvyaIconView(SanvyaIcons.notifications, size: 30, tint: Color.text3)
                Text(S.Notifications.emptyTitle)
                    .sanvyaStyle(SanvyaType.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.text)
                Text(S.Notifications.emptyBody)
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.text2)
                    .multilineTextAlignment(.center)
                if let onOpenSettings {
                    SanvyaButton(ghost: true, action: onOpenSettings) {
                        Text(S.Notifications.enableCta)
                    }
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func row(_ item: NotificationRow) -> some View {
        let isRead = item.readAt != nil
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(isRead ? Color.borderStrong : severityColor(item.severity))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .sanvyaStyle(SanvyaType.statLabel)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.text)
                    .lineLimit(1)
                if let body = item.body, !body.isEmpty {
                    Text(body)
                        .sanvyaStyle(SanvyaType.statLabel)
                        .foregroundStyle(Color.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(ageLabel(item.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if !isRead { viewModel.markRead(item.id) }
                if let href = item.href, !href.isEmpty { onOpenHref?(href) }
            }
            Button { viewModel.dismiss(item.id) } label: {
                Text(verbatim: "×")
                    .sanvyaStyle(SanvyaType.body)
                    .foregroundStyle(Color.text2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(S.Notifications.dismiss)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // An unread row is tinted, which is the only thing distinguishing it
        // besides the dot. Web does the same with `--accent-ghost`.
        .background(isRead ? Color.clear : Color.accentGhost)
    }

    /// Web's `SEV_COLOR` map, with its own fallback to accent for a severity
    /// nobody has defined a colour for.
    private func severityColor(_ severity: String?) -> Color {
        switch severity {
        case "warn": Color.warning
        case "urgent": Color.negative
        default: Color.accent
        }
    }

    /// Domain returns the shape; the words and the date format are the view's,
    /// because both are locale-dependent and web's version hardcodes English.
    private func ageLabel(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "" }
        switch timeAgo(iso, now: nowIso()) {
        case .justNow: return S.Notifications.justNow
        case .minutes(let n): return S.Notifications.minutesAgo(count: String(n))
        case .hours(let n): return S.Notifications.hoursAgo(count: String(n))
        case .days(let n): return S.Notifications.daysAgo(count: String(n))
        case .on(let value): return isoLabel(value, "d MMM y")
        }
    }
}
