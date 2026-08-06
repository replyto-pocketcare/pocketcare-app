import SwiftUI

struct PlaceholderView: View {
    let title: String
    @Binding var isDrawerOpen: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text(title)
                    .font(.title)
                    .fontWeight(.bold)
                Text("This feature is coming soon.")
                    .foregroundColor(.secondary)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation(.spring()) {
                            isDrawerOpen.toggle()
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .imageScale(.large)
                    }
                }
            }
        }
    }
}

struct SearchView: View {
    @Binding var isDrawerOpen: Bool
    var body: some View { PlaceholderView(title: "Search", isDrawerOpen: $isDrawerOpen) }
}

struct TemplatesView: View {
    @Binding var isDrawerOpen: Bool
    var body: some View { PlaceholderView(title: "Templates", isDrawerOpen: $isDrawerOpen) }
}

struct CashflowView: View {
    @Binding var isDrawerOpen: Bool
    var body: some View { PlaceholderView(title: "Planned Cashflow", isDrawerOpen: $isDrawerOpen) }
}

struct RecurringView: View {
    @Binding var isDrawerOpen: Bool
    var body: some View { PlaceholderView(title: "Recurring", isDrawerOpen: $isDrawerOpen) }
}

struct HelpView: View {
    @Binding var isDrawerOpen: Bool
    var body: some View { PlaceholderView(title: "Help & FAQ", isDrawerOpen: $isDrawerOpen) }
}

// Added 2026-08-05 alongside the drawer-parity fix: both are real web
// routes (apps/web/app/{reflect,notifications}/page.tsx) that this drawer
// was missing entirely, not just missing a built screen for -- see
// docs/mobile/screen-specs/navigation-drawer.md.
struct ReflectView: View {
    @Binding var isDrawerOpen: Bool
    var body: some View { PlaceholderView(title: "Reflect", isDrawerOpen: $isDrawerOpen) }
}

struct NotificationsPlaceholderView: View {
    @Binding var isDrawerOpen: Bool
    var body: some View { PlaceholderView(title: "Notifications", isDrawerOpen: $isDrawerOpen) }
}
