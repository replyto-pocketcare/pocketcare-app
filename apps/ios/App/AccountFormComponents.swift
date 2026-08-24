import SwiftUI

/// Shared constants + form pieces for the account create/edit screens --
/// mirrors Android's CreateAccountViewModel.kt's ACCOUNT_TYPES/
/// ACCOUNT_CURRENCIES/ACCOUNT_COLOR_HEX exactly (byte-for-byte, so the two
/// platforms show the same options in the same order). Split into its own
/// file per the Phase B "component reuse" rule -- CreateAccountView and
/// EditAccountView both need the chip row + color swatch row.

/// The 7 apps/web AccountType values (packages/types/src/index.ts),
/// regular-account path only per docs/mobile/screen-specs/accounts.md scope.
let accountTypes = FormOptions.accountTypes
let accountCurrencies = FormOptions.currencies

/// Hex, because hex is what `accounts.color` stores.
let accountColorHex = FormOptions.accountColors

func accountTypeLabel(_ type: String) -> String {
    type.replacingOccurrences(of: "_", with: " ").capitalized
}

/// Minimal wrapping flow layout (iOS 16+ Layout protocol) -- SwiftUI has no
/// built-in equivalent of Compose's FlowRow, and a fixed HStack would clip
/// or overflow with 7-9 options depending on device width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + width, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct ChipRow: View {
    let options: [String]
    let selected: String
    var label: (String) -> String = { $0 }
    let onSelect: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selected
                Button(label(option)) { onSelect(option) }
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(isSelected ? Color.accent : Color.surface2)
                    .foregroundColor(isSelected ? .white : Color.text)
                    .clipShape(Capsule())
            }
        }
    }
}

struct ColorSwatchRow: View {
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(accountColorHex, id: \.self) { hex in
                let isSelected = hex == selected
                Circle()
                    .fill(Color(hex: hex) ?? .gray)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Circle().stroke(isSelected ? Color.text : Color.border, lineWidth: isSelected ? 3 : 2)
                    )
                    .onTapGesture { onSelect(hex) }
            }
        }
    }
}

struct AllowNegativeToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Allow negative balance")
                    .font(.system(size: 14))
                    .foregroundColor(Color.text)
                Text(isOn
                    ? "This account can go below zero without a warning."
                    : "You'll be warned before this account would go below zero.")
                    .font(.system(size: 12))
                    .foregroundColor(Color.text2)
            }
        }
    }
}
