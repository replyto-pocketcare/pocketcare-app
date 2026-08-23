import SwiftUI

/**
 The shape every top-level screen shares.

 Web gives each page a heading and its primary action on one row, then the
 content below — and, crucially, **no title bar**. There is no `UINavigationBar`
 anywhere in web's phone layout: the util row is the top of the page, and the
 heading is page content.

 Native screens were each wrapping themselves in a `NavigationView` with a
 `navigationTitle`, which put a system chrome bar above the shell's own. This is
 the replacement, so the fix is one component rather than fourteen improvisations.

 ```swift
 SanvyaPage("Budgets") {
     SanvyaButton { showNew = true } label: { Text("+ New budget") }
 } content: {
     …
 }
 ```
 */
struct SanvyaPage<Action: View, Content: View>: View {
    private let title: String
    private let action: () -> Action
    private let content: () -> Content

    init(
        _ title: String,
        @ViewBuilder action: @escaping () -> Action,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.action = action
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SanvyaMetrics.PageHeader.sectionGap) {
            HStack(alignment: .center, spacing: SanvyaMetrics.PageHeader.headerGap) {
                // `compact: true` is web's own choice, not a native concession:
                // globals.css drops h1 to 22px below 860px, and that is the size
                // a phone actually renders.
                SanvyaH1(title, compact: true)
                Spacer(minLength: 0)
                action()
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SanvyaPage where Action == EmptyView {
    /// A page whose heading has no action beside it.
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title, action: { EmptyView() }, content: content)
    }
}
