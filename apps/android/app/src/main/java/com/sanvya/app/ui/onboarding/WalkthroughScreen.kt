package com.sanvya.app.ui.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.domain.onboarding.walkthroughProgress
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaIcons
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.FormOptions
import com.sanvya.app.ui.components.SanvyaButton
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaIcon
import com.sanvya.app.ui.components.SanvyaInput
import com.sanvya.app.ui.components.SanvyaModal
import com.sanvya.app.ui.components.SanvyaText

/**
 * First-run walkthrough — ported from apps/web/src/onboarding/Walkthrough.tsx.
 *
 * Written for a specific person: a 60+ user who signed up, landed on the
 * dashboard, did not know what to do, and believed "add an account" meant
 * linking their real bank. They stopped there. Three rules follow, and every
 * step obeys them:
 *
 * 1. **Say what the app IS, first** — not what to tap. "It is not connected to
 *    your bank" is the single most important sentence in this file.
 * 2. **Manual entry is the product, not an apology.**
 * 3. **Do not send them to the real form.** The new-account screen offers
 *    Savings / Current / Credit card / Demat, which reads as bank onboarding.
 *    Step 2 asks for a name and a number and defaults the rest.
 *
 * Part A (1–4) is setup and ends in a real Finish. Part B (5–7) is opt-in:
 * making onboarding LONGER would be the wrong answer to "I found this
 * overwhelming".
 *
 * Presented in [SanvyaModal] — the port of web's `Modal`, which is what web
 * uses here — so this composable is the panel only: no scaffold, no scroll, no
 * background of its own.
 *
 * Mirrors iOS's WalkthroughView.swift step for step.
 */
