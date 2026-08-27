package com.sanvya.app.ui.notifications

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.data.repository.NotificationRow
import com.sanvya.app.data.repository.nowIso
import com.sanvya.app.domain.notifications.TimeAgo
import com.sanvya.app.domain.notifications.timeAgo
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaColors
import com.sanvya.app.theme.SanvyaIcons
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaIcon
import com.sanvya.app.ui.components.SanvyaPage
import com.sanvya.app.ui.isoLabel

/**
 * The notification inbox -- ported from apps/web/app/notifications/page.tsx.
 *
 * The row's deep link is web's `n.href` -- a web path like `/budgets` -- handed
 * to [onOpenHref], which resolves it through Domain's `parseAppLink`. A row
 * whose href resolves to nothing is still tappable and still marks itself read;
 * it simply does not move, which is what a dead link on web does too.
 */
@Composable
fun NotificationsScreen(
    onOpenSettings: (() -> Unit)? = null,
    onOpenHref: (String) -> Unit = {},
    viewModel: NotificationsViewModel = viewModel(),
) {
    val items by viewModel.items.collectAsState()
    val unread by viewModel.unread.collectAsState()
    val colors = LocalSanvyaColors.current

    SanvyaPage(
        title = S.Notifications.title(sRes()),
        modifier = Modifier.verticalScroll(rememberScrollState()),
    ) {
        if (unread > 0 || onOpenSettings != null) {
            Row(
                modifier = Modifier.padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (unread > 0) {
                    AssistChip(
                        onClick = viewModel::markAllRead,
                        label = { Text(S.Notifications.markAllRead(sRes()), fontSize = 12.sp) },
                        colors = AssistChipDefaults.assistChipColors(
                            containerColor = colors.surface2,
                            labelColor = colors.text,
                        ),
                    )
                }
                onOpenSettings?.let {
                    AssistChip(
                        onClick = it,
                        label = { Text(S.Notifications.settings(sRes()), fontSize = 12.sp) },
                        colors = AssistChipDefaults.assistChipColors(
                            containerColor = colors.surface2,
                            labelColor = colors.text,
                        ),
                    )
                }
            }
        }

        if (items.isEmpty()) {
            SanvyaCard(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                padding = PaddingValues(40.dp),
            ) {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    SanvyaIcon(SanvyaIcons.notifications, size = 30.dp, tint = colors.text3)
                    Text(
                        S.Notifications.emptyTitle(sRes()),
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 14.sp,
                        color = colors.text,
                    )
                    Text(
                        S.Notifications.emptyBody(sRes()),
                        fontSize = 13.sp,
                        color = colors.text2,
                        textAlign = TextAlign.Center,
                    )
                    onOpenSettings?.let {
                        OutlinedButton(onClick = it, modifier = Modifier.padding(top = 6.dp)) {
                            Text(S.Notifications.enableCta(sRes()))
                        }
                    }
                }
            }
        } else {
            SanvyaCard(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                padding = PaddingValues(0.dp),
            ) {
                items.forEachIndexed { index, item ->
                    if (index > 0) {
                        Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
                    }
                    NotificationRowView(
                        item = item,
                        colors = colors,
                        onOpen = {
                            if (item.readAt == null) viewModel.markRead(item.id)
                            item.href?.takeIf { it.isNotEmpty() }?.let(onOpenHref)
                        },
                        onDismiss = { viewModel.dismiss(item.id) },
                    )
                }
            }
        }
    }
}

@Composable
private fun NotificationRowView(
    item: NotificationRow,
    colors: SanvyaColors,
    onOpen: () -> Unit,
    onDismiss: () -> Unit,
) {
    val isRead = item.readAt != null
    Row(
        modifier = Modifier
            .fillMaxWidth()
            // An unread row is tinted, which is the only thing distinguishing
            // it besides the dot. Web does the same with `--accent-ghost`.
            .background(if (isRead) Color.Transparent else colors.accentGhost)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            Modifier
                .padding(top = 6.dp)
                .size(8.dp)
                .background(
                    if (isRead) colors.borderStrong else severityColor(item.severity, colors),
                    CircleShape,
                ),
        )
        Column(
            modifier = Modifier.weight(1f).clickable(onClick = onOpen),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                item.title,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = colors.text,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            item.body?.takeIf { it.isNotEmpty() }?.let {
                Text(it, fontSize = 12.5.sp, color = colors.text2)
            }
            Text(ageLabel(item.createdAt), fontSize = 11.sp, color = colors.text2)
        }
        Spacer(Modifier.size(4.dp))
        Text(
            "×",
            fontSize = 16.sp,
            color = colors.text2,
            modifier = Modifier.clickable(onClick = onDismiss),
        )
    }
}

/**
 * Web's `SEV_COLOR` map, with its own fallback to accent for a severity nobody
 * has defined a colour for.
 */
private fun severityColor(severity: String?, colors: SanvyaColors): Color = when (severity) {
    "warn" -> colors.warning
    "urgent" -> colors.negative
    else -> colors.accent
}

/**
 * Domain returns the shape; the words and the date format are the view's,
 * because both are locale-dependent and web's version hardcodes English.
 */
@Composable
private fun ageLabel(iso: String?): String {
    if (iso.isNullOrEmpty()) return ""
    return when (val age = timeAgo(iso, nowIso())) {
        is TimeAgo.JustNow -> S.Notifications.justNow(sRes())
        is TimeAgo.Minutes -> S.Notifications.minutesAgo(sRes(), age.value)
        is TimeAgo.Hours -> S.Notifications.hoursAgo(sRes(), age.value)
        is TimeAgo.Days -> S.Notifications.daysAgo(sRes(), age.value)
        is TimeAgo.On -> isoLabel(age.iso, "d MMM y")
    }
}
