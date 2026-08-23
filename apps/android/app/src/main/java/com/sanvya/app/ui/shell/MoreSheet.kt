package com.sanvya.app.ui.shell

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.dp
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaIcons
import com.sanvya.app.theme.SanvyaShape
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.SanvyaButton
import com.sanvya.app.ui.components.SanvyaIcon
import com.sanvya.app.ui.components.SanvyaModal
import com.sanvya.app.ui.components.SanvyaText
import com.sanvya.app.ui.components.press

/**
 * One nav group, matching web's NAV_GROUPS.
 *
 * Internal, not private: the More sheet and the expanded-layout sidebar render
 * the **same** list. They have to. At >= 840dp the More sheet is unreachable, so
 * anything that lived only there would simply vanish on a tablet.
 */
internal data class NavGroup(val title: String, val items: List<NavEntry>)
internal data class NavEntry(val route: String, val label: String, val glyph: String)

/**
 * Web's `NAV_GROUPS`, verbatim.
 *
 * The Money group has one "Shared & owed" entry, not two: `/groups` now
 * redirects to `/friends`, because Groups and Splits were one screen's worth of
 * information split across two.
 */
internal val NAV_GROUPS = listOf(
    NavGroup(
        "Money",
        listOf(
            NavEntry("accounts", "Accounts", SanvyaIcons.accountBalance),
            NavEntry("transactions", "Transactions", SanvyaIcons.swapHoriz),
            NavEntry("cards", "Cards", SanvyaIcons.creditCard),
            NavEntry("splits", "Shared & owed", SanvyaIcons.groups),
            NavEntry("search", "Search", SanvyaIcons.search),
        ),
    ),
    NavGroup(
        "Planning",
        listOf(
            NavEntry("budgets", "Budgets", SanvyaIcons.donutSmall),
            NavEntry("goals", "Goals", SanvyaIcons.flag),
            NavEntry("recurring", "Recurring", SanvyaIcons.autorenew),
            NavEntry("loans", "Loans", SanvyaIcons.requestQuote),
        ),
    ),
    NavGroup(
        "Growth",
        listOf(
            NavEntry("investments", "Investments", SanvyaIcons.trendingUp),
            NavEntry("reflect", "Reflect", SanvyaIcons.volunteerActivism),
            NavEntry("insights", "Insights", SanvyaIcons.insights),
            NavEntry("statements", "Statements", SanvyaIcons.description),
        ),
    ),
    NavGroup(
        "",
        listOf(
            NavEntry("assistant", "Ask Sanvya", SanvyaIcons.autoAwesome),
            NavEntry("settings", "Settings", SanvyaIcons.settings),
            NavEntry("help", "Help & FAQ", SanvyaIcons.help),
        ),
    ),
)

/**
 * Every destination that is not in the bottom bar.
 *
 * Web's footer also offers "Install app"; that is a PWA affordance and is
 * deliberately not ported — this app is already installed.
 */
@Composable
fun MoreSheet(
    open: Boolean,
    currentRoute: String?,
    unreadCount: Int,
    isGuest: Boolean,
    guestDaysLeft: Int?,
    onNavigate: (String) -> Unit,
    onCustomize: () -> Unit,
    onFeedback: () -> Unit,
    onClose: () -> Unit,
    appVersion: String,
) {
    val colors = LocalSanvyaColors.current
    SanvyaModal(open = open, onClose = onClose, label = "More") {
        Row(
            modifier = Modifier.fillMaxWidth().padding(bottom = 14.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SanvyaText("Sanvya", SanvyaType.h2)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                RoundIconButton(SanvyaIcons.edit, "Customize bottom bar", onCustomize)
                RoundIconButton(SanvyaIcons.close, "Close", onClose)
            }
        }

        Column(
            modifier = Modifier
                .heightIn(max = (LocalConfiguration.current.screenHeightDp * 0.6f).dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            MoreNavItem(
                glyph = SanvyaIcons.notifications,
                label = "Notifications",
                active = currentRoute?.startsWith("notifications") == true,
                badge = unreadCount,
                onClick = { onNavigate("notifications") },
            )
            NAV_GROUPS.forEach { group ->
                Column(
                    modifier = Modifier.padding(top = 10.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    if (group.title.isNotEmpty()) {
                        SanvyaText(
                            text = group.title.uppercase(),
                            style = SanvyaType.sectionTitle,
                            color = colors.text2,
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 2.dp),
                        )
                    }
                    group.items.forEach { entry ->
                        MoreNavItem(
                            glyph = entry.glyph,
                            label = entry.label,
                            active = currentRoute?.startsWith(entry.route) == true,
                            onClick = { onNavigate(entry.route) },
                        )
                    }
                }
            }
        }

        Column(
            modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (isGuest) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(SanvyaShape.row)
                        .background(colors.accentGhost)
                        .border(1.dp, colors.accentSoft, SanvyaShape.row)
                        .clickable { onNavigate("login") }
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                ) {
                    SanvyaText(
                        text = if (guestDaysLeft != null) {
                            "Guest · $guestDaysLeft days until data is deleted"
                        } else {
                            "Guest"
                        },
                        style = SanvyaType.statLabel,
                    )
                    SanvyaText("Create account →", SanvyaType.statLabel, color = colors.accent)
                }
            }
            SanvyaButton(onClick = onFeedback, ghost = true, modifier = Modifier.fillMaxWidth()) {
                SanvyaIcon(SanvyaIcons.chatBubble, size = 16.dp, tint = colors.text)
                SanvyaText("Feedback", SanvyaType.button, color = colors.text)
            }
            SanvyaText(
                text = "Sanvya v$appVersion",
                style = SanvyaType.navLabel,
                color = colors.text2,
                modifier = Modifier.fillMaxWidth().padding(top = 2.dp),
            )
        }
    }
}

