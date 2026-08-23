import SwiftUI

/// `.press` — the universal 0.97 tap feedback, 120ms on the standard curve.
public struct SanvyaPressStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? SanvyaMotion.pressScale : 1)
            .animation(SanvyaMotion.standard(SanvyaMotion.pressDuration), value: configuration.isPressed)
    }
}

/// `.lift:active` — the gentler 0.985 for cards and tiles, where a 3% snap
/// reads as a glitch rather than a press.
public struct SanvyaLiftPressStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? SanvyaMotion.liftPressScale : 1)
            .animation(SanvyaMotion.standard(SanvyaMotion.liftPressDuration), value: configuration.isPressed)
    }
}

/**
 `.btn` — the terracotta pill, and `.btn.ghost`.

 Hand-drawn rather than `.buttonStyle(.borderedProminent)`: the system style
 owns its corner radius, tint treatment and disabled appearance, none of which
 match, and overriding all three is more code than drawing the button.
 */
public struct SanvyaButton<Label: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    private let ghost: Bool
    private let action: () -> Void
    private let label: () -> Label

    public init(ghost: Bool = false, action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.ghost = ghost
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) { label() }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 40)
                .sanvyaStyle(SanvyaType.button)
                .foregroundStyle(ghost ? Color.text : Color.white)
                .background(ghost ? Color.surface : Color.accent)
                .clipShape(Capsule())
                .overlay {
                    if ghost { Capsule().strokeBorder(Color.borderStrong, lineWidth: 1) }
                }
                // `.btn.ghost` carries no shadow at all — that is what
                // distinguishes it, not just the fill.
                .modifier(ConditionalShadow(active: !ghost && isEnabled, shadow: SanvyaShadows.shadowAccent(dark: colorScheme == .dark)))
                // `.btn:disabled { opacity: 0.45 }` — the whole control fades,
                // label included, rather than swapping to a disabled palette.
                .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(SanvyaPressStyle())
    }
}

private struct ConditionalShadow: ViewModifier {
    let active: Bool
    let shadow: SanvyaShadow
    func body(content: Content) -> some View {
        if active { content.sanvyaShadow(shadow) } else { content }
    }
}

/// `.chip` — pill with a hairline border; `[data-active]` fills with accent.
public struct SanvyaChip: View {
    private let label: String
    private let isActive: Bool
    private let action: () -> Void

    public init(_ label: String, isActive: Bool, action: @escaping () -> Void) {
        self.label = label
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label)
                .sanvyaStyle(SanvyaType.chip)
                .lineLimit(1)
                .foregroundStyle(isActive ? Color.white : Color.text)
                // Phones (<560px on web) tighten horizontal padding to 8 so a
                // header chip row stays on one line.
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(isActive ? Color.accent : Color.surface)
                .clipShape(Capsule())
                .overlay {
                    Capsule().strokeBorder(isActive ? Color.accent : Color.border, lineWidth: 1)
                }
                .animation(SanvyaMotion.standard(SanvyaMotion.colorFadeDuration), value: isActive)
        }
        .buttonStyle(SanvyaPressStyle())
    }
}

/**
 `.input` — 12pt radius, hairline border, and on focus a solid 3pt
 `--accent-ghost` halo (CSS writes it as a zero-blur box-shadow, which is a
 ring, not a shadow) plus an `--accent-soft` border.
 */
public struct SanvyaInput<Leading: View, Trailing: View>: View {
    @FocusState private var focused: Bool
    @Binding private var text: String
    private let placeholder: String
    private let isSecure: Bool
    private let leading: () -> Leading
    private let trailing: () -> Trailing

    public init(
        text: Binding<String>,
        placeholder: String = "",
        isSecure: Bool = false,
        @ViewBuilder leading: @escaping () -> Leading = { EmptyView() },
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self._text = text
        self.placeholder = placeholder
        self.isSecure = isSecure
        self.leading = leading
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: 8) {
            leading()
            Group {
                if isSecure {
                    SecureField("", text: $text, prompt: promptText)
                } else {
                    TextField("", text: $text, prompt: promptText)
                }
            }
            .focused($focused)
            .textFieldStyle(.plain)
            .sanvyaStyle(SanvyaType.body)
            .foregroundStyle(Color.text)
            .tint(Color.accent)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: SanvyaRadius.radiusSm, style: .continuous)
                .fill(Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SanvyaRadius.radiusSm, style: .continuous)
                .strokeBorder(focused ? Color.accentSoft : Color.border, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SanvyaRadius.radiusSm + 3, style: .continuous)
                .strokeBorder(Color.accentGhost, lineWidth: 3)
                .opacity(focused ? 1 : 0)
                .padding(-3)
        )
        .animation(SanvyaMotion.standard(SanvyaMotion.colorFadeDuration), value: focused)
    }

    private var promptText: Text {
        Text(placeholder).foregroundStyle(Color.text2)
    }
}
