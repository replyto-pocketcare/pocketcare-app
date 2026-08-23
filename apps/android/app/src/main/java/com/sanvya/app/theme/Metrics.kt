package com.sanvya.app.theme

import androidx.compose.ui.unit.dp

// GENERATED FILE — do not hand-edit.
// Source: apps/web/app/globals.css + tools/parity/tokens.spec.mjs
// Regenerate with: node tools/parity/generate-tokens.mjs

/**
 * Shell metrics — the numbers that make the bottom bar, utility row and page
 * padding land where web puts them. `bottomInset` is web's literal offset;
 * the platform safe-area inset is added on top, exactly as
 * `env(safe-area-inset-bottom)` does.
 *
 * `*Compact` values are what a phone renders; `Expanded` is the
 * tablet/foldable sidebar layout. Which one applies is decided by
 * `SanvyaWindowClass`, from Material 3's breakpoints — not from the web
 * breakpoints these values were read out of.
 */
object SanvyaMetrics {
    object BottomNav {
        val sideInset = 16.dp
        val bottomInset = 14.dp
        val maxWidth = 460.dp
        val paddingV = 6.dp
        val paddingH = 8.dp
        val itemGap = 2.dp
        val itemHeight = 52.dp
        val itemHeightCompact = 46.dp
        val addSize = 52.dp
        val addSizeCompact = 48.dp
        val addRingWidth = 3.dp
        val addOverhang = 14.dp
        val addSideMargin = 6.dp
        val labelHiddenBelow = 640.dp
    }


    /**
     * The expanded layout: sidebar, top bar, and the inset window frame the app
     * sits in. globals.css:594-700.
     *
     * Web's values, kept as web's values -- a tablet should look like the
     * desktop browser. Only the threshold at which we switch to this is the
     * platform's; see SanvyaWindowClass.
     */
    object Expanded {
        val frameInset = 16.dp
        val frameRadius = 26.dp
        val sidebarInset = 17.dp
        val sidebarWidth = 252.dp
        val sidebarRadius = 25.dp
        val sidebarPaddingTop = 18.dp
        val sidebarPaddingH = 14.dp
        val sidebarPaddingBottom = 14.dp
        val sidebarGap = 4.dp
        val brandSize = 26.dp
        val brandPaddingBottom = 14.dp
        val searchPaddingV = 10.dp
        val searchPaddingH = 12.dp
        val searchMarginBottom = 12.dp
        val searchRadius = 12.dp
        val searchIconSize = 16.dp
        val itemPaddingV = 9.dp
        val itemPaddingH = 10.dp
        val itemRadius = 10.dp
        val itemGap = 10.dp
        val itemIconSize = 19.dp
        val railWidth = 3.dp
        val railHeight = 20.dp
        val railOffset = 14.dp
        val badgeMinWidth = 18.dp
        val badgeHeight = 18.dp
        val footPaddingTop = 10.dp
        val topBarHeight = 36.dp
        val topBarGap = 16.dp
        val topBarPaddingV = 10.dp
        val topBarMarginBottom = 18.dp
        val topIconSize = 36.dp
        val topDotSize = 7.dp
        val avatarSize = 36.dp
        val contentPaddingTop = 24.dp
        val contentPaddingH = 32.dp
        val contentPaddingBottom = 40.dp
        val contentMaxWidth = 1440.dp
    }

    object PageHeader {
        val sectionGap = 20.dp
        val headerGap = 12.dp
    }

    object UtilRow {
        val minHeight = 40.dp
        val gap = 10.dp
        val marginBottom = 8.dp
        val buttonSize = 40.dp
        val backPaddingStart = 12.dp
        val backPaddingEnd = 14.dp
        val backGap = 6.dp
    }

    object Page {
        val paddingTop = 10.dp
        val paddingHorizontal = 16.dp
        val paddingBottom = 96.dp
        val maxWidth = 720.dp
    }

    object ListGrid {
        val minColumnWidth = 320.dp
        val gap = 12.dp
    }

    object AddPopover {
        val minWidth = 220.dp
        val bottomOffset = 84.dp
        val padding = 10.dp
        val gap = 8.dp
        val itemPaddingV = 10.dp
        val itemPaddingH = 12.dp
    }

    object Banner {
        val paddingV = 7.dp
        val paddingH = 14.dp
        val gap = 8.dp
    }
}
