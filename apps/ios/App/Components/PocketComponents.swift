import SwiftUI

public struct PocketCard<Content: View>: View {
    let content: Content
    
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    public var body: some View {
        content
            .padding(16)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
            .shadow(color: Color.black.opacity(0.16), radius: 30, x: 0, y: 12)
    }
}

public struct RowTile<Trailing: View, Leading: View>: View {
    let title: String
    let subtitle: String?
    let action: (() -> Void)?
    let trailing: Trailing
    let leading: Leading
    
    public init(
        title: String,
        subtitle: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder leading: () -> Leading = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.trailing = trailing()
        self.leading = leading()
    }
    
    public var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: 12) {
                leading
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.text)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.text2)
                    }
                }
                
                Spacer()
                
                trailing
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(RowTileButtonStyle(enabled: action != nil))
        .disabled(action == nil)
    }
}

struct RowTileButtonStyle: ButtonStyle {
    let enabled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed && enabled ? Color.border : Color.clear)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

public struct PrimaryButton: View {
    let text: String
    let isGhost: Bool
    let action: () -> Void
    
    public init(_ text: String, isGhost: Bool = false, action: @escaping () -> Void) {
        self.text = text
        self.isGhost = isGhost
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
        }
        .buttonStyle(PrimaryButtonStyle(isGhost: isGhost))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    let isGhost: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isGhost ? .text : .white)
            .background(isGhost ? Color.surface : Color.accent)
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .stroke(isGhost ? Color.borderStrong : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
            .shadow(color: isGhost ? .clear : Color.accent.opacity(0.9), radius: 12, x: 0, y: 10)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

public struct FloatingInput: View {
    let label: String
    @Binding var text: String
    
    @FocusState private var isFocused: Bool
    
    public init(_ label: String, text: Binding<String>) {
        self.label = label
        self._text = text
    }
    
    public var body: some View {
        ZStack(alignment: .leading) {
            Text(label)
                .foregroundColor(isFocused || !text.isEmpty ? .accentSoft : .text2)
                .font(.system(size: isFocused || !text.isEmpty ? 11 : 15))
                .offset(y: isFocused || !text.isEmpty ? -12 : 0)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                .animation(.easeOut(duration: 0.15), value: text.isEmpty)
            
            TextField("", text: $text)
                .focused($isFocused)
                .font(.system(size: 15))
                .padding(.top, 14) // Make room for floating label
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isFocused ? Color.accentSoft : Color.border, lineWidth: 1)
        )
        // Add focus ring effect (shadow outline) if focused
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isFocused ? Color.accent.opacity(0.15) : Color.clear, lineWidth: 3)
                .scaleEffect(1.02)
        )
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
