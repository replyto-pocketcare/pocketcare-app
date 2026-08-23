package com.sanvya.app.ui.shell

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaIcons
import com.sanvya.app.theme.SanvyaMetrics
import com.sanvya.app.theme.SanvyaShape
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.Eyebrow
import com.sanvya.app.ui.components.SanvyaIcon
import com.sanvya.app.ui.components.SanvyaText
import com.sanvya.app.ui.components.press

/**
 * The persistent sidebar shown at [SanvyaWindowClass.EXPANDED].
 *
 * A port of web's `.side-nav` (`globals.css:633-683`), which appears at the same
 * moment the floating bottom bar disappears. Both cannot be on screen at once —
 * two primary navigations is one too many, and web is emphatic about it.
 *
 * It renders the **same** [NAV_GROUPS] the More sheet renders, plus Home and
 * Notifications above them, because at this size the More sheet is unreachable
 * and anything exclusive to it would be lost.
 *
 * The bottom bar's four customizable slots have no meaning here: every
 * destination is already one tap away. `NavPrefs` is left untouched and unread,
 * so narrowing the window restores the bar exactly as the user arranged it.
 */
@Composable
fun SideNav(
    currentRoute: String?,
    unreadCount: Int,
    isGuest: Boolean,
    guestDaysLeft: Int?,
    appVersion: String,
    onNavigate: (String) -> Unit,
    onFeedback: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalSanvyaColors.current
    val x = SanvyaMetrics.Expanded

    Column(
        modifier = modifier
            .width(x.sidebarWidth)
            .fillMaxHeight()
            // Leading corners only, so it sits flush inside the window frame's
            // own radius rather than floating a rounded card against a corner.
            .clip(RoundedCornerShape(topStart = x.sidebarRadius, bottomStart = x.sidebarRadius))
            .background(colors.sidebar)
            .padding(
                top = x.sidebarPaddingTop,
                start = x.sidebarPaddingH,
                end = x.sidebarPaddingH,
                bottom = x.sidebarPaddingBottom,
            ),
        verticalArrangement = Arrangement.spacedBy(x.sidebarGap),
    ) {
        Box(modifier = Modifier.padding(start = 8.dp, end = 8.dp, bottom = x.brandPaddingBottom)) {
            SanvyaText("Sanvya", style = SanvyaType.h2, color = colors.text)
        }

        // Search is a row, not a field. At this width the add affordance moves
        // into the dashboard's own header, and search is the thing every screen
        // reaches for -- so it takes the primary slot. Tapping opens the real
        // search screen; nothing is typed here.
        val searchInteraction = remember { MutableInteractionSource() }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = x.searchMarginBottom)
                .press(searchInteraction)
                .clip(RoundedCornerShape(x.searchRadius))
                .background(colors.surface)
                .border(1.dp, colors.border, RoundedCornerShape(x.searchRadius))
                .clickable(
                    interactionSource = searchInteraction,
                    indication = null,
                    onClick = { onNavigate("search") },
                )
                .padding(horizontal = x.searchPaddingH, vertical = x.searchPaddingV),
            horizontalArrangement = Arrangement.spacedBy(9.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SanvyaIcon(SanvyaIcons.search, size = x.searchIconSize, tint = colors.text3)
            SanvyaText("Search anything…", style = SanvyaType.statLabel, color = colors.text3)
        }

        Column(
            modifier = Modifier.weight(1f).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            SideNavItem(
                glyph = SanvyaIcons.spaceDashboard,
                label = "Home",
                isActive = currentRoute == "dashboard",
                onClick = { onNavigate("dashboard") },
            )
            SideNavItem(
                glyph = SanvyaIcons.notifications,
                label = "Notifications",
                isActive = currentRoute == "notifications",
                badge = unreadCount,
                onClick = { onNavigate("notifications") },
            )

            NAV_GROUPS.forEach { group ->
                Column(
                    modifier = Modifier.padding(top = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    if (group.title.isNotEmpty()) {
                        Eyebrow(
                            group.title,
                            modifier = Modifier
                                .alpha(0.65f)
                                .padding(horizontal = 10.dp, vertical = 2.dp),
                        )
                    }
                    group.items.forEach { entry ->
                        SideNavItem(
                            glyph = entry.glyph,
                            label = entry.label,
                            isActive = currentRoute == entry.route,
                            onClick = { onNavigate(entry.route) },
                        )
                    }
                }
            }
        }

        Column(
            modifier = Modifier
                .padding(top = x.footPaddingTop)
                .fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(1.dp)
                    .background(colors.border),
            )
            Spacer(modifier = Modifier.height(x.footPaddingTop))

            if (isGuest) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 4.dp)
                        .clip(SanvyaShape.row)
                        .background(colors.accentGhost)
                        .border(1.dp, colors.accentSoft, SanvyaShape.row)
                        .clickable { onNavigate("login") }
                        .padding(horizontal = 10.dp, vertical = 9.dp),
                ) {
                    SanvyaText(
                        guestDaysLeft?.let { "Guest · ${it}d left" } ?: "Guest",
                        style = SanvyaType.statLabel.copy(fontWeight = FontWeight.Bold),
                        color = colors.text,
                    )
                    SanvyaText(
                        "Create account →",
                        style = SanvyaType.statLabel,
                        color = colors.accent,
                        modifier = Modifier.padding(top = 2.dp),
                    )
                }
            }

            SideNavItem(
                glyph = SanvyaIcons.chatBubble,
                label = "Feedback",
                isActive = false,
                onClick = onFeedback,
            )

            // Web's footer also offers "Install app". Deliberately not ported:
            // it is a PWA affordance, and this app is already installed.

            SanvyaText(
                "Sanvya v$appVersion",
                style = SanvyaType.navLabel,
                color = colors.text2,
                modifier = Modifier.alpha(0.7f).padding(start = 10.dp, end = 10.dp, top = 6.dp),
            )
        }
    }
}

