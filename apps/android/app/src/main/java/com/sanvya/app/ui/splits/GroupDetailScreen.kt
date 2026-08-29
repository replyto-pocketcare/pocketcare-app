package com.sanvya.app.ui.splits

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.data.repository.ExpenseItem
import com.sanvya.app.data.repository.SplitGroup
import com.sanvya.app.domain.money.fromMajor
import com.sanvya.app.domain.receipts.qtyToMajor
import com.sanvya.app.domain.splits.ItemBreakdownItem
import com.sanvya.app.domain.splits.ItemBreakdownShare
import com.sanvya.app.domain.splits.itemBreakdown
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaColors
import com.sanvya.app.ui.accounts.ChipRow
import com.sanvya.app.ui.baseCurrencyNow
import com.sanvya.app.ui.components.ConfirmDialog
import com.sanvya.app.ui.components.DateField
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaChip
import com.sanvya.app.ui.components.SanvyaModal
import com.sanvya.app.ui.components.SanvyaPage
import com.sanvya.app.ui.formatMajorPlain
import com.sanvya.app.ui.formatMoney

/**
 * Real port of apps/web/app/groups/[id]/page.tsx (task #30).
 *
 * Two of the original scope cuts are now closed:
 *
 * **Add expense** no longer opens a local equal-split sheet. Web's button is a
 * link to the full transaction form with this group preselected, and so is
 * this: an unequal expense added from inside a group used to be impossible on a
 * phone while the percent/exact/itemised editor sat one screen away.
 *
 * **Itemised bills** can be opened in place. `expense_items` has existed since
 * 0040 with no UI on either phone, so "who had what" -- the exact question
 * people ask when a split is argued about -- had no answer outside the browser.
 */
@Composable
fun GroupDetailScreen(
    groupId: String,
    onBack: () -> Unit,
    onAddExpense: (String) -> Unit,
    viewModel: GroupDetailViewModel = viewModel(),
) {
    LaunchedEffect(groupId) { viewModel.select(groupId) }

    val res = sRes()
    val colors = LocalSanvyaColors.current
    val group by viewModel.group.collectAsState()
    val members by viewModel.members.collectAsState()
    val expenses by viewModel.expenses.collectAsState()
    val settlements by viewModel.settlements.collectAsState()
    val breakdowns by viewModel.breakdowns.collectAsState()
    val loaded by viewModel.loaded.collectAsState()
    var showInvite by remember { mutableStateOf(false) }
    var settleTarget by remember { mutableStateOf<MemberUiModel?>(null) }
    var showEdit by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    val summary by viewModel.summary.collectAsState()

    SanvyaPage(
        title = group?.name ?: S.Groups.kindGroup(res),
        action = {
            SanvyaChip(
                label = S.Groups.invite(res),
                active = false,
                onClick = { showInvite = true },
            )
            SanvyaChip(
                label = S.Splits.addExpense(res),
                active = false,
                onClick = { onAddExpense(groupId) },
            )
            // Web puts these behind a kebab. A chip row is the native
            // equivalent here and keeps the destructive one visibly separate
            // from the two additive ones above.
            SanvyaChip(label = S.Groups.edit(res), active = false, onClick = { showEdit = true })
            SanvyaChip(label = S.Groups.delete(res), active = false, onClick = { confirmDelete = true })
        },
    ) {
        if (!loaded) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            return@SanvyaPage
        }

        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            summary?.let { sum -> item { GroupSummaryCard(sum, colors) } }
            item {
                Text(S.Groups.membersTitle(res), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = colors.text2)
            }
            items(members, key = { it.userId }) { m ->
                MemberRow(m, viewModel.nameOf(m.userId, res), colors) { if (!m.isSelf) settleTarget = m }
            }

            if (expenses.isNotEmpty()) {
                item { Spacer(Modifier.height(4.dp)); Text(S.Groups.expensesTitle(res), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = colors.text2) }
                items(expenses, key = { it.id }) { e ->
                    ExpenseRow(
                        expense = e,
                        breakdown = breakdowns[e.id],
                        nameOf = { id -> viewModel.nameOf(id, res) },
                        onOpen = { viewModel.loadBreakdown(e.id) },
                        colors = colors,
                    )
                }
            }

            // Settled up -- the other half of the group's history. Its own
            // section rather than mixed into Expenses: a settlement moves money
            // between two members without adding to what the group spent, so
            // interleaving them would imply it counts toward the total.
            if (settlements.isNotEmpty()) {
                item { Spacer(Modifier.height(4.dp)); Text(S.Groups.settledTitle(res), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = colors.text2) }
                items(settlements, key = { it.id }) { s ->
                    SettlementRow(s, { id -> viewModel.nameOf(id, res) }, colors)
                }
            }

            item { Spacer(Modifier.height(72.dp)) }
        }
    }

    InviteSheet(
        open = showInvite,
        groupName = group?.name.orEmpty(),
        viewModel = viewModel,
        onClose = { showInvite = false },
    )

    settleTarget?.let { target ->
        SettleUpSheet(
            viewModel = viewModel,
            target = target,
            targetName = viewModel.nameOf(target.userId, res),
            onDismiss = { viewModel.resetUpiStage(); settleTarget = null },
        )
    }

    if (showEdit) {
        group?.let { g ->
            EditGroupSheet(
                group = g,
                viewModel = viewModel,
                onDismiss = { showEdit = false },
            )
        }
    }

    if (confirmDelete) {
        ConfirmDialog(
            title = S.Groups.deleteTitle(res),
            message = S.Groups.deleteMsg(res, group?.name.orEmpty()),
            confirmLabel = S.Groups.delete(res),
            cancelLabel = S.Translation.commonCancel(res),
            onConfirm = {
                confirmDelete = false
                viewModel.deleteGroup { err -> if (err == null) onBack() }
            },
            onDismiss = { confirmDelete = false },
        )
    }
}

