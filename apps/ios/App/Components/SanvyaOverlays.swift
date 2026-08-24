import SwiftUI

/**
 The design system's dialog: a `.card` floating on a 45%-opacity scrim, 440pt
 wide at most, 24pt padding, entering with a spring from 0.94 scale.

 Presented as a `.fullScreenCover` with a clear background rather than
 `.sheet`: a sheet is a different presentation entirely — it slides from the
 bottom, keeps a card-stack appearance and cannot be centred — whereas web's
 Modal is a centred dialog over a dimmed page. VoiceOver focus containment
 comes from the cover being its own presentation, which is the behaviour web
 has to hand-roll as a JS focus trap.
 */
public struct SanvyaModalModifier<Panel: View>: ViewModifier {
    @Binding var isPresented: Bool
    let label: String?
    let dismissOnScrimTap: Bool
    let panel: () -> Panel

    public func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented) {
            SanvyaModalContainer(
                isPresented: $isPresented,
                label: label,
                dismissOnScrimTap: dismissOnScrimTap,
                panel: panel
            )
            .presentationBackground(.clear)
        }
    }
}

private struct SanvyaModalContainer<Panel: View>: View {
    @Binding var isPresented: Bool
    let label: String?
    let dismissOnScrimTap: Bool
    let panel: () -> Panel

    @State private var shown = false

    var body: some View {
        ZStack {
            // rgba(43,39,35,0.45) — the ink colour at 45%, not plain black.
            Color(.sRGB, red: 0.1686, green: 0.1529, blue: 0.1373, opacity: 0.45)
                .ignoresSafeArea()
                .onTapGesture { if dismissOnScrimTap { close() } }
                .accessibilityHidden(true)

            ScrollView {
                // minHeight + centring keeps the card centred when it fits and
                // fully reachable (scrolled from the top) when it is taller
                // than the screen — the same trick web's Modal uses.
                SanvyaCard(padding: 24) { panel() }
                    .frame(maxWidth: 440)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scaleEffect(shown ? 1 : 0.94)
            .opacity(shown ? 1 : 0)
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: shown)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label ?? "Dialog")
        .onAppear { shown = true }
    }

    private func close() {
        shown = false
        isPresented = false
    }
}

public extension View {
    /// Presents `panel` as the design system's centred dialog.
    func sanvyaModal<Panel: View>(
        isPresented: Binding<Bool>,
        label: String? = nil,
        dismissOnScrimTap: Bool = true,
        @ViewBuilder panel: @escaping () -> Panel
    ) -> some View {
        modifier(SanvyaModalModifier(
            isPresented: isPresented,
            label: label,
            dismissOnScrimTap: dismissOnScrimTap,
            panel: panel
        ))
    }

    /// Blocking, non-dismissable loader for an in-flight destructive write —
    /// web renders `GlobalLoader` over the page for the same purpose.
    func sanvyaBlockingLoader(isPresented: Binding<Bool>, label: String? = nil) -> some View {
        fullScreenCover(isPresented: isPresented) {
            ZStack {
                Color(.sRGB, red: 0.1686, green: 0.1529, blue: 0.1373, opacity: 0.45)
                    .ignoresSafeArea()
                SanvyaLoading(label: label)
            }
            .presentationBackground(.clear)
            .interactiveDismissDisabled(true)
        }
    }
}
