package com.sanvya.app.ui.feedback

import android.content.res.Resources
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Checkbox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.domain.feedback.FEEDBACK_AREAS
import com.sanvya.app.domain.feedback.FEEDBACK_SEVERITIES
import com.sanvya.app.domain.feedback.feedbackAreaKey
import com.sanvya.app.domain.feedback.feedbackSeverityKey
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.Muted
import com.sanvya.app.ui.components.SanvyaButton
import com.sanvya.app.ui.components.SanvyaChip
import com.sanvya.app.ui.components.SanvyaInput
import com.sanvya.app.ui.components.SanvyaModal
import com.sanvya.app.ui.components.SanvyaText

/**
 * Send feedback -- ported from `apps/web/src/ui/BugReport.tsx`.
 *
 * The "Feedback" entry in the More sheet and the side nav was wired to a
 * closure that closed the sheet and did nothing else, on BOTH platforms: a
 * visible control that lied, and the app's only error-report channel.
 *
 * Two things are deliberately not web's:
 *
 *  * **Every string is translated.** Web's modal is hardcoded English end to
 *    end -- 30-odd strings, in an app that ships in three languages. The
 *    catalogue entries added for this port are there for web to adopt.
 *  * **The area picker is a chip grid, not a `<select>`.** Fourteen options in
 *    a native dropdown is a scroll wheel on Android and a wheel-picker sheet on
 *    iOS; chips show the whole vocabulary at once, which is what the web
 *    `<select>` effectively does on a desktop.
 *
 * What IS web's, exactly: the default-on log checkbox, the promise about what
 * is captured, the bug/suggestion split (and with it the severity row, which a
 * suggestion does not get), and the thank-you screen including the beta-tester
 * reward copy.
 *
 * Mirrors iOS's FeedbackSheet.
 */
@Composable
fun FeedbackSheet(
    open: Boolean,
    route: String,
    online: Boolean,
    onClose: () -> Unit,
    viewModel: FeedbackViewModel = viewModel(),
) {
    if (!open) return
    val res = sRes()
    val state by viewModel.state.collectAsState()
    val configuration = LocalConfiguration.current
    val viewport = "${configuration.screenWidthDp}x${configuration.screenHeightDp}"
    val userAgent = remember {
        "Android ${android.os.Build.VERSION.RELEASE}; ${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}"
    }

    SanvyaModal(
        open = true,
        onClose = { onClose(); viewModel.reset() },
        label = S.Feedback.title(res),
    ) {
        if (state.done) {
            DonePanel(
                res = res,
                isBug = state.isBug,
                onAnother = { viewModel.reset() },
                onDone = { onClose(); viewModel.reset() },
            )
            return@SanvyaModal
        }

        Column(
            modifier = Modifier.heightIn(max = (configuration.screenHeightDp * 0.7f).dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SanvyaText(S.Feedback.title(res), SanvyaType.h2)
            Muted(S.Feedback.intro(res), style = SanvyaType.body.copy(fontSize = 12.sp))

            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                SanvyaChip(
                    S.Feedback.kindBug(res),
                    active = state.isBug,
                    onClick = { viewModel.setKind("bug") },
                    modifier = Modifier.weight(1f),
                )
                SanvyaChip(
                    S.Feedback.kindSuggestion(res),
                    active = !state.isBug,
                    onClick = { viewModel.setKind("suggestion") },
                    modifier = Modifier.weight(1f),
                )
            }

            // A suggestion has no severity -- web hides the whole row, and the
            // repository writes null, so the triage queue is not sorted by an
            // urgency nobody chose.
            if (state.isBug) {
                Muted(S.Feedback.severityLabel(res), style = SanvyaType.body.copy(fontSize = 12.sp))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    FEEDBACK_SEVERITIES.forEach { severity ->
                        SanvyaChip(
                            feedbackLabel(res, feedbackSeverityKey(severity)),
                            active = state.severity == severity,
                            onClick = { viewModel.setSeverity(severity) },
                        )
                    }
                }
            }

            Muted(S.Feedback.areaLabel(res), style = SanvyaType.body.copy(fontSize = 12.sp))
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                FEEDBACK_AREAS.forEach { area ->
                    SanvyaChip(
                        feedbackLabel(res, feedbackAreaKey(area)),
                        active = state.area == area,
                        // Tapping the chosen one again clears it: web's select
                        // has an empty first option and this has no equivalent
                        // row to offer.
                        onClick = { viewModel.setArea(if (state.area == area) "" else area) },
                    )
                }
            }

            SanvyaInput(
                value = state.title,
                onValueChange = viewModel::setTitle,
                placeholder = S.Feedback.titlePlaceholder(res),
            )
            SanvyaInput(
                value = state.description,
                onValueChange = viewModel::setDescription,
                placeholder = if (state.isBug) {
                    S.Feedback.bugPlaceholder(res)
                } else {
                    S.Feedback.suggestionPlaceholder(res)
                },
                singleLine = false,
                modifier = Modifier.heightIn(min = 96.dp),
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Checkbox(checked = state.includeLog, onCheckedChange = viewModel::setIncludeLog)
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    SanvyaText(S.Feedback.includeLog(res), SanvyaType.body.copy(fontSize = 13.sp))
                    Muted(S.Feedback.includeLogHint(res), style = SanvyaType.body.copy(fontSize = 11.sp))
                }
            }

            Muted(S.Feedback.autoIncluded(res), style = SanvyaType.body.copy(fontSize = 11.sp))

            state.errorKey?.let {
                SanvyaText(
                    feedbackLabel(res, it),
                    SanvyaType.body.copy(fontSize = 13.sp),
                    color = LocalSanvyaColors.current.negative,
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
            ) {
                SanvyaButton(onClick = { onClose(); viewModel.reset() }, ghost = true) {
                    SanvyaText(S.Feedback.cancel(res), SanvyaType.button)
                }
                SanvyaButton(
                    onClick = {
                        viewModel.submit(
                            route = route,
                            platform = "Android",
                            userAgent = userAgent,
                            viewport = viewport,
                            online = online,
                        )
                    },
                    enabled = state.canSubmit,
                ) {
                    SanvyaText(
                        when {
                            state.busy -> S.Feedback.sending(res)
                            state.isBug -> S.Feedback.sendBug(res)
                            else -> S.Feedback.sendSuggestion(res)
                        },
                        SanvyaType.button,
                        color = Color.White,
                    )
                }
            }
        }
    }
}