/**
 * Web's summary card: what the trip cost, and which way your side leans.
 *
 * Without it the screen listed rows and left the user to add them up -- you
 * could not tell what a trip cost in total, or whether you were up or down on
 * it, without doing arithmetic by hand.
 *
 * The auto-split badge is here rather than in the edit sheet because it is a
 * FACT about the group that changes what happens to transactions you have not
 * made yet. A setting you cannot see is a surprise waiting to happen.
 */
@Composable
private fun GroupSummaryCard(summary: GroupSummaryUiModel, colors: SanvyaColors) {
    val res = sRes()
    SanvyaCard(modifier = Modifier.fillMaxWidth(), padding = PaddingValues(20.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                Column(Modifier.weight(1f)) {
                    Text(S.Groups.totalSpent(res), fontSize = 13.sp, color = colors.text2)
                    Text(summary.totalSpentFormatted, fontSize = 26.sp, fontWeight = FontWeight.Bold, color = colors.text)
                }
                Column {
                    Text(S.Groups.youreOwed(res), fontSize = 13.sp, color = colors.text2)
                    Text(summary.owedFormatted, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.positive)
                }
                Column {
                    Text(S.Groups.youOwe(res), fontSize = 13.sp, color = colors.text2)
                    Text(summary.oweFormatted, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.negative)
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    if (summary.startDate != null) {
                        summary.startDate + (summary.endDate?.let { " – $it" } ?: "")
                    } else {
                        S.Groups.noDates(res)
                    },
                    fontSize = 13.sp,
                    color = colors.text2,
                )
                Text("· " + S.Groups.members(res, summary.memberCount), fontSize = 13.sp, color = colors.text2)
                if (summary.autoSplit) {
                    Text("· " + S.Groups.autoSplitOn(res), fontSize = 13.sp, color = colors.accent)
                }
            }
        }
    }
}

/**
 * Rename, re-date, and the auto-split toggle -- web's edit modal.
 *
 * The toggle is DISABLED without both dates, and the repository forces the flag
 * off in that case regardless. A trip with no range has nothing to match a
 * transaction's date against, so an auto-split flag on one is a setting that
 * silently never fires -- worse than an absent one, because the user believes
 * it is working.
 */