@Composable
private fun RoundIconButton(glyph: String, description: String, onClick: () -> Unit) {
    val colors = LocalSanvyaColors.current
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier = Modifier
            .size(34.dp)
            .press(interaction)
            .clip(SanvyaShape.pill)
            .background(colors.surface2)
            .border(1.dp, colors.border, SanvyaShape.pill)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        SanvyaIcon(glyph, size = 15.dp, tint = colors.text, description = description)
    }
}

@Composable
private fun MoreNavItem(
    glyph: String,
    label: String,
    active: Boolean,
    onClick: () -> Unit,
    badge: Int = 0,
) {
    val colors = LocalSanvyaColors.current
    val interaction = remember { MutableInteractionSource() }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .press(interaction)
            .clip(SanvyaShape.row)
            .background(if (active) colors.accentGhost else Color.Transparent)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SanvyaIcon(glyph, size = 20.dp, tint = if (active) colors.accent else colors.text)
        SanvyaText(
            text = label,
            style = SanvyaType.body,
            color = if (active) colors.accent else colors.text,
            modifier = Modifier.weight(1f),
        )
        if (badge > 0) {
            Box(
                modifier = Modifier
                    .widthIn(min = 18.dp)
                    .height(18.dp)
                    .clip(SanvyaShape.pill)
                    .background(colors.negative)
                    .padding(horizontal = 5.dp),
                contentAlignment = Alignment.Center,
            ) {
                SanvyaText(
                    text = if (badge > 9) "9+" else badge.toString(),
                    style = SanvyaType.navLabel,
                    color = Color.White,
                )
            }
        }
    }
}

/**
 * Pick which four destinations sit in the bar.
 *
 * When four are chosen the rest go **disabled**, not silently evicting whoever
 * was picked first — web ignores the extra tap rather than bumping someone, and
 * Save stays disabled until exactly four are selected.
 */
@Composable
fun BottomNavCustomizer(
    open: Boolean,
    current: List<String>,
    onSave: (List<String>) -> Unit,
    onClose: () -> Unit,
) {
    val colors = LocalSanvyaColors.current
    var picked by rememberSaveable(open, current) { mutableStateOf(current) }

    SanvyaModal(open = open, onClose = onClose, label = "Customize bottom bar") {
        SanvyaText("Customize bottom bar", SanvyaType.h2, modifier = Modifier.padding(bottom = 4.dp))
        SanvyaText(
            text = "Pick ${NavPrefs.SLOTS} to keep one tap away. Home and More always stay put.",
            style = SanvyaType.statLabel,
            color = colors.text2,
            modifier = Modifier.padding(bottom = 14.dp),
        )

        Column(
            modifier = Modifier
                .heightIn(max = (LocalConfiguration.current.screenHeightDp * 0.5f).dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            NavPrefs.CATALOG.forEach { item ->
                val active = item.id in picked
                val disabled = !active && picked.size >= NavPrefs.SLOTS
                val interaction = remember { MutableInteractionSource() }
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(SanvyaShape.row)
                        .background(if (active) colors.accentGhost else Color.Transparent)
                        .clickable(
                            interactionSource = interaction,
                            indication = null,
                            enabled = !disabled,
                        ) {
                            picked = if (active) picked - item.id else picked + item.id
                        }
                        .padding(horizontal = 12.dp, vertical = 10.dp)
                        .alpha(if (disabled) 0.55f else 1f),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    SanvyaIcon(
                        glyph = item.glyph,
                        size = 20.dp,
                        tint = if (disabled) colors.text3 else colors.text,
                    )
                    SanvyaText(
                        text = item.label,
                        style = SanvyaType.body,
                        color = if (disabled) colors.text3 else colors.text,
                        modifier = Modifier.weight(1f),
                    )
                    Box(
                        modifier = Modifier
                            .size(20.dp)
                            .clip(SanvyaShape.pill)
                            .background(if (active) colors.accent else Color.Transparent)
                            .border(
                                width = 1.5.dp,
                                color = if (active) colors.accent else colors.borderStrong,
                                shape = SanvyaShape.pill,
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (active) SanvyaIcon(SanvyaIcons.check, size = 13.dp, tint = Color.White)
                    }
                }
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
        ) {
            SanvyaButton(onClick = onClose, ghost = true) {
                SanvyaText("Cancel", SanvyaType.button, color = colors.text)
            }
            SanvyaButton(
                onClick = { onSave(picked) },
                enabled = picked.size == NavPrefs.SLOTS,
            ) {
                SanvyaText("Save", SanvyaType.button, color = Color.White)
            }
        }
    }
}
