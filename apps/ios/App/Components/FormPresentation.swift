import SwiftUI

/// How a create/edit form is presented, by window width.
///
/// **One rule, decided 2026-08-24** (screen-specs/app-shell.md §8a):
///
/// | Window | Surface |
/// |---|---|
/// | < 600pt (Compact) | full page — `.fullScreenCover` |
/// | >= 600pt (Medium and up) | a dialog — `.sheet`, which at that width *is* a dialog |
///
/// > *"On mobile a new page for entering the details is easier for users rather
/// > than to scroll inside a dialog. But for larger screens we have the dialog
/// > or a side panel for input."* — Akhilesh
///
/// **Why not `.sheet` everywhere.** On an iPhone a sheet is a card with rounded
/// corners and a strip of the page still visible behind it. It reads as an
/// overlay to scroll inside — exactly what the rule is against. Every
/// create/edit form on iOS was a `.sheet` before this.
///
/// **What `.fullScreenCover` costs.** Swipe-to-dismiss. Cancel becomes the only
/// way out. Accepted deliberately: an explicit exit from a form holding unsaved
/// input is not a loss.
///
/// The flip is at **Medium**, not Expanded, so a portrait tablet gets dialogs
/// even though it still shows the bottom bar. The reason for a full page is a
/// *narrow* screen, and 600pt is not narrow. That is a different threshold from
/// the sidebar's 840pt on purpose — they answer different questions.
///
/// **This is for forms only.** A confirmation ("mark these 3 EMIs paid?") is not
/// a form and keeps its own presentation: it has nothing to scroll and nothing
/// to lose on dismissal.
extension View {
    /// Adaptive presentation for a create/edit form driven by a `Bool`.
    func sanvyaFormPresentation<FormContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> FormContent
    ) -> some View {
        modifier(FormPresentationModifier(isPresented: isPresented, formContent: content))
    }

    /// Adaptive presentation for a create/edit form driven by an optional item.
    func sanvyaFormPresentation<Item: Identifiable, FormContent: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> FormContent
    ) -> some View {
        modifier(FormItemPresentationModifier(item: item, formContent: content))
    }
}

private struct FormPresentationModifier<FormContent: View>: ViewModifier {
    @Environment(\.sanvyaWindowClass) private var windowClass
    let isPresented: Binding<Bool>
    let formContent: () -> FormContent

    func body(content: Content) -> some View {
        // Both modifiers are always attached, gated on a binding that is only
        // ever true for one of them. Swapping which modifier exists based on
        // width would change the view's identity mid-flight — a rotation with a
        // form open would tear it down and lose whatever had been typed.
        content
            .fullScreenCover(isPresented: gate(.compact)) { formContent() }
            .sheet(isPresented: gate(.dialog)) { formContent() }
    }

    private func gate(_ wanted: FormSurface) -> Binding<Bool> {
        Binding(
            get: { isPresented.wrappedValue && FormSurface.of(windowClass) == wanted },
            set: { if !$0 { isPresented.wrappedValue = false } }
        )
    }
}

private struct FormItemPresentationModifier<Item: Identifiable, FormContent: View>: ViewModifier {
    @Environment(\.sanvyaWindowClass) private var windowClass
    let item: Binding<Item?>
    let formContent: (Item) -> FormContent

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: gate(.compact)) { formContent($0) }
            .sheet(item: gate(.dialog)) { formContent($0) }
    }

    private func gate(_ wanted: FormSurface) -> Binding<Item?> {
        Binding(
            get: { FormSurface.of(windowClass) == wanted ? item.wrappedValue : nil },
            set: { if $0 == nil { item.wrappedValue = nil } }
        )
    }
}

private enum FormSurface {
    case compact
    case dialog

    static func of(_ windowClass: SanvyaWindowClass) -> FormSurface {
        windowClass == .compact ? .compact : .dialog
    }
}
