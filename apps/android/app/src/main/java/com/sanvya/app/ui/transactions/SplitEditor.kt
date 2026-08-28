package com.sanvya.app.ui.transactions

import android.content.res.Resources
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Switch
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sanvya.app.domain.js.jsRound
import com.sanvya.app.domain.splits.SplitModes
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.Muted
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaChip
import com.sanvya.app.ui.components.SanvyaInput
import com.sanvya.app.ui.components.SanvyaText
import com.sanvya.app.ui.formatMoney

/**
 * The split editor on Add transaction -- ported from the two cards at the foot
 * of `apps/web/app/transactions/new/page.tsx`.
 *
 * **The largest single block of web behaviour that was missing from both
 * ports.** Without it a native user could not record a shared dinner at all,
 * and four other features had nothing to hang off: "paid for someone else",
 * auto-split trips, the `?split=` deep link, and Edit's SplitBanner.
 *
 * The arithmetic is NOT here. `splitPlan` in Domain decides every number and
 * whether Save is allowed, under 35 vectors; this file only draws it and
 * reports the disagreements the user has to resolve.
 *
 * The two cards are mutually exclusive by rendering, exactly as web has it:
 * "paid for someone else" disappears while the split is on, and vice versa. It
 * reads as one decision with two shapes, which is what it is.
 *
 * Mirrors iOS's SplitEditorView.swift.
 */
@Composable
fun SplitEditor(viewModel: CreateTransactionViewModel, currency: String) {
    val res = sRes()
    val state by viewModel.uiState.collectAsState()
    if (state.type != "expense") return

    if (!state.splitOn) {
        ForOtherCard(res = res, viewModel = viewModel, state = state)
    }
    if (!state.forOtherOn) {
        SplitCard(res = res, viewModel = viewModel, state = state, currency = currency)
    }
}

/** Web's "I paid this for someone else" card. */
@Composable
private fun ForOtherCard(
    res: Resources,
    viewModel: CreateTransactionViewModel,
    state: CreateTransactionUiState,
) {
    val connections by viewModel.connections.collectAsState()
    SanvyaCard(modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    SanvyaText(
                        S.Transactions.paidForSomeone(res),
                        SanvyaType.body.copy(fontWeight = FontWeight.SemiBold),
                    )
                    Muted(
                        S.Transactions.paidForSomeoneHint(res),
                        style = SanvyaType.body.copy(fontSize = 12.sp),
                    )
                }
                Switch(checked = state.forOtherOn, onCheckedChange = viewModel::setForOtherOn)
            }

            if (state.forOtherOn) {
                if (connections.isEmpty()) {
                    // Nobody to owe yet. Web says so rather than showing an
                    // empty picker, and the sentence names where to fix it.
                    Muted(
                        S.Transactions.paidForSomeoneNoOne(res),
                        style = SanvyaType.body.copy(fontSize = 12.5.sp),
                    )
                } else {
                    Muted(S.Transactions.paidForSomeonePick(res), style = SanvyaType.body.copy(fontSize = 12.sp))
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        connections.forEach { person ->
                            SanvyaChip(
                                person.name,
                                active = state.forOtherUserId == person.id,
                                onClick = {
                                    viewModel.setForOtherUserId(
                                        if (state.forOtherUserId == person.id) "" else person.id,
                                    )
                                },
                            )
                        }
                    }
                }
            }
        }
    }
}

/** Web's "Split this expense" card. */
@Composable
private fun SplitCard(
    res: Resources,
    viewModel: CreateTransactionViewModel,
    state: CreateTransactionUiState,
    currency: String,
) {
    SanvyaCard(modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SanvyaText(
                    S.Transactions.splitExpense(res),
                    SanvyaType.body.copy(fontWeight = FontWeight.SemiBold),
                )
                Switch(checked = state.splitOn, onCheckedChange = viewModel::setSplitOn)
            }

            if (state.splitOn) {
                SplitCardBody(res = res, viewModel = viewModel, state = state, currency = currency)
            }
        }
    }
}

/**
 * The body of the split card, shown once the toggle is on.
 *
 * Split out from [SplitCard] so the toggle row stays readable and the body
 * can be reasoned about as one unit: group, participants, mode, payers,
 * summary -- web's order, unchanged.
 */