@Composable
private fun EditGroupSheet(
    group: SplitGroup,
    viewModel: GroupDetailViewModel,
    onDismiss: () -> Unit,
) {
    val res = sRes()
    val colors = LocalSanvyaColors.current
    var name by rememberSaveable(group.id) { mutableStateOf(group.name) }
    var start by rememberSaveable(group.id) { mutableStateOf(group.startDate.orEmpty()) }
    var end by rememberSaveable(group.id) { mutableStateOf(group.endDate.orEmpty()) }
    var auto by rememberSaveable(group.id) { mutableStateOf(group.autoSplit) }
    var error by remember { mutableStateOf<String?>(null) }
    val datesSet = start.isNotBlank() && end.isNotBlank()

    SanvyaModal(open = true, onClose = onDismiss, label = S.Groups.edit(res)) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text(S.Groups.namePlaceholder(res)) },
                modifier = Modifier.fillMaxWidth(),
            )
            Text(S.Groups.datesOptional(res), fontSize = 12.sp, color = colors.text2)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                DateField(value = start, onValueChange = { start = it; if (end.isNotBlank() && it > end) end = it }, modifier = Modifier.weight(1f))
                DateField(value = end, onValueChange = { end = it }, modifier = Modifier.weight(1f))
            }
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Switch(checked = auto && datesSet, onCheckedChange = { auto = it }, enabled = datesSet)
                Column(Modifier.padding(start = 8.dp)) {
                    Text(S.Groups.autoSplitLabel(res), fontSize = 14.sp, color = colors.text)
                    Text(
                        S.Groups.autoSplitDesc(res, start.ifBlank { "—" }, end.ifBlank { "—" }, group.kind),
                        fontSize = 12.sp,
                        color = colors.text2,
                    )
                }
            }
            error?.let { Text(it, color = colors.negative, fontSize = 13.sp) }
            Button(
                onClick = {
                    viewModel.updateGroup(name, start, end, auto) { err ->
                        if (err == null) onDismiss() else error = err
                    }
                },
                enabled = name.isNotBlank(),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(S.Translation.commonSave(res))
            }
        }
    }
}

@Composable
private fun MemberRow(m: MemberUiModel, name: String, colors: SanvyaColors, onClick: () -> Unit) {
    val res = sRes()
    Row(
        Modifier.fillMaxWidth().clickable(enabled = !m.isSelf, onClick = onClick).padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(name, color = colors.text, fontWeight = FontWeight.Medium)
        val net = m.net
        Text(
            when {
                net == 0L -> S.Groups.settledTag(res)
                net > 0 -> S.Groups.owesYouAmt(res, m.netFormatted)
                else -> S.Groups.youOweAmt(res, m.netFormatted)
            },
            fontSize = 13.sp,
            color = if (net == 0L) colors.text2 else if (net > 0) colors.positive else colors.negative,
        )
    }
}

/**
 * One expense, expandable in place when the bill was itemised.
 *
 * Web's own comment on the same row: the answer to "why do I owe this?" belongs
 * next to the number, not on another screen. The chip only exists when
 * `expenses.has_items` is set, so an ordinary expense keeps the plain row.
 */
@Composable
private fun ExpenseRow(
    expense: ExpenseUiModel,
    breakdown: ExpenseBreakdownUiModel?,
    nameOf: (String) -> String,
    onOpen: () -> Unit,
    colors: SanvyaColors,
) {
    val res = sRes()
    // rememberSaveable, not remember: a LazyColumn drops an item's state when it
    // scrolls out of view, so an opened bill would silently close itself as the
    // user scrolled past it and back.
    var open by rememberSaveable(expense.id) { mutableStateOf(false) }

    Column(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(expense.description ?: S.Groups.expenseFallback(res), color = colors.text, fontWeight = FontWeight.Medium)
                Text(expense.date, fontSize = 11.sp, color = colors.text2)
            }
            if (expense.hasItems) {
                SanvyaChip(
                    label = if (open) S.Receipts.breakdownHide(res) else S.Receipts.breakdownShow(res),
                    active = open,
                    onClick = { open = !open; if (open) onOpen() },
                )
            }
            Text(
                expense.amountFormatted,
                color = colors.text,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(start = 8.dp),
            )
        }

        if (expense.hasItems && open) {
            if (breakdown == null) {
                CircularProgressIndicator(Modifier.size(18.dp))
            } else {
                ItemBreakdownPanel(
                    breakdown = breakdown,
                    currency = expense.currency,
                    nameOf = nameOf,
                    colors = colors,
                )
            }
        }
    }
}

