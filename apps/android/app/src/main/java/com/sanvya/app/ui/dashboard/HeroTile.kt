package com.sanvya.app.ui.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.SanvyaText

/**
 * The "showpiece" tiles — light content on an earthy gradient.
 *
 * Web gives four tiles this treatment (Budgets, Goals, Subscriptions,
 * Cashflow) and only those four. Ported with the same gradients, because the
 * colour is what distinguishes one from another at a glance on a busy
 * dashboard; a single accent-coloured card for all four would lose that.
 *
 * The gradients are hardcoded here, matching web, and NOT generated. They are
 * four two-stop CSS gradients in one file with no other consumer — the kind of
 * value the catalogue exists to hold only once there is a second reader. If a
 * fifth hero tile ever appears, that is the moment to move them.
 */
enum class HeroTint(val start: Color, val end: Color) {
    // linear-gradient(150deg, #b06a4f, #8f533c)
    CASHFLOW(Color(0xFFB06A4F), Color(0xFF8F533C)),
    BUDGETS(Color(0xFFC08A3E), Color(0xFFA8503A)),
    GOALS(Color(0xFF2F6F6A), Color(0xFF3E4A38)),
    SUBS(Color(0xFF7A4A6B), Color(0xFF4F3A54)),
}

/** `rgba(246,240,231,0.82)` — web's HERO_MUTED. */
val heroInk = Color(0xFFF6F0E7)
val heroInkMuted = Color(0xFFF6F0E7).copy(alpha = 0.82f)

@Composable
fun HeroTile(
    title: String,
    tint: HeroTint,
    onOpen: (() -> Unit)?,
    trailing: @Composable (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(24.dp))
            .background(
                // 150deg in CSS runs top-left-ish to bottom-right-ish. Compose
                // takes explicit endpoints; Offset.Infinite lets the gradient
                // size itself to the tile rather than to a guessed pixel span.
                Brush.linearGradient(
                    colors = listOf(tint.start, tint.end),
                    start = Offset.Zero,
                    end = Offset.Infinite,
                )
            )
            .then(if (onOpen != null) Modifier.clickable(onClick = onOpen) else Modifier)
            .padding(horizontal = 24.dp, vertical = 22.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            SanvyaText(
                title.uppercase(),
                style = SanvyaType.eyebrow,
                color = heroInk.copy(alpha = 0.72f),
                modifier = Modifier.weight(1f),
            )
            trailing?.invoke()
        }
        content()
    }
}

/**
 * Web's `LightBar` — a progress track on a hero tile.
 *
 * Its own track is white at 18% rather than a design token: the tile behind it
 * is a gradient, so a surface-coloured track would be invisible on one end of
 * it and wrong on the other.
 */
@Composable
fun LightBar(pct: Float, color: Color = heroInk, modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxWidth()
            .height(8.dp)
            .clip(RoundedCornerShape(999.dp))
            .background(Color.White.copy(alpha = 0.18f)),
    ) {
        Box(
            Modifier
                .fillMaxWidth(pct.coerceIn(0f, 100f) / 100f)
                .height(8.dp)
                .clip(RoundedCornerShape(999.dp))
                .background(color),
        )
    }
}
