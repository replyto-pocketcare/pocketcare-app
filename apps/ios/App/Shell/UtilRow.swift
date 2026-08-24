import SwiftUI

/**
 The in-flow utility row: one Back affordance on the left, the notification bell
 on the right.

 **A screen gets at most one back affordance, and this is it.** Web deleted
 every page-local "back to X" link to guarantee that, so no screen may add a
 navigation-bar back button on top of this row.

 In normal layout flow rather than floating, which is deliberate: the previous
 design used a fixed-position bell and it collided with pages that had their own
 header controls.
 */
struct UtilRow: View {
    let showBack: Bool
    let unreadCount: Int
    let onBack: () -> Void
    let onNotifications: () -> Void

    var body: some View {
        HStack {
            if showBack {
                BackButton(action: onBack)
            } else {
                Spacer().frame(width: 0)
            }
            Spacer()
            NotifBell(unreadCount: unreadCount, action: onNotifications)
        }
        .frame(minHeight: SanvyaMetrics.UtilRow.minHeight)
        .padding(.bottom, SanvyaMetrics.UtilRow.marginBottom)
    }
}

private struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SanvyaMetrics.UtilRow.backGap) {
                SanvyaIconView(SanvyaIcons.arrowBack, size: 18, tint: .text)
                Text(S.Translation.commonBack)
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.text)
            }
            .padding(.leading, SanvyaMetrics.UtilRow.backPaddingStart)
            .padding(.trailing, SanvyaMetrics.UtilRow.backPaddingEnd)
            .frame(height: SanvyaMetrics.UtilRow.buttonSize)
            .background(Color.surface)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.border, lineWidth: 1))
        }
        .buttonStyle(SanvyaPressStyle())
        .accessibilityLabel(S.Translation.commonBack)
    }
}

/// The bell, with its unread badge capped at "9+" exactly as web caps it.
struct NotifBell: View {
    let unreadCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                SanvyaIconView(SanvyaIcons.notifications, size: 19, tint: .text)
                    .frame(width: SanvyaMetrics.UtilRow.buttonSize,
                           height: SanvyaMetrics.UtilRow.buttonSize)
                    .background(Color.surface)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.border, lineWidth: 1))

                if unreadCount > 0 {
                    Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                        .sanvyaStyle(SanvyaType.navLabel)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(Color.negative)
                        .clipShape(Capsule())
                        .offset(x: -3, y: 3)
                }
            }
        }
        .buttonStyle(SanvyaPressStyle())
        .accessibilityLabel(unreadCount > 0
            ? "\(S.Translation.navNotifications) (\(unreadCount))"
            : S.Translation.navNotifications)
    }
}
