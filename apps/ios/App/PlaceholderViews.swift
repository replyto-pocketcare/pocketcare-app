import SwiftUI

struct PlaceholderView: View {
    let title: String

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
        }
    }
}

struct SearchView: View {
    var body: some View { PlaceholderView(title: S.Translation.navSearch, ) }
}

struct HelpView: View {
    var body: some View { PlaceholderView(title: S.Translation.navHelp, ) }
}

// Added 2026-08-05 alongside the drawer-parity fix: both are real web
// routes (apps/web/app/{reflect,notifications}/page.tsx) that this drawer
// was missing entirely, not just missing a built screen for -- see
// docs/mobile/screen-specs/navigation-drawer.md.
struct ReflectView: View {
    var body: some View { PlaceholderView(title: S.Translation.navReflect, ) }
}

struct NotificationsPlaceholderView: View {
    var body: some View { PlaceholderView(title: S.Translation.navNotifications, ) }
}