@Composable
private fun SplitCardBody(
    res: Resources,
    viewModel: CreateTransactionViewModel,
    state: CreateTransactionUiState,
    currency: String,
) {
    val colors = LocalSanvyaColors.current
    val groups by viewModel.groups.collectAsState()
    val plan by viewModel.splitPlan.collectAsState()
    val account by viewModel.account.collectAsState()
    // The account the money leaves. Named in two sentences web shows under the
    // payers, so the user knows which of their accounts is being charged.
    val accountName = account?.name.orEmpty()
    val autoGroup = groups.firstOrNull { it.id == state.splitGroupId && it.autoSplit }
    if (autoGroup != null) {
        // Web explains WHY the trip was chosen for you, and how to
        // decline it -- a preselection with no explanation reads as a bug.
        SanvyaText(
            S.Transactions.autoSplitWith(res, autoGroup.name),
            SanvyaType.body.copy(fontSize = 12.sp),
            color = colors.accent,
        )
    }

    Muted(S.Transactions.groupTrip(res), style = SanvyaType.body.copy(fontSize = 12.sp))
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        groups.forEach { group ->
            SanvyaChip(
                group.name,
                active = state.splitGroupId == group.id,
                onClick = {
                    viewModel.setSplitGroup(if (state.splitGroupId == group.id) "" else group.id)
                },
            )
        }
    }

    val groupMemberIds = if (state.splitGroupId.isEmpty()) {
        emptyList()
    } else {
        viewModel.membersOf(state.splitGroupId)
    }

    when {
        state.splitGroupId.isEmpty() -> Muted(
            S.Transactions.pickGroupPre(res) + S.Transactions.pickGroupLink(res) + ".",
            style = SanvyaType.body.copy(fontSize = 12.sp),
        )
        groupMemberIds.size < 2 -> Muted(
            S.Transactions.onlyYou(res),
            style = SanvyaType.body.copy(fontSize = 12.sp),
        )
        else -> {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf(SplitModes.EQUAL, SplitModes.EXACT, SplitModes.PERCENT).forEach { mode ->
                    SanvyaChip(
                        modeLabel(res, mode),
                        active = state.splitMode == mode,
                        onClick = { viewModel.setSplitMode(mode) },
                    )
                }
            }

            Muted(S.Transactions.splitBetween(res), style = SanvyaType.body.copy(fontSize = 12.sp))
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                groupMemberIds.forEach { uid ->
                    SanvyaChip(
                        viewModel.memberName(uid, res),
                        active = state.splitMembers.contains(uid),
                        onClick = { viewModel.toggleSplitMember(uid) },
                    )
                }
            }

            if (state.splitMode != SplitModes.EQUAL && state.splitMembers.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    state.splitMembers.forEachIndexed { index, uid ->
                        AmountRow(
                            label = viewModel.memberName(uid, res),
                            value = state.shareText[uid].orEmpty(),
                            onValueChange = { viewModel.setShareText(uid, it) },
                            placeholder = if (state.splitMode == SplitModes.PERCENT) "%" else currency,
                            // The computed share beside the field is the
                            // point of the whole row: in percent mode you
                            // type 40 and need to see what 40% actually is.
                            trailing = formatMoney(plan.shares.getOrElse(index) { 0L }, currency),
                        )
                    }
                    val totalMinor = viewModel.totalMinor(currency)
                    Muted(
                        if (state.splitMode == SplitModes.EXACT) {
                            val sum = formatMoney(plan.sharesSum, currency)
                            val total = formatMoney(totalMinor, currency)
                            if (plan.sharesSum == totalMinor) {
                                S.Transactions.sharesMatch(res, sum, total)
                            } else {
                                S.Transactions.sharesMismatch(res, sum, total)
                            }
                        } else {
                            // `jsRound` on the SUM, matching Domain's own
                            // acceptance test -- three people at 33.33
                            // read as 100 here and are accepted there.
                            val pct = jsRound(plan.percentSum).toInt()
                            if (pct == 100) {
                                S.Transactions.percentMatch(res, pct)
                            } else {
                                S.Transactions.percentMismatch(res, pct)
                            }
                        },
                        style = SanvyaType.body.copy(fontSize = 12.sp),
                    )
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SanvyaText(S.Transactions.multiplePaid(res), SanvyaType.body.copy(fontSize = 14.sp))
                Switch(checked = state.multiPayer, onCheckedChange = viewModel::setMultiPayer)
            }

            if (state.multiPayer) {
                val totalMinor = viewModel.totalMinor(currency)
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    state.splitMembers.forEach { uid ->
                        AmountRow(
                            label = S.Transactions.memberPaid(res, viewModel.memberName(uid, res)),
                            value = state.paidText[uid].orEmpty(),
                            onValueChange = { viewModel.setPaidText(uid, it) },
                            placeholder = currency,
                            trailing = null,
                        )
                    }
                    val sum = formatMoney(plan.paidSum, currency)
                    val total = formatMoney(totalMinor, currency)
                    Muted(
                        if (plan.paidSum == totalMinor) {
                            S.Transactions.paidMatch(res, sum, total)
                        } else {
                            S.Transactions.paidMismatch(res, sum, total)
                        },
                        style = SanvyaType.body.copy(fontSize = 12.sp),
                    )
                    // Only one leg of a multi-payer split touches an account of
                    // yours; the others are recorded as what they are owed. Web
                    // says so here rather than letting the balance surprise you.
                    Muted(
                        S.Transactions.onlyYourPayment(res, accountName),
                        style = SanvyaType.body.copy(fontSize = 11.sp),
                    )
                }
            } else {
                Muted(
                    S.Transactions.youPaidFrom(res, formatMoney(totalMinor, currency), accountName),
                    style = SanvyaType.body.copy(fontSize = 12.sp),
                )
            }

            SplitSummary(res = res, viewModel = viewModel, state = state, currency = currency)
        }
    }
}