/** Web's post-submit panel, reward copy and all. */
@Composable
private fun DonePanel(res: Resources, isBug: Boolean, onAnother: () -> Unit, onDone: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        SanvyaText("🙏", SanvyaType.h2.copy(fontSize = 34.sp))
        SanvyaText(
            if (isBug) S.Feedback.thanksBug(res) else S.Feedback.thanksSuggestion(res),
            SanvyaType.h2,
        )
        Muted(
            if (isBug) S.Feedback.thanksBugBody(res) else S.Feedback.thanksSuggestionBody(res),
            style = SanvyaType.body.copy(fontSize = 14.sp),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SanvyaButton(onClick = onAnother, ghost = true) {
                SanvyaText(S.Feedback.sendAnother(res), SanvyaType.button)
            }
            SanvyaButton(onClick = onDone) {
                SanvyaText(S.Feedback.done(res), SanvyaType.button, color = Color.White)
            }
        }
    }
}

/**
 * A `feedback` namespace key, resolved.
 *
 * The generated `feedbackAreaKey` / `feedbackSeverityKey` return a key rather
 * than a string, for the same reason `assistantErrorKey` does: the derivation
 * is shared and vector-pinned, the wording is per-locale. This is the one place
 * that turns one into the other, and it is exhaustive on purpose -- a new area
 * in web's list fails here rather than rendering its own key on screen.
 */
private fun feedbackLabel(res: Resources, key: String): String = when (key) {
    "sevFatal" -> S.Feedback.sevFatal(res)
    "sevHigh" -> S.Feedback.sevHigh(res)
    "sevMedium" -> S.Feedback.sevMedium(res)
    "sevLow" -> S.Feedback.sevLow(res)
    "areaDashboard" -> S.Feedback.areaDashboard(res)
    "areaTransactions" -> S.Feedback.areaTransactions(res)
    "areaAccountsCards" -> S.Feedback.areaAccountsCards(res)
    "areaBudgets" -> S.Feedback.areaBudgets(res)
    "areaGoals" -> S.Feedback.areaGoals(res)
    "areaInvestments" -> S.Feedback.areaInvestments(res)
    "areaFriendsSplits" -> S.Feedback.areaFriendsSplits(res)
    "areaSubscriptions" -> S.Feedback.areaSubscriptions(res)
    "areaLoans" -> S.Feedback.areaLoans(res)
    "areaAskSanvya" -> S.Feedback.areaAskSanvya(res)
    "areaInsights" -> S.Feedback.areaInsights(res)
    "areaSettingsBilling" -> S.Feedback.areaSettingsBilling(res)
    "areaSyncOffline" -> S.Feedback.areaSyncOffline(res)
    "areaOther" -> S.Feedback.areaOther(res)
    "errNeedBug" -> S.Feedback.errNeedBug(res)
    "errNeedSuggestion" -> S.Feedback.errNeedSuggestion(res)
    else -> S.Feedback.errSubmit(res)
}
