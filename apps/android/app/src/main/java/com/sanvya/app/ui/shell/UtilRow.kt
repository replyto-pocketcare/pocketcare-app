package com.sanvya.app.ui.shell

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaIcons
import com.sanvya.app.theme.SanvyaMetrics
import com.sanvya.app.theme.SanvyaShape
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.SanvyaIcon
import com.sanvya.app.ui.components.SanvyaText
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.ui.components.press

/**
 * The in-flow utility row: one Back affordance on the left, the notification
 * bell on the right.
 *
 * **A screen gets at most one back affordance, and this is it.** Web deleted
 * every page-local "← back to X" link to guarantee that, so no screen may add a
 * `TopAppBar` navigation icon on top of this row.
 *
 * In normal flow rather than floating, which is deliberate: the previous
 * design used a fixed-position bell and it collided with pages that had their
 * own header controls.
 */
@Composable
fun UtilRow(
    showBack: Boolean,
    unreadCount: Int,
    onBack: () -> Unit,
    onNotifications: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val util = SanvyaMetrics.UtilRow
    Row(
        modifier = modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = util.minHeight)
            .padding(bottom = util.marginBottom),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (showBack) BackButton(onBack) else Box(Modifier)
        NotifBell(unreadCount, onNotifications)
    }
}

@Composable
private fun BackButton(onBack: () -> Unit) {
    // Hoisted: `semantics { }` is a plain lambda, not a composable one, so
    // `sRes()` cannot be called inside it.
    val backLabel = S.Translation.commonBack(sRes())
    val colors = LocalSanvyaColors.current
    val util = SanvyaMetrics.UtilRow
    val interaction = remember { MutableInteractionSource() }
    Row(
        modifier = Modifier
            .height(util.buttonSize)
            .press(interaction)
            .clip(SanvyaShape.pill)
            .background(colors.surface)
            .border(1.dp, colors.border, SanvyaShape.pill)
            .clickable(interactionSource = interaction, indication = null, onClick = onBack)
            .padding(start = util.backPaddingStart, end = util.backPaddingEnd)
            .semantics { contentDescription = backLabel },
        horizontalArrangement = Arrangement.spacedBy(util.backGap),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SanvyaIcon(SanvyaIcons.arrowBack, size = 18.dp, tint = colors.text)
        SanvyaText(backLabel, SanvyaType.statLabel, color = colors.text)
    }
}

/** The bell, with its unread badge capped at "9+" exactly as web caps it. */
@Composable
fun NotifBell(unreadCount: Int, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalSanvyaColors.current
    val util = SanvyaMetrics.UtilRow
    val interaction = remember { MutableInteractionSource() }
    val description = if (unreadCount > 0) S.Translation.navNotifications(sRes()) + " ($unreadCount)" else S.Translation.navNotifications(sRes())

    Box(
        modifier = modifier
            .size(util.buttonSize)
            .press(interaction)
            .clip(SanvyaShape.pill)
            .background(colors.surface)
            .border(1.dp, colors.border, SanvyaShape.pill)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        SanvyaIcon(SanvyaIcons.notifications, size = 19.dp, tint = colors.text)
        if (unreadCount > 0) {
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .offset(x = (-3).dp, y = 3.dp)
                    .widthIn(min = 15.dp)
                    .height(15.dp)
                    .clip(SanvyaShape.pill)
                    .background(colors.negative)
                    .padding(horizontal = 3.dp),
                contentAlignment = Alignment.Center,
            ) {
                SanvyaText(
                    text = if (unreadCount > 9) "9+" else unreadCount.toString(),
                    style = SanvyaType.navLabel,
                    color = Color.White,
                )
            }
        }
    }
}