@Composable
fun WalkthroughScreen(
    onFinish: () -> Unit,
    onSkip: () -> Unit,
    onNavigateToLogin: () -> Unit,
    onNavigateToPlans: () -> Unit,
    viewModel: WalkthroughViewModel = viewModel(),
) {
    val res = sRes()
    val colors = LocalSanvyaColors.current
    val step by viewModel.step.collectAsState()
    val busy by viewModel.busy.collectAsState()
    val error by viewModel.error.collectAsState()
    val isGuest by viewModel.isGuest.collectAsState()
    val onTrial by viewModel.onTrial.collectAsState()

    val progress = walkthroughProgress(step)
    val stepIcon = when (step) {
        1 -> SanvyaIcons.volunteerActivism
        2 -> SanvyaIcons.accountBalance
        3 -> SanvyaIcons.receiptLong
        4 -> SanvyaIcons.check
        5 -> SanvyaIcons.insights
        6 -> SanvyaIcons.autoAwesome
        else -> if (isGuest) SanvyaIcons.person else SanvyaIcons.redeem
    }

    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(42.dp)
                    .background(colors.accentGhost, RoundedCornerShape(12.dp)),
                contentAlignment = Alignment.Center,
            ) {
                SanvyaIcon(stepIcon, size = 24.dp, tint = colors.accent)
            }
            Spacer(Modifier.weight(1f))
            SanvyaText(
                S.Onboarding.wtProgress(res, progress.step, progress.of),
                SanvyaType.statLabel.copy(fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold),
                color = colors.text2,
            )
        }

        when (step) {
            1 -> Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Title(S.Onboarding.wtIntroTitle(res))
                Body(S.Onboarding.wtIntroP1(res))
                Body(S.Onboarding.wtIntroP2(res), strong = true)
                Body(S.Onboarding.wtIntroP3(res))
                Body(S.Onboarding.wtIntroP4(res))
                Actions(
                    primary = S.Onboarding.wtIntroCta(res), onPrimary = { viewModel.setStep(2) },
                    secondary = S.Onboarding.wtSkip(res), onSecondary = onSkip,
                )
            }

            2 -> {
                val name by viewModel.accountName.collectAsState()
                val balance by viewModel.accountBalance.collectAsState()
                val canSave by viewModel.canSaveAccount.collectAsState()
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Title(S.Onboarding.wtAccTitle(res))
                    Body(S.Onboarding.wtAccP1(res))
                    Body(S.Onboarding.wtAccP2(res))
                    Field(S.Onboarding.wtAccNameLabel(res)) {
                        SanvyaInput(
                            value = name,
                            onValueChange = viewModel::setAccountName,
                            placeholder = "${S.Onboarding.wtAccEg1(res)} · ${S.Onboarding.wtAccEg2(res)}",
                        )
                    }
                    Field(S.Onboarding.wtAccBalLabel(res)) {
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            SanvyaInput(
                                value = balance,
                                onValueChange = viewModel::setAccountBalance,
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                            )
                            SanvyaText(S.Onboarding.wtAccBalHelp(res), SanvyaType.statLabel, color = colors.text2)
                        }
                    }
                    ErrorLine(error)
                    Actions(
                        primary = if (busy) S.Onboarding.wtSaving(res) else S.Onboarding.wtAccCta(res),
                        onPrimary = viewModel::saveAccount,
                        enabled = !busy && canSave,
                        secondary = S.Onboarding.wtLater(res), onSecondary = { viewModel.setStep(3) },
                    )
                }
            }

            3 -> {
                val what by viewModel.spendWhat.collectAsState()
                val amount by viewModel.spendAmount.collectAsState()
                val canSave by viewModel.canSaveSpend.collectAsState()
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Title(S.Onboarding.wtSpendTitle(res))
                    Body(S.Onboarding.wtSpendP1(res))
                    Body(S.Onboarding.wtSpendP2(res))
                    Body(S.Onboarding.wtSpendP3(res), strong = true)
                    Field(S.Onboarding.wtSpendWhatLabel(res)) {
                        SanvyaInput(
                            value = what,
                            onValueChange = viewModel::setSpendWhat,
                            placeholder = S.Onboarding.wtSpendWhatEg(res),
                        )
                    }
                    Field(S.Onboarding.wtSpendAmountLabel(res)) {
                        SanvyaInput(
                            value = amount,
                            onValueChange = viewModel::setSpendAmount,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        )
                    }
                    ErrorLine(error)
                    Actions(
                        primary = if (busy) S.Onboarding.wtSaving(res) else S.Onboarding.wtSpendCta(res),
                        onPrimary = viewModel::saveSpend,
                        enabled = !busy && canSave,
                        secondary = S.Onboarding.wtLater(res), onSecondary = { viewModel.setStep(4) },
                    )
                }
            }

            4 -> Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Title(S.Onboarding.wtDoneTitle(res))
                Where(SanvyaIcons.spaceDashboard, S.Onboarding.wtDoneDashTitle(res), S.Onboarding.wtDoneDashBody(res))
                Where(SanvyaIcons.swapHoriz, S.Onboarding.wtDoneTxnTitle(res), S.Onboarding.wtDoneTxnBody(res))
                Where(SanvyaIcons.donutSmall, S.Onboarding.wtDoneBudgetTitle(res), S.Onboarding.wtDoneBudgetBody(res))
                SanvyaText(
                    S.Onboarding.wtDonePrivacy(res),
                    SanvyaType.body.copy(fontSize = 13.5.sp),
                    color = colors.text2,
                )
                Actions(
                    primary = S.Onboarding.wtDoneCta(res), onPrimary = onFinish,
                    secondary = S.Onboarding.wtDoneMore(res), onSecondary = { viewModel.setStep(5) },
                )
            }

            5 -> Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Title(S.Onboarding.wtInsightsTitle(res))
                Body(S.Onboarding.wtInsightsP1(res))
                SanvyaCard(padding = PaddingValues(12.dp), background = colors.surface2) {
                    SanvyaText(
                        S.Onboarding.wtInsightsEg(res),
                        SanvyaType.body.copy(fontSize = 14.sp, fontStyle = FontStyle.Italic),
                    )
                }
                Body(S.Onboarding.wtInsightsP2(res))
                Actions(
                    primary = S.Onboarding.wtNext(res), onPrimary = { viewModel.setStep(6) },
                    secondary = S.Onboarding.wtDoneCta(res), onSecondary = onFinish,
                )
            }

            6 -> Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Title(S.Onboarding.wtAskTitle(res))
                Body(S.Onboarding.wtAskP1(res))
                Body(S.Onboarding.wtAskP2(res))
                SanvyaText(
                    S.Onboarding.wtAskPrivacy(res),
                    SanvyaType.body.copy(fontSize = 13.5.sp),
                    color = colors.text2,
                )
                Actions(
                    primary = S.Onboarding.wtNext(res), onPrimary = { viewModel.setStep(7) },
                    secondary = S.Onboarding.wtDoneCta(res), onSecondary = onFinish,
                )
            }

            else -> if (isGuest) {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Title(S.Onboarding.wtGuestTitle(res))
                    Body(S.Onboarding.wtGuestP1(res))
                    Actions(
                        primary = S.Onboarding.wtGuestCta(res),
                        onPrimary = { onFinish(); onNavigateToLogin() },
                        secondary = S.Onboarding.wtGuestLater(res), onSecondary = onFinish,
                    )
                }
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Title(if (onTrial) S.Onboarding.wtPlanTitleTrial(res) else S.Onboarding.wtPlanTitle(res))
                    if (onTrial) Body(S.Onboarding.wtPlanTrial(res))
                    Body(S.Onboarding.wtPlanFree(res))
                    FormOptions.plans.forEach { plan ->
                        // surface-2, not surface: this card sits INSIDE the
                        // modal's own card, and two identical fills separated by
                        // a hairline read as one block. Web overrides the same
                        // token here.
                        SanvyaCard(padding = PaddingValues(14.dp), background = colors.surface2) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.Bottom,
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                SanvyaText(plan.label, SanvyaType.body.copy(fontSize = 16.sp, fontWeight = FontWeight.Bold))
                                Spacer(Modifier.weight(1f))
                                SanvyaText(
                                    S.Onboarding.wtPlanPerMonth(res, plan.monthly),
                                    SanvyaType.body.copy(fontSize = 15.sp, fontWeight = FontWeight.Bold),
                                )
                            }
                            Spacer(Modifier.size(4.dp))
                            SanvyaText(
                                S.Onboarding.wtPlanQuota(res, plan.quota),
                                SanvyaType.body.copy(fontSize = 13.5.sp),
                                color = colors.text2,
                            )
                        }
                    }
                    Actions(
                        primary = S.Onboarding.wtPlanCta(res), onPrimary = onFinish,
                        secondary = S.Onboarding.wtPlanSee(res),
                        onSecondary = { onFinish(); onNavigateToPlans() },
                    )
                }
            }
        }
    }
}