/**
 * Web's summary block: your share, and which way the money leans.
 *
 * `net` is what you paid minus what you owe. Positive and the others owe you;
 * negative and you owe them. Web colours the two differently and so does this,
 * because "you'll owe" and "others owe you" are opposite news.
 */
@Composable
private fun SplitSummary(
    res: Resources,
    viewModel: CreateTransactionViewModel,
    state: CreateTransactionUiState,
    currency: String,
) {
    val colors = LocalSanvyaColors.current
    val plan by viewModel.splitPlan.collectAsState()
    if (!plan.valid) {
        Muted(S.Transactions.pickTwo(res), style = SanvyaType.body.copy(fontSize = 12.sp))
        return
    }
    val me = viewModel.currentUserId.orEmpty()
    val myIndex = state.splitMembers.indexOf(me)
    val myShare = if (myIndex >= 0) plan.shares.getOrElse(myIndex) { 0L } else 0L
    val myPaid = plan.payers.filter { it.isMe }.sumOf { it.paidMinor }
    val net = myPaid - myShare

    SanvyaCard(
        modifier = Modifier.fillMaxWidth(),
        padding = PaddingValues(12.dp),
        background = colors.surface2,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                SanvyaText(S.Transactions.yourShare(res), SanvyaType.body.copy(fontSize = 13.sp))
                SanvyaText(
                    formatMoney(myShare, currency),
                    SanvyaType.body.copy(fontSize = 13.sp, fontWeight = FontWeight.Bold),
                )
                Muted(S.Transactions.countsInBudget(res), style = SanvyaType.body.copy(fontSize = 13.sp))
            }
            if (net > 0) {
                SanvyaText(
                    S.Transactions.othersOweYou(res, formatMoney(net, currency)),
                    SanvyaType.body.copy(fontSize = 13.sp),
                    color = colors.positive,
                )
            }
            if (net < 0) {
                SanvyaText(
                    S.Transactions.youllOwe(res, formatMoney(-net, currency)),
                    SanvyaType.body.copy(fontSize = 13.sp),
                    color = colors.negative,
                )
            }
        }
    }
}

/** One "name … [field] … computed" row. */
@Composable
private fun AmountRow(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    trailing: String?,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SanvyaText(label, SanvyaType.body.copy(fontSize = 14.sp), modifier = Modifier.weight(1f))
        SanvyaInput(
            value = value,
            onValueChange = onValueChange,
            placeholder = placeholder,
            modifier = Modifier.width(110.dp),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        )
        if (trailing != null) {
            Muted(
                trailing,
                modifier = Modifier.width(80.dp),
                style = SanvyaType.body.copy(fontSize = 12.sp),
            )
        }
    }
}

private fun modeLabel(res: Resources, mode: String): String = when (mode) {
    SplitModes.EXACT -> S.Transactions.modeExact(res)
    SplitModes.PERCENT -> S.Transactions.modePercent(res)
    else -> S.Transactions.modeEqual(res)
}