/**
 * Who had what, and what that came to.
 *
 * Read-only, exactly as web is: editing a split after the fact means rewriting
 * ledger postings, which is the edit-transaction flow's job.
 *
 * The person chips filter to one member's lines. The arithmetic behind both the
 * filter and the footer total is Domain's `itemBreakdown` under its own golden
 * vectors -- the two platforms cannot drift on which lines are "yours".
 */
@Composable
private fun ItemBreakdownPanel(
    breakdown: ExpenseBreakdownUiModel,
    currency: String,
    nameOf: (String) -> String,
    colors: SanvyaColors,
) {
    val res = sRes()
    // "" is web's own "everyone" value, not a placeholder -- see itemBreakdown.
    var filter by rememberSaveable { mutableStateOf("") }
    val itemsById = remember(breakdown) { breakdown.items.associateBy { it.id } }
    val view = remember(breakdown, filter) {
        itemBreakdown(
            items = breakdown.items.map { ItemBreakdownItem(it.id, it.amount) },
            shares = breakdown.shares.map { ItemBreakdownShare(it.itemId, it.userId, it.shareAmount) },
            filterUserId = filter,
        )
    }

    Column(
        modifier = Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(colors.surface2)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        // One person cannot be filtered against themselves -- web hides the row
        // entirely below two people, and so does this.
        if (view.everyone.size > 1) {
            ChipRow(
                options = listOf("") + view.everyone,
                selected = filter,
                label = { id -> if (id.isEmpty()) S.Receipts.breakdownEveryone(res) else nameOf(id) },
                onSelect = { filter = it },
                colors = colors,
            )
        }

        view.lines.forEach { line ->
            val item = itemsById[line.itemId]
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(
                            item?.description?.takeIf { it.isNotBlank() } ?: kindLabel(res, item?.kind),
                            fontSize = 13.5.sp,
                            color = colors.text,
                        )
                        // Plain captions, not chips: these are labels, and a
                        // chip implies a control you can press. (Web's own note
                        // on the same two spans.)
                        if (item != null && item.kind != "item") {
                            Text(
                                kindLabel(res, item.kind).uppercase(),
                                fontSize = 10.5.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = colors.text2,
                            )
                        }
                        quantityLabel(res, item)?.let { qty ->
                            Text(qty, fontSize = 11.5.sp, color = colors.text2)
                        }
                    }
                    if (line.shares.isNotEmpty()) {
                        Text(
                            line.shares.joinToString(" · ") { "${nameOf(it.userId)} ${formatMoney(it.amount, currency)}" },
                            fontSize = 11.5.sp,
                            color = colors.text2,
                        )
                    }
                }
                Text(
                    formatMoney(line.amount, currency),
                    fontSize = 13.5.sp,
                    color = colors.text,
                    modifier = Modifier.padding(start = 8.dp),
                )
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                if (filter.isEmpty()) S.Receipts.splitTotal(res) else S.Receipts.breakdownPersonTotal(res, nameOf(filter)),
                fontSize = 13.5.sp,
                fontWeight = FontWeight.Bold,
                color = colors.text,
            )
            Text(formatMoney(view.total, currency), fontSize = 13.5.sp, fontWeight = FontWeight.Bold, color = colors.text)
        }
    }
}

/** `expense_items.kind` as a label. Unknown kinds read as a plain item, which
 * is what web's `t(\`kind.${kind}\`, kind)` degrades to. */