/**
 * Body copy is 15sp, not the app's 12.5–13sp muted default. Web's plan says
 * why: this is the one screen written for someone who finds the rest small.
 */
@Composable
private fun Body(text: String, strong: Boolean = false) = SanvyaText(
    text,
    SanvyaType.body.copy(fontSize = 15.sp, fontWeight = if (strong) FontWeight.Bold else FontWeight.Normal),
    modifier = Modifier.fillMaxWidth(),
)

@Composable
private fun Title(text: String) = SanvyaText(
    text,
    SanvyaType.h2.copy(fontSize = 21.sp, fontWeight = FontWeight.SemiBold),
    modifier = Modifier.fillMaxWidth(),
)

@Composable
private fun Field(label: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        SanvyaText(label, SanvyaType.body.copy(fontSize = 14.sp, fontWeight = FontWeight.SemiBold))
        content()
    }
}

@Composable
private fun ErrorLine(error: String?) {
    if (error == null) return
    SanvyaText(error, SanvyaType.body.copy(fontSize = 15.sp), color = LocalSanvyaColors.current.negative)
}

/**
 * Stacked, full-width actions — easier to hit, and the primary one is obvious.
 * Web makes the same choice for the same reason.
 */
@Composable
private fun Actions(
    primary: String,
    onPrimary: () -> Unit,
    enabled: Boolean = true,
    secondary: String? = null,
    onSecondary: (() -> Unit)? = null,
) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        SanvyaButton(onClick = onPrimary, modifier = Modifier.fillMaxWidth(), enabled = enabled) {
            // `weight(1f)` + a centred style, because SanvyaButton lays its
            // content out in a Row and a full-width button with left-aligned
            // text reads as a list item.
            SanvyaText(
                primary,
                SanvyaType.button.copy(textAlign = TextAlign.Center),
                color = Color.White,
                modifier = Modifier.weight(1f),
            )
        }
        if (secondary != null && onSecondary != null) {
            TextButton(onClick = onSecondary, modifier = Modifier.fillMaxWidth()) {
                SanvyaText(secondary, SanvyaType.body.copy(fontSize = 14.sp), color = LocalSanvyaColors.current.text2)
            }
        }
    }
}

/** "Where to look" row. */
@Composable
private fun Where(glyph: String, heading: String, text: String) {
    val colors = LocalSanvyaColors.current
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
        SanvyaIcon(glyph, size = 20.dp, tint = colors.accent, modifier = Modifier.padding(top = 1.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            SanvyaText(heading, SanvyaType.body.copy(fontSize = 15.sp, fontWeight = FontWeight.SemiBold))
            SanvyaText(text, SanvyaType.body.copy(fontSize = 13.5.sp), color = colors.text2)
        }
    }
}

/**
 * The walkthrough, gated and presented. Mounted by the dashboard, because that
 * is where web mounts it (`apps/web/app/page.tsx` renders `<Walkthrough />` in
 * both of the dashboard's branches) — and it is the right place: the dashboard
 * is where a new user actually lands and stalls.
 */
@Composable
fun WalkthroughHost(
    onNavigateToLogin: () -> Unit,
    onNavigateToPlans: () -> Unit,
    gate: WalkthroughGateViewModel = viewModel(),
) {
    val open by gate.isOpen.collectAsState()
    // A scrim tap resolves to skip(), matching web's `onClose={skip}`: a tap
    // outside is "not now", never "done".
    SanvyaModal(open = open, onClose = gate::skip, label = S.Onboarding.wtDialogLabel(sRes())) {
        WalkthroughScreen(
            onFinish = gate::finish,
            onSkip = gate::skip,
            onNavigateToLogin = onNavigateToLogin,
            onNavigateToPlans = onNavigateToPlans,
        )
    }
}
