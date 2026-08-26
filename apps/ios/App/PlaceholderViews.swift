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

// Everything this file used to hold has been built. `PlaceholderView` itself
// stays: `AssistantView` is the one nav entry still unbuilt on both platforms,
// and a placeholder is what keeps its tap from being a crash.
