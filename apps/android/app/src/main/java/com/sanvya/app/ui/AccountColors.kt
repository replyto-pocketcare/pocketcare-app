package com.sanvya.app.ui

import androidx.compose.ui.graphics.Color

/**
 * ACCOUNT_COLORS + colorForId, ported byte-for-byte from
 * apps/web/src/colors.ts. Deliberately distinct from the earthy SanvyaColors
 * design tokens (theme/Color.kt) -- includes jewel tones (indigo/violet/
 * denim) -- used only for per-account chip/bar coloring.
 *
 * Extracted 2026-08-05 (was inlined twice already -- once in
 * DashboardScreen.kt, then almost a third time in AccountsScreen.kt -- see
 * docs/mobile/screen-specs/accounts.md "Shared: colorForId" and the Phase B
 * checklist's "component reuse, no inline re-implementation" rule).
 */
val ACCOUNT_COLORS: List<Color> = listOf(
    0xFF3E4A38, 0xFF5F6647, 0xFF6B7A4F, 0xFF9CAE8E, 0xFFB06A4F, 0xFFC98A72,
    0xFFA8503A, 0xFF7C4A3A, 0xFF5F4636, 0xFFC9B79C, 0xFFC08A3E, 0xFF4F46E5,
    0xFF6D5ACF, 0xFF3F5A8A, 0xFF2F6F6A, 0xFF7A4A6B, 0xFF4B5563, 0xFF2B2723,
).map { Color(it or 0xFF000000) }

fun colorForId(id: String?): Color {
    if (id.isNullOrEmpty()) return Color(0xFF7C7264)
    var h = 0L
    for (c in id) {
        h = (h * 31 + c.code) and 0xFFFFFFFFL
    }
    return ACCOUNT_COLORS[(h % ACCOUNT_COLORS.size).toInt()]
}

fun accountColor(explicit: String?, id: String): Color {
    if (!explicit.isNullOrBlank()) {
        return try {
            Color(android.graphics.Color.parseColor(explicit))
        } catch (e: IllegalArgumentException) {
            colorForId(id)
        }
    }
    return colorForId(id)
}
