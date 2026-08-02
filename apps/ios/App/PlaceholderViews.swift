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
