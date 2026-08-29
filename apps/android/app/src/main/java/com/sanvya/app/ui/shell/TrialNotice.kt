package com.sanvya.app.ui.shell

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaShape
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.SanvyaButton
import com.sanvya.app.ui.components.SanvyaModal
import com.sanvya.app.ui.components.SanvyaText

/**
 * Trial onboarding -- a port of `apps/web/src/ui/TrialNotice.tsx`.
 *
 * Two things, and they are two because they answer different questions:
 *
 *  * a **persistent banner** counting the trial down, so nobody is surprised on
 *    day fifteen by features quietly disappearing, and
 *  * a **one-time welcome dialog** right after registration, which says what is
 *    unlocked and, more usefully, what is NOT free afterwards.
 *
 * Only for registered users actually on the trial: not guests (they have their
 * own three-day countdown on the bottom bar) and not paid subscribers. That gate
 * is web's `session && !session.isGuest && e.isTrial`, and it is why the caller
 * passes all three in rather than this composable guessing from one of them.
 *
 * **The features listed are hardcoded on web as an array of English strings.**
 * They are four i18n keys here, and they are a LIST rather than one sentence for
 * the same reason web made them one: "you will lose Ask Sanvya, Insights,
 * Statements and more" scans as marketing, four bullets scan as an inventory.
 *
 * Mirrors apps/ios/App/Shell/TrialNotice.swift.
 */
@Composable
fun TrialNotice(
    onTrial: Boolean,
    daysLeft: Int,
    email: String?,
    onSeePlans: () -> Unit,
) {
    // Observed so `markSeen` closes the dialog: the flag lives in
    // SharedPreferences, which is not itself a snapshot state object.
    val revision by TrialPrefs.revision.collectAsState()
    val res = sRes()
    val colors = LocalSanvyaColors.current

    // Local, and deliberately NOT derived from `TrialPrefs.seen` alone: web
    // opens the dialog once per mount and keeps it open until dismissed, so a
    // preference write that happened in another process must not yank it away
    // mid-read.
    var welcomeOpen by remember(onTrial, email, revision) {
        mutableStateOf(onTrial && email != null && !TrialPrefs.seen(email))
    }

    if (!onTrial) return

    val dayLabel = S.Dashboard.trialDays(res, daysLeft)

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 16.dp)
            .clip(SanvyaShape.row)
            .background(colors.accentGhost)
            .border(1.dp, colors.accentSoft, SanvyaShape.row)
            .padding(horizontal = 14.dp, vertical = 9.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(SanvyaShape.pill)
                .background(colors.accent),
        )
        Column(modifier = Modifier.weight(1f)) {
            SanvyaText(
                text = S.Dashboard.trialBannerTitle(res, dayLabel),
                style = SanvyaType.statLabel,
                color = colors.text,
            )
            SanvyaText(
                text = S.Dashboard.trialBannerBody(res),
                style = SanvyaType.statLabel,
                color = colors.text2,
            )
        }
        SanvyaButton(onClick = onSeePlans) {
            SanvyaText(S.Dashboard.trialUpgrade(res), style = SanvyaType.button, color = colors.surface)
        }
    }

    SanvyaModal(
        open = welcomeOpen,
        onClose = {
            TrialPrefs.markSeen(email)
            welcomeOpen = false
        },
        label = S.Dashboard.trialWelcomeTitle(res),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            SanvyaText(
                text = S.Dashboard.trialWelcomeTitle(res),
                style = SanvyaType.h2,
                color = colors.text,
            )
            SanvyaText(
                text = S.Dashboard.trialWelcomeSubtitle(res, dayLabel),
                style = SanvyaType.statLabel,
                color = colors.text2,
            )
            SanvyaText(
                text = S.Dashboard.trialWelcomeIntro(res),
                style = SanvyaType.body,
                color = colors.text,
            )
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf(
                    S.Dashboard.trialLoseAssistant(res),
                    S.Dashboard.trialLoseInsights(res),
                    S.Dashboard.trialLoseAutomation(res),
                    S.Dashboard.trialLoseCsv(res),
                ).forEach { feature ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        // Web draws a "✦" glyph in `--accent`. A small filled
                        // dot says the same thing without shipping a decorative
                        // character that no font here is guaranteed to have.
                        Box(
                            modifier = Modifier
                                .padding(top = 6.dp)
                                .size(6.dp)
                                .clip(SanvyaShape.pill)
                                .background(colors.accent),
                        )
                        SanvyaText(text = feature, style = SanvyaType.statLabel, color = colors.text)
                    }
                }
            }
            SanvyaText(
                text = S.Dashboard.trialWelcomeFooter(res, dayLabel),
                style = SanvyaType.statLabel,
                color = colors.text2,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
            ) {
                SanvyaButton(
                    onClick = {
                        TrialPrefs.markSeen(email)
                        welcomeOpen = false
                    },
                    ghost = true,
                ) {
                    SanvyaText(S.Dashboard.trialLater(res), style = SanvyaType.button, color = colors.text)
                }
                SanvyaButton(
                    onClick = {
                        TrialPrefs.markSeen(email)
                        welcomeOpen = false
                        onSeePlans()
                    },
                ) {
                    SanvyaText(S.Dashboard.trialSeePlans(res), style = SanvyaType.button, color = colors.surface)
                }
            }
        }
    }
}