private fun kindLabel(res: android.content.res.Resources, kind: String?): String = when (kind) {
    "tax" -> S.Receipts.kindTax(res)
    "service_charge" -> S.Receipts.kindServiceCharge(res)
    "tip" -> S.Receipts.kindTip(res)
    "discount" -> S.Receipts.kindDiscount(res)
    else -> S.Receipts.kindItem(res)
}

/**
 * "2 kg" / "3×", or nothing at all when the line carries no quantity.
 *
 * The bare "×" when there is no unit is web's, and is a symbol rather than a
 * word on purpose -- it needs no translation, which is why it is not a key.
 */
private fun quantityLabel(res: android.content.res.Resources, item: ExpenseItem?): String? {
    val milli = item?.quantity ?: return null
    val unit = item.unit?.takeIf { it.isNotBlank() }
    return S.Receipts.splitQtyLabel(res, trimmedQty(milli), if (unit != null) " $unit" else "×")
}

/**
 * Milli-units as the shortest exact decimal: 2000 -> "2", 1500 -> "1.5".
 * Web prints the raw JS number, which drops trailing zeros the same way.
 *
 * A knowing duplicate of the same helper in `receipts/SplitReceiptScreen.kt`:
 * it is private there, and lifting it into a shared UI module is a change to a
 * file this one does not own.
 */
private fun trimmedQty(milli: Long): String {
    val major = qtyToMajor(milli)
    if (major == Math.floor(major)) return major.toLong().toString()
    return String.format(java.util.Locale.ROOT, "%.3f", major).trimEnd('0').trimEnd('.')
}

/**
 * One past settlement, with its status.
 *
 * A PENDING settlement is a claim, not a fact: it came from a UPI hand-off that
 * gives no delivery callback, and only the payee can close it. Rendering it
 * identically to a confirmed one tells both people the debt is settled when the
 * money may never have arrived -- which is web's "Waiting to be confirmed".
 */
@Composable
private fun SettlementRow(s: SettlementUiModel, nameOf: (String) -> String, colors: SanvyaColors) {
    val res = sRes()
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Column(Modifier.weight(1f)) {
            Text(
                when {
                    s.iPaid -> S.Groups.settledYouPaid(res, nameOf(s.otherUserId))
                    s.paidToMe -> S.Groups.settledPaidYou(res, nameOf(s.otherUserId))
                    else -> S.Groups.settledBetween(res, nameOf(s.fromUser), nameOf(s.toUser))
                },
                color = colors.text,
                fontWeight = FontWeight.Medium,
                fontSize = 13.sp,
            )
            Text(s.date, fontSize = 11.sp, color = colors.text2)
            if (s.pending) {
                Text(S.Groups.settledPending(res), fontSize = 11.sp, color = colors.warning)
            }
        }
        Text(s.amountFormatted, color = colors.text2, fontWeight = FontWeight.SemiBold)
    }
}

