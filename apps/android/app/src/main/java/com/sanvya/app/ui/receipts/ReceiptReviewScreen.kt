package com.sanvya.app.ui.receipts

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.domain.receipts.ReceiptLine
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaColors
import com.sanvya.app.theme.SanvyaRadius
import java.text.NumberFormat
import java.util.Locale
import com.sanvya.app.ui.formatMoney
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.ui.components.SanvyaChip
import com.sanvya.app.ui.components.SanvyaInput
import com.sanvya.app.ui.components.SanvyaPage

private val LINE_KINDS = listOf("item", "tax", "service_charge", "tip", "discount")

/**
 * Real port of apps/web/app/receipts/review/page.tsx (task #62). See
 * docs/mobile/screen-specs/receipt-scan.md.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReceiptReviewScreen(
    scanId: String,
    onBack: () -> Unit,
    onSaved: (transactionId: String) -> Unit,
    /**
     * "Split this bill" — the group id is resolved (or created) by the view
     * model first, so this only has to navigate.
     */
    onSplit: (groupId: String, accountId: String, categoryId: String) -> Unit = { _, _, _ -> },
    viewModel: ReceiptReviewViewModel = viewModel(),
) {
    LaunchedEffect(scanId) { viewModel.load(scanId) }

    val colors = LocalSanvyaColors.current
    val draft by viewModel.draft.collectAsState()
    val accounts by viewModel.accounts.collectAsState()
    val categories by viewModel.categories.collectAsState()
    val accountId by viewModel.accountId.collectAsState()
    val categoryId by viewModel.categoryId.collectAsState()
    val loaded by viewModel.loaded.collectAsState()
    val saving by viewModel.saving.collectAsState()
    val error by viewModel.error.collectAsState()
    val savedTransactionId by viewModel.savedTransactionId.collectAsState()
    val wantsSplit by viewModel.wantsSplit.collectAsState()
    val groups by viewModel.groups.collectAsState()
    val groupId by viewModel.groupId.collectAsState()
    val newGroupName by viewModel.newGroupName.collectAsState()
    val splitGroupId by viewModel.splitGroupId.collectAsState()
    // Hoisted: continueToSplit() runs in a coroutine and cannot call sRes(),
    // which is @Composable. Same rule the rest of this codebase follows.
    val pickGroupMessage = S.Receipts.reviewPickGroup(sRes())

    LaunchedEffect(savedTransactionId) {
        savedTransactionId?.let { onSaved(it) }
    }

    LaunchedEffect(splitGroupId) {
        splitGroupId?.let {
            viewModel.clearSplitTarget()
            onSplit(it, accountId.orEmpty(), categoryId.orEmpty())
        }
    }

    SanvyaPage(
        title = S.Receipts.reviewTitle(sRes()),
        action = {

        },
    ) {
        if (!loaded) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            return@SanvyaPage
        }
        val d = draft
        if (d == null) {
            Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                Text(error ?: S.Receipts.reviewNotFound(sRes()), color = colors.text2, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            }
            return@SanvyaPage
        }

        val digits = 2
        val rec = viewModel.reconcileResult()
        val subs = viewModel.subtotalsResult()
        val balanced = rec?.ok ?: false
        val canSave = balanced && accountId != null && !saving

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                Card(colors = CardDefaults.cardColors(containerColor = colors.surface), shape = RoundedCornerShape(SanvyaRadius.radiusLg)) {
                    Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        OutlinedTextField(
                            value = d.merchant ?: "", onValueChange = { viewModel.setMerchant(it) },
                            label = { Text(S.Receipts.reviewMerchant(sRes())) }, singleLine = true, modifier = Modifier.fillMaxWidth(),
                        )
                        OutlinedTextField(
                            value = d.occurredAt ?: "", onValueChange = { viewModel.setOccurredAt(it) },
                            label = { Text("Date (YYYY-MM-DD)") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
                        )
                        Text(S.Receipts.reviewAccount(sRes()), fontSize = 12.sp, color = colors.text2)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            accounts.forEach { a ->
                                FilterChip(selected = accountId == a.id, onClick = { viewModel.setAccountId(a.id) }, label = { Text(a.name) })
                            }
                        }
                        Text(S.Receipts.reviewCategory(sRes()), fontSize = 12.sp, color = colors.text2)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            FilterChip(selected = categoryId == null, onClick = { viewModel.setCategoryId(null) }, label = { Text(S.Receipts.reviewNoCategory(sRes())) })
                            categories.forEach { c ->
                                FilterChip(selected = categoryId == c.id, onClick = { viewModel.setCategoryId(c.id) }, label = { Text(c.name) })
                            }
                        }
                    }
                }
            }

            item {
                Text(S.Receipts.reviewItems(sRes()), fontWeight = FontWeight.Bold, color = colors.text, fontSize = 15.sp)
            }
            items(d.lines, key = { it.id }) { line ->
                LineEditor(
                    line = line,
                    digits = digits,
                    colors = colors,
                    onChange = { patch -> viewModel.updateLine(line.id) { it.copy(description = patch.description, quantity = patch.quantity, unit = patch.unit, kind = patch.kind, amount = patch.amount) } },
                    onRemove = { viewModel.removeLine(line.id) },
                )
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { viewModel.addLine("item") }) { Text("+ Add item") }
                    OutlinedButton(onClick = { viewModel.addLine("tax") }) { Text("+ Add charge") }
                }
            }

            item {
                Card(colors = CardDefaults.cardColors(containerColor = colors.surface), shape = RoundedCornerShape(SanvyaRadius.radiusLg)) {
                    Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        subs?.let { s ->
                            SubtotalRow(S.Receipts.reviewSubtotalItems(sRes()), s.items, d.currency)
                            if (s.discount != 0L) SubtotalRow(S.Receipts.kindDiscount(sRes()), s.discount, d.currency)
                            if (s.serviceCharge != 0L) SubtotalRow(S.Receipts.kindServiceCharge(sRes()), s.serviceCharge, d.currency)
                            if (s.tax != 0L) SubtotalRow(S.Receipts.kindTax(sRes()), s.tax, d.currency)
                            if (s.tip != 0L) SubtotalRow(S.Receipts.kindTip(sRes()), s.tip, d.currency)
                        }
                        OutlinedTextField(
                            value = d.total?.let { formatMajor(it, digits) } ?: "",
                            onValueChange = { v -> viewModel.setTotal(parseMajor(v, digits)) },
                            label = { Text(S.Receipts.reviewTotal(sRes())) },
                            singleLine = true,
                            modifier = Modifier.widthIn(max = 220.dp),
                        )
                        rec?.let { r ->
                            Surface(
                                color = if (balanced) colors.surface2 else colors.negative.copy(alpha = 0.12f),
                                shape = RoundedCornerShape(10.dp),
                            ) {
                                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Text(
                                        if (balanced) "Adds up: ${formatMoney(r.computed, d.currency)} ✓"
                                        else if (r.reason == "missing_total") S.Receipts.reviewNeedTotal(sRes())
                                        else "Lines add up to ${formatMoney(r.computed, d.currency)}, but the receipt says ${r.stated?.let { formatMoney(it, d.currency) } ?: "—"}.",
                                        fontSize = 13.sp,
                                        color = colors.text,
                                    )
                                    if (!balanced && r.reason == "mismatch") {
                                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                            Button(onClick = { viewModel.addDifferenceAsLine() }) { Text("Add ${formatMoney(r.delta, d.currency)} as a line") }
                                            OutlinedButton(onClick = { viewModel.useComputedTotal() }) { Text("Use ${formatMoney(r.computed, d.currency)}") }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            item {
                Card(colors = CardDefaults.cardColors(containerColor = colors.surface), shape = RoundedCornerShape(SanvyaRadius.radiusLg)) {
                    Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        // Record or split. This was a dead, disabled
                        // "Split this bill — coming soon" chip, hardcoded in
                        // English, until the itemized write path landed
                        // (2026-08-27). It is the real toggle now.
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            SanvyaChip(
                                label = S.Receipts.reviewJustRecord(sRes()),
                                active = !wantsSplit,
                                onClick = { viewModel.setWantsSplit(false) },
                            )
                            SanvyaChip(
                                label = S.Receipts.reviewSplitIt(sRes()),
                                active = wantsSplit,
                                onClick = { viewModel.setWantsSplit(true) },
                            )
                        }
                        if (wantsSplit) {
                            SplitGroupPicker(
                                groups = groups,
                                groupId = groupId,
                                newGroupName = newGroupName,
                                onPickGroup = viewModel::setGroupId,
                                onNewGroupName = viewModel::setNewGroupName,
                            )
                        }
                        error?.let { Text(it, color = colors.negative, fontSize = 12.sp) }
                        Button(
                            onClick = {
                                if (wantsSplit) viewModel.continueToSplit(pickGroupMessage) else viewModel.saveAsTransaction()
                            },
                            enabled = canSave,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text(
                                when {
                                    saving -> S.Translation.commonSaving(sRes())
                                    wantsSplit -> S.Receipts.reviewContinueToSplit(sRes())
                                    else -> S.Receipts.reviewSave(sRes())
                                },
                            )
                        }
                        if (!balanced) {
                            Text(S.Receipts.reviewMustBalance(sRes()), fontSize = 11.sp, color = colors.text2)
                        }
                    }
                }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

@Composable
private fun SubtotalRow(label: String, amountMinor: Long, currency: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, fontSize = 13.sp, color = LocalSanvyaColors.current.text2)
        Text(formatMoney(amountMinor, currency), fontSize = 13.sp)
    }
}

@Composable
private fun LineEditor(line: ReceiptLine, digits: Int, colors: SanvyaColors, onChange: (ReceiptLine) -> Unit, onRemove: () -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = colors.surface), shape = RoundedCornerShape(SanvyaRadius.radiusLg)) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(
                    value = line.description,
                    onValueChange = { onChange(line.copy(description = it)) },
                    label = { Text(S.Receipts.reviewDescription(sRes())) },
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
                IconButton(onClick = onRemove) { Icon(Icons.Default.Close, contentDescription = S.Receipts.reviewRemoveLine(sRes()), tint = colors.text2) }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(
                    value = line.quantity?.let { (it / 1000.0).toString() } ?: "",
                    onValueChange = { v ->
                        val n = v.trim().toDoubleOrNull()
                        onChange(line.copy(quantity = if (v.isBlank() || n == null) null else Math.round(n * 1000)))
                    },
                    label = { Text(S.Receipts.reviewQty(sRes())) },
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
                OutlinedTextField(
                    value = formatMajor(line.amount, digits),
                    onValueChange = { v ->
                        val minor = parseMajor(v, digits) ?: 0L
                        onChange(line.copy(amount = if (line.kind == "discount") -Math.abs(minor) else Math.abs(minor)))
                    },
                    label = { Text(S.Receipts.reviewAmount(sRes())) },
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                LINE_KINDS.forEach { k ->
                    FilterChip(
                        selected = line.kind == k,
                        onClick = {
                            val amount = if (k == "discount") -Math.abs(line.amount) else Math.abs(line.amount)
                            onChange(line.copy(kind = k, amount = amount))
                        },
                        label = { Text(k.replace("_", " ")) },
                    )
                }
            }
        }
    }
}

