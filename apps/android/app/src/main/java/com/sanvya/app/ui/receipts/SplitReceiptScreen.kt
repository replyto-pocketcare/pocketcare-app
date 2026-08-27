package com.sanvya.app.ui.receipts

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.domain.receipts.LineProblem
import com.sanvya.app.domain.receipts.ReceiptLine
import com.sanvya.app.domain.receipts.isCharge
import com.sanvya.app.domain.receipts.majorTextFromMinor
import com.sanvya.app.domain.receipts.qtyToMajor
import com.sanvya.app.domain.receipts.splitModesFor
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaShape
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.SanvyaButton
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaChip
import com.sanvya.app.ui.components.SanvyaInput
import com.sanvya.app.ui.components.SanvyaText
import com.sanvya.app.ui.formatMoney

/**
 * Per-item split assignment — "who had what".
 *
 * Ported from `apps/web/app/receipts/split/page.tsx`. One card per line: tap
 * faces to include people, pick how that line divides. Tax, service charge and
 * tip default to `proportional` (allocated by what each person actually ate),
 * which is the fair answer often enough that most people never touch it — but
 * can be overridden per charge, because "the service charge was for the table"
 * is just as common.
 *
 * Nothing saves until every line is assigned and every exact/percent split
 * validates, so the expense that reaches the ledger is always balanced. Both
 * the per-line check and the allocation itself are Domain's, under vectors.
 *
 * Mirrors iOS's SplitReceiptView.swift.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SplitReceiptScreen(
    scanId: String,
    groupId: String,
    accountId: String,
    categoryId: String,
    onSaved: (String) -> Unit,
    viewModel: SplitReceiptViewModel = viewModel(),
) {
    val res = sRes()
    val colors = LocalSanvyaColors.current

    LaunchedEffect(scanId, groupId) { viewModel.load(scanId, groupId, accountId, categoryId) }

    val draft by viewModel.draft.collectAsState()
    val loaded by viewModel.loaded.collectAsState()
    val corrupt by viewModel.corrupt.collectAsState()
    val memberIds by viewModel.memberIds.collectAsState()
    val state by viewModel.state.collectAsState()
    val group by viewModel.group.collectAsState()
    val error by viewModel.error.collectAsState()
    val savedExpenseId by viewModel.savedExpenseId.collectAsState()

    LaunchedEffect(savedExpenseId) { savedExpenseId?.let(onSaved) }

    val youLabel = S.Receipts.splitYou(res)
    val someoneLabel = S.Receipts.splitSomeone(res)
    fun nameOf(id: String) = viewModel.nameOf(id, youLabel, someoneLabel)

    Scaffold(containerColor = colors.bg) { padding ->
        val d = draft
        if (d == null) {
            if (loaded) {
                SanvyaCard(modifier = Modifier.padding(padding).padding(16.dp)) {
                    SanvyaText(
                        if (corrupt) S.Receipts.splitCorrupt(res) else S.Receipts.splitNotFound(res),
                        SanvyaType.body,
                    )
                }
            }
            return@Scaffold
        }

        val allocation = viewModel.allocation()
        val alloc = allocation?.getOrNull()
        val hasProblem = viewModel.hasLineProblem()

        Column(modifier = Modifier.padding(padding).fillMaxSize()) {
            LazyColumn(
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                item {
                    SanvyaText(
                        listOfNotNull(S.Receipts.splitIntro(res), group?.name).joinToString(" · "),
                        SanvyaType.body.copy(fontSize = 13.sp),
                        color = colors.text2,
                    )
                }

                item {
                    SanvyaCard(padding = PaddingValues(14.dp)) {
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            SanvyaText(
                                S.Receipts.splitQuick(res),
                                SanvyaType.body.copy(fontSize = 12.sp),
                                color = colors.text2,
                            )
                            SanvyaChip(
                                label = S.Receipts.splitEveryoneAll(res),
                                active = false,
                                onClick = { viewModel.applyToAll(viewModel.everyone()) },
                            )
                            SanvyaChip(
                                label = S.Receipts.splitOnlyMe(res),
                                active = false,
                                onClick = { viewModel.applyToAll(viewModel.onlyMe()) },
                            )
                        }
                    }
                }

                items(d.lines, key = { it.id }) { line ->
                    val s = state[line.id]
                    if (s != null) {
                        SanvyaCard(padding = PaddingValues(16.dp)) {
                            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                LineHeader(line, viewModel.currency, res)

                                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                    memberIds.forEach { uid ->
                                        SanvyaChip(
                                            label = nameOf(uid),
                                            active = s.members.contains(uid),
                                            onClick = { viewModel.toggleMember(line.id, uid) },
                                        )
                                    }
                                }

                                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                    splitModesFor(line).forEach { m ->
                                        SanvyaChip(
                                            label = modeLabel(m, res),
                                            active = s.mode == m,
                                            onClick = { viewModel.setMode(line.id, m) },
                                        )
                                    }
                                }

                                if (s.mode == "exact" || s.mode == "percent" || s.mode == "quantity") {
                                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                        s.members.forEach { uid ->
                                            Row(
                                                modifier = Modifier.fillMaxWidth(),
                                                verticalAlignment = Alignment.CenterVertically,
                                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                                            ) {
                                                SanvyaText(
                                                    nameOf(uid),
                                                    SanvyaType.body.copy(fontSize = 14.sp),
                                                    modifier = Modifier.weight(1f),
                                                    maxLines = 1,
                                                    overflow = TextOverflow.Ellipsis,
                                                )
                                                SanvyaInput(
                                                    value = s.weights[uid] ?: "",
                                                    onValueChange = { viewModel.setWeight(line.id, uid, it) },
                                                    modifier = Modifier.widthIn(max = 130.dp),
                                                    placeholder = placeholderFor(s.mode, viewModel.digits),
                                                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                                                )
                                                SanvyaText(
                                                    suffixFor(s.mode, line.unit),
                                                    SanvyaType.body.copy(fontSize = 12.sp),
                                                    color = colors.text2,
                                                    modifier = Modifier.widthIn(min = 24.dp),
                                                )
                                            }
                                        }
                                    }
                                }

                                val problem = viewModel.problemFor(line)
                                if (problem != null) {
                                    SanvyaText(
                                        problemText(problem, viewModel.digits, res),
                                        SanvyaType.body.copy(fontSize = 12.5.sp),
                                        color = colors.negative,
                                    )
                                } else if (alloc != null) {
                                    FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                        (alloc.perLine[line.id] ?: emptyList()).forEach { sh ->
                                            SanvyaText(
                                                "${nameOf(sh.userId)} ${formatMoney(sh.amount, viewModel.currency)}",
                                                SanvyaType.body.copy(fontSize = 12.5.sp),
                                                color = colors.text2,
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // The summary sits ON the page background, not inside the list, so
            // the card reads as a card rather than a cut-off strip. Web pins it
            // the same way and for the same reason.
            SanvyaCard(
                modifier = Modifier.padding(horizontal = 16.dp).padding(bottom = 12.dp),
                padding = PaddingValues(16.dp),
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (alloc != null && !hasProblem) {
                        // Per-person tiles. A row of "Name: ₹x" runs together at
                        // a glance; stacking the label over the amount makes
                        // each person scannable. Web's reasoning, kept.
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            memberIds.forEach { uid ->
                                PersonTile(
                                    name = nameOf(uid),
                                    amount = formatMoney(alloc.byUser[uid] ?: 0L, viewModel.currency),
                                    isMe = nameOf(uid) == youLabel,
                                )
                            }
                        }
                        HorizontalDivider(color = colors.border)
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.Bottom,
                        ) {
                            SanvyaText(
                                S.Receipts.splitTotal(res),
                                SanvyaType.body.copy(fontSize = 13.sp),
                                color = colors.text2,
                            )
                            Box(Modifier.weight(1f))
                            SanvyaText(
                                formatMoney(alloc.total, viewModel.currency),
                                SanvyaType.body.copy(fontSize = 17.sp, fontWeight = FontWeight.SemiBold),
                            )
                        }
                    } else {
                        SanvyaText(
                            if (hasProblem) {
                                S.Receipts.splitFixLines(res)
                            } else {
                                allocation?.exceptionOrNull()?.message ?: S.Receipts.splitFixLines(res)
                            },
                            SanvyaType.body.copy(fontSize = 13.sp),
                            color = colors.negative,
                        )
                    }

                    error?.let {
                        SanvyaText(it, SanvyaType.body.copy(fontSize = 13.sp), color = colors.negative)
                    }

                    SanvyaButton(
                        onClick = { viewModel.save() },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = viewModel.canSave(),
                    ) {
                        SanvyaText(S.Receipts.splitSave(res), SanvyaType.button, modifier = Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

@Composable
private fun LineHeader(line: ReceiptLine, currency: String, res: android.content.res.Resources) {
    val colors = LocalSanvyaColors.current
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            SanvyaText(
                line.description.ifEmpty { kindLabel(line.kind, res) },
                SanvyaType.body.copy(fontSize = 15.sp, fontWeight = FontWeight.SemiBold),
            )
            if (isCharge(line.kind) || line.quantity != null) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (isCharge(line.kind)) {
                        // A plain uppercase caption, not a chip: a chip reads as
                        // tappable and this is a static label. Web fixed the
                        // same thing for the same reason.
                        SanvyaText(
                            kindLabel(line.kind, res).uppercase(),
                            SanvyaType.body.copy(fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold),
                            color = colors.text2,
                        )
                    }
                    if (isCharge(line.kind) && line.quantity != null) {
                        SanvyaText("·", SanvyaType.body.copy(fontSize = 11.5.sp), color = colors.text2)
                    }
                    line.quantity?.let { q ->
                        SanvyaText(
                            S.Receipts.splitQtyLabel(res, trimmedQty(q), line.unit?.let { " $it" } ?: ""),
                            SanvyaType.body.copy(fontSize = 11.5.sp),
                            color = colors.text2,
                        )
                    }
                }
            }
        }
        SanvyaText(
            formatMoney(line.amount, currency),
            SanvyaType.body.copy(fontSize = 15.sp, fontWeight = FontWeight.SemiBold),
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun PersonTile(name: String, amount: String, isMe: Boolean) {
    val colors = LocalSanvyaColors.current
    SanvyaCard(
        modifier = Modifier.widthIn(min = 120.dp),
        shape = SanvyaShape.radiusSm,
        padding = PaddingValues(horizontal = 10.dp, vertical = 8.dp),
        background = if (isMe) colors.accentGhost else colors.surface2,
    ) {
        SanvyaText(name, SanvyaType.body.copy(fontSize = 11.5.sp), color = colors.text2, maxLines = 1, overflow = TextOverflow.Ellipsis)
        SanvyaText(amount, SanvyaType.body.copy(fontSize = 15.sp, fontWeight = FontWeight.SemiBold))
    }
}

private fun placeholderFor(mode: String, digits: Int): String =
    if (mode == "exact") majorTextFromMinor(0L, digits) else "0"

private fun suffixFor(mode: String, unit: String?): String = when (mode) {
    "percent" -> "%"
    "quantity" -> unit ?: "×"
    else -> ""
}

/**
 * `mode.*` and `kind.*` are looked up dynamically on web; the generated
 * accessors here are flat, so these are exhaustive when-expressions over closed
 * sets rather than a string-keyed map that could silently miss.
 */