/**
 * Settle up with one member -- web's settle Modal on `/friends`.
 *
 * Two things this used to get wrong, both of which booked money that never
 * moved:
 *
 * **There was no "None".** Every settlement picked an account, so settling a
 * cash debt in person still posted a bank transfer. Web's account `<select>`
 * opens on an empty option that means exactly "don't post anything", and the
 * repository already honours a null account by skipping the ledger leg.
 *
 * **UPI was offered unconditionally.** It is a rupee rail, so it is offered
 * only when this settlement is in INR and there is an amount to send -- web's
 * `base === "INR" && Number(amount) > 0`. The currency compared here is the
 * GROUP's, because that is what the settlement is recorded in.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettleUpSheet(
    viewModel: GroupDetailViewModel,
    target: MemberUiModel,
    targetName: String,
    onDismiss: () -> Unit,
) {
    val res = sRes()
    val colors = LocalSanvyaColors.current
    val accounts by viewModel.accounts.collectAsState()
    val upiStage by viewModel.upiStage.collectAsState()
    // direction from the CALLER's perspective: target.net > 0 means they owe
    // us (we "received"), target.net < 0 means we owe them (we "paid").
    val direction = if (target.net >= 0) "received" else "paid"
    // The GROUP's currency. `formatMajorPlain`, not `%.2f` on a `/ 100.0`:
    // those hardcoded the same assumption twice over -- the scale AND the
    // decimal count -- so a zero-decimal currency prefilled a hundredth of the
    // balance and then printed two decimals that do not exist in it.
    val settleGroup by viewModel.group.collectAsState()
    val settleCurrency = settleGroup?.currency ?: baseCurrencyNow()
    var amount by remember {
        mutableStateOf(formatMajorPlain(kotlin.math.abs(target.net), settleCurrency))
    }
    // "" is a real option, not a placeholder -- see the doc comment above.
    var accountId by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }

    // `fromMajor`, never `* 100`: the settlement carries its own currency and a
    // zero-decimal one would be sent a hundred times over.
    val amountMinor = fromMajor(amount.replace(",", "").toDoubleOrNull() ?: 0.0, settleCurrency).amount
    val upiOffered = direction == "paid" && settleCurrency == "INR" && amountMinor > 0

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = colors.surface) {
        Column(Modifier.padding(20.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(S.Splits.settleWith(res, targetName), fontWeight = FontWeight.Bold, fontSize = 18.sp, color = colors.text)
            Text(
                if (target.net >= 0) S.Splits.theyPayYouBack(res, targetName) else S.Splits.youPayThemBack(res, targetName),
                fontSize = 13.sp,
                color = colors.text2,
            )
            OutlinedTextField(
                value = amount,
                onValueChange = { amount = it },
                label = { Text(S.Splits.amountLabel(res, settleCurrency)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            Text(
                if (direction == "received") S.Splits.receivedInto(res) else S.Splits.paidFrom(res),
                fontSize = 12.sp,
                color = colors.text2,
            )
            ChipRow(
                options = listOf("") + accounts.map { it.id },
                selected = accountId,
                label = { id -> if (id.isEmpty()) S.Splits.noneMarkSettled(res) else accounts.find { it.id == id }?.name.orEmpty() },
                onSelect = { accountId = it },
                colors = colors,
            )

            if (upiOffered) {
                // Web renders the UPI stages INLINE inside the settle modal
                // rather than stacking a dialog on a sheet -- a modal over a
                // modal on a phone hides the amount the payment is for.
                when (val stage = upiStage) {
                    UpiStage.Idle -> Button(
                        onClick = { viewModel.startUpiFetch(target.userId) },
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text(S.Payments.payButton(res)) }
                    is UpiStage.Fetching -> Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        CircularProgressIndicator(Modifier.size(20.dp))
                        Text(S.Payments.payPreparing(res), fontSize = 13.sp, color = colors.text2)
                    }
                    is UpiStage.Error -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(
                            if (stage.code == "no_handle") S.Payments.payNoHandle(res, targetName) else stage.message,
                            fontSize = 13.sp,
                            color = colors.negative,
                        )
                        TextButton(onClick = { viewModel.resetUpiStage() }) { Text(S.Payments.payBack(res)) }
                    }
                    is UpiStage.Ready -> PayViaUpiDialog(
                        counterpartyName = stage.displayName ?: targetName,
                        vpa = stage.vpa,
                        amountMinor = amountMinor,
                        onDismiss = { viewModel.resetUpiStage() },
                        onPaid = { ref ->
                            viewModel.recordUpiSettlement(target.userId, amount, direction, ref) { err ->
                                viewModel.resetUpiStage()
                                if (err == null) onDismiss()
                            }
                        },
                    )
                }
            }

            error?.let { Text(it, fontSize = 12.sp, color = colors.negative) }

            Button(
                onClick = {
                    saving = true
                    viewModel.settleManually(target.userId, amount, direction, accountId.ifEmpty { null }) { err ->
                        saving = false
                        error = err
                        if (err == null) onDismiss()
                    }
                },
                enabled = amountMinor > 0 && !saving,
                modifier = Modifier.fillMaxWidth(),
            ) { Text(if (saving) S.Splits.settling(res) else S.Splits.settle(res)) }
        }
    }
}
