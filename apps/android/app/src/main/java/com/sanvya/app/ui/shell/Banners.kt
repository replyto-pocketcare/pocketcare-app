package com.sanvya.app.ui.shell

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaMetrics
import com.sanvya.app.theme.SanvyaShape
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.SanvyaText

/**
 * The app-wide banners, in web's z-order: sync problems above offline, both
 * above everything else. They are full-width strips rather than page content,
 * so they read as system messages.
 */

/**
 * Shown whenever connectivity is lost.
 *
 * The copy is web's, verbatim — it is doing real work: telling someone their
 * data is safe on the device is the difference between "the app is broken" and
 * "the app is waiting".
 */
@Composable
fun OfflineBanner(offline: Boolean) {
    if (!offline) return
    val colors = LocalSanvyaColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.warning)
            .padding(horizontal = SanvyaMetrics.Banner.paddingH, vertical = SanvyaMetrics.Banner.paddingV)
            .semantics { liveRegion = LiveRegionMode.Polite },
        horizontalArrangement = Arrangement.spacedBy(SanvyaMetrics.Banner.gap, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(7.dp)
                .clip(SanvyaShape.pill)
                .background(Color.White.copy(alpha = 0.9f)),
        )
        SanvyaText(
            text = "You're offline — changes are saved on this device and will sync when you're back online.",
            style = SanvyaType.statLabel,
            color = Color.White,
        )
    }
}

/**
 * Shown while any write sits quarantined in `failed_writes`.
 *
 * Discoverability is the entire point. The failure this covers is silent by
 * design — the upload queue unblocks, everything else syncs, and the app looks
 * perfectly healthy while a few of someone's expenses sit in limbo. A recovery
 * screen buried in Settings is only ever found by someone who already suspects
 * something is wrong. So the app says so, unprompted, until it is dealt with.
 */
@Composable
fun SyncProblemsBanner(count: Int, onReview: () -> Unit) {
    if (count <= 0) return
    val colors = LocalSanvyaColors.current
    val interaction = remember { MutableInteractionSource() }
    val message = if (count == 1) {
        "1 change couldn't be saved — tap to review"
    } else {
        "$count changes couldn't be saved — tap to review"
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.negative)
            .clickable(interactionSource = interaction, indication = null, onClick = onReview)
            .padding(horizontal = SanvyaMetrics.Banner.paddingH, vertical = SanvyaMetrics.Banner.paddingV)
            .semantics { liveRegion = LiveRegionMode.Assertive },
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SanvyaText(text = message, style = SanvyaType.statLabel, color = Color.White)
    }
}

/**
 * The in-flow sync status strip — not sticky, unlike the two above, because it
 * is informational rather than a problem to act on.
 */
@Composable
fun SyncStatusStrip(message: String?, warn: Boolean, onForceSync: (() -> Unit)?) {
    if (message == null) return
    val colors = LocalSanvyaColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 16.dp)
            .clip(SanvyaShape.row)
            .background(if (warn) colors.accentGhost else colors.surface2)
            .padding(horizontal = 14.dp, vertical = 9.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(SanvyaShape.pill)
                .background(if (warn) colors.warning else colors.text2),
        )
        SanvyaText(
            text = message,
            style = SanvyaType.statLabel,
            color = if (warn) colors.text else colors.text2,
            modifier = Modifier.weight(1f),
        )
        if (onForceSync != null) {
            val interaction = remember { MutableInteractionSource() }
            SanvyaText(
                text = "Force Sync",
                style = SanvyaType.statLabel,
                color = colors.accent,
                modifier = Modifier.clickable(
                    interactionSource = interaction,
                    indication = null,
                    onClick = onForceSync,
                ),
            )
        }
    }
}
