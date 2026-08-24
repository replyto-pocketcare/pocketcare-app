import SwiftUI

/**
 The design system's surfaces, drawn from generated tokens.

 These supersede `PocketComponents.swift` (`PocketCard`, `RowTile`,
 `PrimaryButton`, `FloatingInput`), which was hand-styled against eyeballed
 values. Screens move over as each is rebuilt against its spec; the old file
 stays until its last call site is gone, and nothing new should use it.
 */

/// `.card` — surface, hairline border, 24pt radius, the two-layer card shadow.
/// `action` makes it web's `a.card`, which takes the gentler 0.985 press.
public struct SanvyaCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let padding: CGFloat
    private let cornerRadius: CGFloat
    private let action: (() -> Void)?
    private let content: () -> Content

    public init(
        padding: CGFloat = 16,
        cornerRadius: CGFloat = SanvyaRadius.radiusLg,
        action: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.action = action
        self.content = content
    }

    public var body: some View {
        if let action {
            Button(action: action) { surface }
                .buttonStyle(SanvyaLiftPressStyle())
        } else {
            surface
        }
    }

    private var surface: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.border, lineWidth: 1)
            )
            .sanvyaShadow(SanvyaShadows.shadow(dark: colorScheme == .dark))
    }
}

/// `.row-tile` — a row inside a card, separated by space and a recessed
/// surface rather than a hairline divider.
public struct SanvyaRowTile<Content: View>: View {
    private let isOpen: Bool
    private let action: (() -> Void)?
    private let content: () -> Content

    public init(isOpen: Bool = false, action: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.isOpen = isOpen
        self.action = action
        self.content = content
    }

    public var body: some View {
        if let action {
            Button(action: action) { surface }.buttonStyle(SanvyaPressStyle())
        } else {
            surface
        }
    }

    private var surface: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SanvyaRadius.row, style: .continuous)
                    .fill(isOpen ? Color.accentGhost : Color.surface2)
            )
    }
}

/// `.row-stack` — the 6pt gap between row tiles.
public struct SanvyaRowStack<Content: View>: View {
    private let content: () -> Content
    public init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    public var body: some View {
        VStack(alignment: .leading, spacing: 6, content: content)
    }
}

/**
 `.list-grid` — `repeat(auto-fill, minmax(min(320px, 100%), 1fr))`.

 `.adaptive(minimum:)` is the same rule: as many equal columns as fit at the
 minimum width, collapsing to one when the container is narrower.
 */
public struct SanvyaListGrid<Content: View>: View {
    private let minColumnWidth: CGFloat
    private let content: () -> Content

    public init(
        minColumnWidth: CGFloat = SanvyaMetrics.ListGrid.minColumnWidth,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.minColumnWidth = minColumnWidth
        self.content = content
    }

    public var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minColumnWidth), spacing: SanvyaMetrics.ListGrid.gap, alignment: .top)],
            alignment: .leading,
            spacing: SanvyaMetrics.ListGrid.gap,
            content: content
        )
    }
}
