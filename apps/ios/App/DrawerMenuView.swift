import SwiftUI

struct DrawerMenuView: View {
    @Binding var currentTab: NavTab
    @Binding var isDrawerOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("PocketCare")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .background(Color.accent)
            .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // Notifications renders above the titled groups, matching
                    // web's AppShell.tsx:303 (a standalone row before
                    // NAV_GROUPS, not inside one) and Android's separate
                    // notificationsDrawerItem. Added 2026-08-05 -- this drawer
                    // was missing it entirely until checked against the real
                    // web source.
                    DrawerItemRow(
                        item: NavItem(tab: .notifications, label: "Notifications", icon: "bell"),
                        isSelected: currentTab == .notifications
                    ) {
                        currentTab = .notifications
                        withAnimation(.spring()) {
                            isDrawerOpen = false
                        }
                    }
                    ForEach(navGroups) { group in
                        if !group.title.isEmpty {
                            Text(group.title.uppercased())
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(Color.text2)
                                .padding(.leading, 24)
                                .padding(.top, 16)
                        } else {
                            Spacer().frame(height: 8)
                        }

                        ForEach(group.items) { item in
                            DrawerItemRow(
                                item: item,
                                isSelected: currentTab == item.tab
                            ) {
                                currentTab = item.tab
                                withAnimation(.spring()) {
                                    isDrawerOpen = false
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bg)
        .edgesIgnoringSafeArea(.all)
    }
}

struct DrawerItemRow: View {
    let item: NavItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: item.icon)
                    .font(.title3)
                
                Text(item.label)
                    .font(.body)
                    .fontWeight(isSelected ? .bold : .regular)
                
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(isSelected ? Color.accent.opacity(0.15) : Color.clear)
            .foregroundColor(isSelected ? Color.accent : Color.text)
            .cornerRadius(12)
            .padding(.horizontal, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