private fun formatMajor(minor: Long, digits: Int): String {
    val scale = Math.pow(10.0, digits.toDouble())
    return String.format(Locale.ROOT, "%.${digits}f", minor / scale)
}

private fun parseMajor(text: String, digits: Int): Long? {
    val n = text.trim().replace(",", ".").toDoubleOrNull() ?: return if (text.isBlank()) null else 0L
    val scale = Math.pow(10.0, digits.toDouble())
    return Math.round(n * scale)
}

private fun formatMoney(minor: Long, currency: String): String {
    // `toMajor`, not `/ 100.0`: this is the receipt review's own formatter and
    // the receipt's currency is whatever was printed on it, not the user's.
    val major = toMajor(money(minor, currency))
    return try {
        val fmt = NumberFormat.getCurrencyInstance(Locale.ROOT)
        fmt.currency = java.util.Currency.getInstance(currency)
        fmt.format(major)
    } catch (e: Exception) {
        "$major $currency"
    }
}

/**
 * Pick an existing group, or name a new one.
 *
 * Web uses a `<select>` whose empty option means "create a new group"; the same
 * shape reads better on a phone as a chip row, so the "new group" field appears
 * when nothing is selected rather than behind a placeholder option.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SplitGroupPicker(
    groups: List<com.sanvya.app.data.repository.SplitGroup>,
    groupId: String,
    newGroupName: String,
    onPickGroup: (String) -> Unit,
    onNewGroupName: (String) -> Unit,
) {
    val res = sRes()
    val colors = LocalSanvyaColors.current
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(S.Receipts.reviewGroup(res), fontSize = 12.sp, color = colors.text2)
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            SanvyaChip(
                label = S.Receipts.reviewNewGroup(res),
                active = groupId.isEmpty(),
                onClick = { onPickGroup("") },
            )
            groups.forEach { g ->
                SanvyaChip(label = g.name, active = groupId == g.id, onClick = { onPickGroup(g.id) })
            }
        }
        if (groupId.isEmpty()) {
            Text(S.Receipts.reviewNewGroupName(res), fontSize = 12.sp, color = colors.text2)
            SanvyaInput(
                value = newGroupName,
                onValueChange = onNewGroupName,
                modifier = Modifier.fillMaxWidth(),
                placeholder = S.Receipts.reviewNewGroupPlaceholder(res),
            )
        }
        Text(S.Receipts.reviewSplitNote(res), fontSize = 11.sp, color = colors.text2)
    }
}
