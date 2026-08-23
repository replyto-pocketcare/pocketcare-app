import SwiftUI

// GENERATED FILE — do not hand-edit.
// Source: apps/web/app/globals.css + tools/parity/tokens.spec.mjs
// Regenerate with: node tools/parity/generate-tokens.mjs

/**
 Shell metrics. `bottomInset` is web's literal offset; the safe-area inset is
 added on top, exactly as `env(safe-area-inset-bottom)` does on web.

 iPhones are always below web's 640px breakpoint, so the `Compact` values are
 what a phone renders; iPad and landscape-regular cross it.
 */
public enum SanvyaMetrics {
    public enum BottomNav {
        public static let sideInset: CGFloat = 16
        public static let bottomInset: CGFloat = 14
        public static let maxWidth: CGFloat = 460
        public static let paddingV: CGFloat = 6
        public static let paddingH: CGFloat = 8
        public static let itemGap: CGFloat = 2
        public static let itemHeight: CGFloat = 52
        public static let itemHeightCompact: CGFloat = 46
        public static let addSize: CGFloat = 52
        public static let addSizeCompact: CGFloat = 48
        public static let addRingWidth: CGFloat = 3
        public static let addOverhang: CGFloat = 14
        public static let addSideMargin: CGFloat = 6
        public static let labelHiddenBelow: CGFloat = 640
    }

    public enum UtilRow {
        public static let minHeight: CGFloat = 40
        public static let gap: CGFloat = 10
        public static let marginBottom: CGFloat = 8
        public static let buttonSize: CGFloat = 40
        public static let backPaddingStart: CGFloat = 12
        public static let backPaddingEnd: CGFloat = 14
        public static let backGap: CGFloat = 6
    }

    public enum Page {
        public static let paddingTop: CGFloat = 10
        public static let paddingHorizontal: CGFloat = 16
        public static let paddingBottom: CGFloat = 96
        public static let maxWidth: CGFloat = 720
    }

    public enum ListGrid {
        public static let minColumnWidth: CGFloat = 320
        public static let gap: CGFloat = 12
    }

    public enum AddPopover {
        public static let minWidth: CGFloat = 220
        public static let bottomOffset: CGFloat = 84
        public static let padding: CGFloat = 10
        public static let gap: CGFloat = 8
        public static let itemPaddingV: CGFloat = 10
        public static let itemPaddingH: CGFloat = 12
    }

    public enum Banner {
        public static let paddingV: CGFloat = 7
        public static let paddingH: CGFloat = 14
        public static let gap: CGFloat = 8
    }
}
