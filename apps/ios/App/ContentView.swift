import SwiftUI
import Domain

// Proves App -> Domain wires up, same spirit as the old RN scaffold's
// canary screen. Real screens start at Phase 3 (plan §7) once Phase 0/1
// land.
struct ContentView: View {
    var body: some View {
        Text(DomainSkeleton.ready ? "PocketCare — iOS skeleton (P0.3)" : "domain not wired")
            .padding()
    }
}

#Preview {
    ContentView()
}