private fun modeLabel(mode: String, res: android.content.res.Resources): String = when (mode) {
    "equal" -> S.Receipts.modeEqual(res)
    "quantity" -> S.Receipts.modeQuantity(res)
    "percent" -> S.Receipts.modePercent(res)
    "exact" -> S.Receipts.modeExact(res)
    else -> S.Receipts.modeProportional(res)
}

private fun kindLabel(kind: String, res: android.content.res.Resources): String = when (kind) {
    "tax" -> S.Receipts.kindTax(res)
    "service_charge" -> S.Receipts.kindServiceCharge(res)
    "tip" -> S.Receipts.kindTip(res)
    "discount" -> S.Receipts.kindDiscount(res)
    else -> S.Receipts.kindItem(res)
}

private fun problemText(
    problem: LineProblem,
    digits: Int,
    res: android.content.res.Resources,
): String = when (problem) {
    is LineProblem.NeedsSomeone -> S.Receipts.splitNeedsSomeone(res)
    is LineProblem.ExactMismatch ->
        S.Receipts.splitExactMismatch(res, majorTextFromMinor(problem.diffMinor, digits))
    is LineProblem.PercentMismatch -> S.Receipts.splitPercentMismatch(res, problem.pct)
    is LineProblem.QuantityMismatch ->
        S.Receipts.splitQtyMismatch(res, trimmedQty(problem.gotMilli), trimmedQty(problem.wantMilli))
}

/**
 * Milli-units as the shortest exact decimal: 2000 -> "2", 1500 -> "1.5".
 * Web prints the raw JS number, which drops trailing zeros the same way.
 */
private fun trimmedQty(milli: Long): String {
    val major = qtyToMajor(milli)
    if (major == Math.floor(major)) return major.toLong().toString()
    return String.format(java.util.Locale.ROOT, "%.3f", major).trimEnd('0').trimEnd('.')
}