/**
 * One sidebar row.
 *
 * The active row gets a colour, a heavier weight **and** a left rail marker.
 * The rail is not decoration: it is the cue that reads as "you are here" from
 * the corner of the eye, without having to parse a colour difference.
 */
@Composable
private fun SideNavItem(
    glyph: String,
    label: String,
    isActive: Boolean,
    badge: Int = 0,
    onClick: () -> Unit,
) {
    val colors = LocalSanvyaColors.current
    val x = SanvyaMetrics.Expanded

    val interaction = remember { MutableInteractionSource() }

    Box(contentAlignment = Alignment.CenterStart) {
        if (isActive) {
            Box(
                modifier = Modifier
                    .offset(x = -x.railOffset)
                    .width(x.railWidth)
                    .height(x.railHeight)
                    .clip(RoundedCornerShape(topEnd = 3.dp, bottomEnd = 3.dp))
                    .background(colors.accent),
            )
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .press(interaction)
                .clip(RoundedCornerShape(x.itemRadius))
                .background(if (isActive) colors.accentGhost else Color.Transparent)
                .clickable(interactionSource = interaction, indication = null, onClick = onClick)
                .padding(horizontal = x.itemPaddingH, vertical = x.itemPaddingV),
            horizontalArrangement = Arrangement.spacedBy(x.itemGap),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SanvyaIcon(
                glyph,
                size = x.itemIconSize,
                tint = if (isActive) colors.accent else colors.text,
            )
            SanvyaText(
                label,
                // Web's active row is weight 650 -- a real value, not a rounding
                // of "semibold": Inter is bundled as a VARIABLE font precisely so
                // 550/650 land where the design put them.
                style = if (isActive) {
                    SanvyaType.body.copy(fontWeight = FontWeight(650))
                } else {
                    SanvyaType.body
                },
                color = if (isActive) colors.accent else colors.text,
                modifier = Modifier.weight(1f),
            )
            if (badge > 0) {
                Box(
                    modifier = Modifier
                        .widthIn(min = x.badgeMinWidth)
                        .height(x.badgeHeight)
                        .clip(SanvyaShape.pill)
                        .background(colors.negative)
                        .padding(horizontal = 5.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    SanvyaText(
                        if (badge > 9) "9+" else "$badge",
                        style = SanvyaType.navLabel,
                        color = Color.White,
                    )
                }
            }
        }
    }
}
