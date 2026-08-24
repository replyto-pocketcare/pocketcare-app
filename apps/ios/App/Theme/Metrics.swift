import SwiftUI

// GENERATED FILE — do not hand-edit.
// Source: apps/web/app/globals.css + tools/parity/tokens.spec.mjs
// Regenerate with: node tools/parity/generate-tokens.mjs

/**
 Shell metrics. `bottomInset` is web's literal offset; the safe-area inset is
 added on top, exactly as `env(safe-area-inset-bottom)` does on web.

 The `Compact` values are what an iPhone renders; `Expanded` is the
 iPad/foldable sidebar layout. Which one applies is decided by
 `SanvyaWindowClass`, from the platform's size classes — not from the web
 breakpoints these values were read out of.
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


    /**
     The expanded layout: sidebar, top bar, and the inset window frame the app
     sits in. globals.css:594-700.

     Web's values, kept as web's values -- an iPad should look like the desktop
     browser. Only the threshold at which we switch to this is the platform's.
     */
    public enum Expanded {
        public static let frameInset: CGFloat = 16
        public static let frameRadius: CGFloat = 26
        public static let sidebarInset: CGFloat = 17
        public static let sidebarWidth: CGFloat = 252
        public static let sidebarRadius: CGFloat = 25
        public static let sidebarPaddingTop: CGFloat = 18
        public static let sidebarPaddingH: CGFloat = 14
        public static let sidebarPaddingBottom: CGFloat = 14
        public static let sidebarGap: CGFloat = 4
        public static let brandSize: CGFloat = 26
        public static let brandPaddingBottom: CGFloat = 14
        public static let searchPaddingV: CGFloat = 10
        public static let searchPaddingH: CGFloat = 12
        public static let searchMarginBottom: CGFloat = 12
        public static let searchRadius: CGFloat = 12
        public static let searchIconSize: CGFloat = 16
        public static let itemPaddingV: CGFloat = 9
        public static let itemPaddingH: CGFloat = 10
        public static let itemRadius: CGFloat = 10
        public static let itemGap: CGFloat = 10
        public static let itemIconSize: CGFloat = 19
        public static let railWidth: CGFloat = 3
        public static let railHeight: CGFloat = 20
        public static let railOffset: CGFloat = 14
        public static let badgeMinWidth: CGFloat = 18
        public static let badgeHeight: CGFloat = 18
        public static let footPaddingTop: CGFloat = 10
        public static let topBarHeight: CGFloat = 36
        public static let topBarGap: CGFloat = 16
        public static let topBarPaddingV: CGFloat = 10
        public static let topBarMarginBottom: CGFloat = 18
        public static let topIconSize: CGFloat = 36
        public static let topDotSize: CGFloat = 7
        public static let avatarSize: CGFloat = 36
        public static let contentPaddingTop: CGFloat = 24
        public static let contentPaddingH: CGFloat = 32
        public static let contentPaddingBottom: CGFloat = 40
        public static let contentMaxWidth: CGFloat = 1440
    }

    /**
     Material 3's window size class breakpoints — the platform's numbers, not
     web's, and the *same* numbers Android reads, so the two apps agree about
     what counts as a tablet.
     */
    public enum WindowClass {
        public static let mediumWidth: CGFloat = 600
        public static let expandedWidth: CGFloat = 840
        public static let mediumHeight: CGFloat = 480
    }

    public enum PageHeader {
        public static let sectionGap: CGFloat = 20
        public static let headerGap: CGFloat = 12
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
