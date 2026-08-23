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
 * Phones are always below web's 640px breakpoint, so `*Compact` values are
 * the ones a phone actually renders. A large tablet in landscape crosses it —
 * the shell picks per WindowSizeClass.
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
