import SwiftUI

/**
 `.btn` wrapped around a `ShareLink`.

 A share control cannot be a `SanvyaButton`: `SanvyaButton` owns a `Button`, and
 the whole point of `ShareLink` is that the system — not the app — owns the
 presentation, the iPad popover anchor and the accessibility affordance. The
 alternative is `UIActivityViewController` presented onto
 `connectedScenes.first`, which is what Settings' diagnostics share does and
 which picks the wrong scene on iPad the moment there are two.

 So the CHROME is repeated here rather than the control being forced. That is a
 knowing duplicate of `SanvyaButton`'s body, and the real fix is to lift those
 six modifiers into a shared `ViewModifier` that both wear — a change to
 `Components/SanvyaControls.swift`, which is not this change's to make.
 */
struct SanvyaShareLink: View {
    let label: String
    let item: String

    var body: some View {
        ShareLink(item: item) {
            HStack(spacing: 8) {
                Text(label)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 40)
            .sanvyaStyle(SanvyaType.button)
            .foregroundStyle(Color.white)
            .background(Color.accent)
            .clipShape(Capsule())
        }
        .buttonStyle(SanvyaPressStyle())
    }
}
