package com.sanvya.app.ui.shell

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.LocalSanvyaShadows
import com.sanvya.app.theme.SanvyaIcons
import com.sanvya.app.theme.SanvyaMetrics
import com.sanvya.app.theme.SanvyaShape
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.SanvyaIcon
import com.sanvya.app.ui.components.SanvyaText
import com.sanvya.app.ui.components.press
import com.sanvya.app.ui.components.sanvyaShadow

/**
 * The floating bottom bar — web's only navigation on a phone.
 *
 * Seven slots, balanced three-and-three around a raised "+":
 * `Home · slot · slot · + · slot · slot · More`.
 *
 * Hand-built rather than `NavigationBar`, because Material's bar cannot produce
 * either of the two things that define this design: a capsule floating inset
 * from the screen edges, and a centre button that rises above its own container.
 *
 * Every number is a generated token — see `docs/mobile/screen-specs/app-shell.md`
 * for the mapping back to `globals.css`.
 */
@Composable
fun BottomNav(
    currentRoute: String?,
    navIds: List<String>,
    unreadCount: Int,
    addLabel: String,
    onNavigate: (String) -> Unit,
    onAdd: () -> Unit,
    onMore: () -> Unit,
    moreOpen: Boolean,
    modifier: Modifier = Modifier,
) {
    val colors = LocalSanvyaColors.current
    val nav = SanvyaMetrics.BottomNav
    // Labels are hidden on the smallest tier -- every phone, and any window
    // narrow enough to be phone-shaped. One source of truth: the shell's window
    // class, not a second width check that could drift from it.
    val compact = !LocalWindowClass.current.showsNavLabels
    val items = NavPrefs.itemsFor(navIds)

    Row(
        modifier = modifier
            .widthIn(max = nav.maxWidth)
            .fillMaxWidth()
            .sanvyaShadow(LocalSanvyaShadows.current.shadowLg, SanvyaShape.pill)
            .clip(SanvyaShape.pill)
            .background(colors.surface)
            .border(1.dp, colors.border, SanvyaShape.pill)
            .padding(horizontal = nav.paddingH, vertical = nav.paddingV),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(nav.itemGap),
    ) {
        NavItem(
            glyph = SanvyaIcons.spaceDashboard,
            label = "Home",
            active = isActive(currentRoute, "dashboard"),
            compact = compact,
            onClick = { onNavigate("dashboard") },
        )

        items.take(2).forEach { item ->
            NavItem(
                glyph = item.glyph,
                label = item.label,
                active = isActive(currentRoute, item.route),
                compact = compact,
                onClick = { onNavigate(item.route) },
            )
        }

        AddButton(label = addLabel, compact = compact, onClick = onAdd)

        items.drop(2).take(2).forEach { item ->
            NavItem(
                glyph = item.glyph,
                label = item.label,
                active = isActive(currentRoute, item.route),
                compact = compact,
                onClick = { onNavigate(item.route) },
            )
        }

        NavItem(
            glyph = SanvyaIcons.moreHoriz,
            label = "More",
            active = moreOpen,
            compact = compact,
            badgeDot = unreadCount > 0,
            onClick = onMore,
        )
    }
}

/**
 * Web's active test, ported exactly:
 * `href === "/" ? path === "/" : path.startsWith(href)`.
 *
 * The prefix match is what keeps "Accounts" lit while you are on
 * `accounts/new`, and the equality special-case is what stops Home lighting up
 * on every screen.
 */
private fun isActive(currentRoute: String?, route: String): Boolean {
    if (currentRoute == null) return false
    return if (route == "dashboard") currentRoute == "dashboard" else currentRoute.startsWith(route)
}

@Composable
private fun RowScope.NavItem(
    glyph: String,
    label: String,
    active: Boolean,
    compact: Boolean,
    onClick: () -> Unit,
    badgeDot: Boolean = false,
) {
    val colors = LocalSanvyaColors.current
    val nav = SanvyaMetrics.BottomNav
    val interaction = remember { MutableInteractionSource() }
    val tint = if (active) colors.accent else colors.text2

    Box(
        modifier = Modifier
            .weight(1f)
            .height(if (compact) nav.itemHeightCompact else nav.itemHeight)
            .press(interaction)
            .clip(SanvyaShape.pill)
            .background(if (active) colors.accentGhost else Color.Transparent)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            // One label for the whole item: the icon is decorative next to it.
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            SanvyaIcon(glyph, size = 22.dp, tint = tint)
            if (!compact) {
                SanvyaText(
                    text = label,
                    style = SanvyaType.navLabel,
                    color = tint,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        if (badgeDot) {
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .offset(x = (-6).dp, y = 2.dp)
                    .size(8.dp)
                    .clip(SanvyaShape.pill)
                    .background(colors.negative),
            )
        }
    }
}

/**
 * The raised "+".
 *
 * `offset(y = -addOverhang)` is web's `margin-top: -14px`: the button sits
 * above the bar's own bounds, and the `--surface` ring is what reads as a
 * cut-out in the bar behind it.
 */
@Composable
private fun AddButton(label: String, compact: Boolean, onClick: () -> Unit) {
    val colors = LocalSanvyaColors.current
    val nav = SanvyaMetrics.BottomNav
    val interaction = remember { MutableInteractionSource() }
    val size = if (compact) nav.addSizeCompact else nav.addSize

    Box(
        modifier = Modifier
            .padding(horizontal = nav.addSideMargin)
            .offset(y = -nav.addOverhang)
            .size(size)
            .press(interaction)
            .sanvyaShadow(LocalSanvyaShadows.current.shadowAccent, SanvyaShape.pill)
            .clip(SanvyaShape.pill)
            .background(colors.surface)
            .padding(nav.addRingWidth)
            .clip(SanvyaShape.pill)
            .background(colors.accent)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        SanvyaIcon(SanvyaIcons.add, size = 24.dp, tint = Color.White)
    }
}
