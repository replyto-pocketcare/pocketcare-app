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

// Added 2026-08-05 alongside the drawer-parity fix: a real web route
// (apps/web/app/reflect/page.tsx) that this drawer was missing entirely, not
// just missing a built screen for -- see
// docs/mobile/screen-specs/navigation-drawer.md. Notifications joined it there
// and has since been built.
struct ReflectView: View {
    var body: some View { PlaceholderView(title: S.Translation.navReflect, ) }
}
