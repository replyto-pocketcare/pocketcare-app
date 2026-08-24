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

    LaunchedEffect(savedTransactionId) {
        savedTransactionId?.let { onSaved(it) }
    }

    Scaffold(
        containerColor = colors.bg,
        topBar = {
            TopAppBar(
                title = { Text("Check the details", fontWeight = FontWeight.Bold, color = colors.text) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = colors.text2) } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.bg),
            )
        },
    ) { padding ->
        if (!loaded) {
            Box(Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            return@Scaffold
        }
        val d = draft
        if (d == null) {
            Box(Modifier.padding(padding).fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                Text(error ?: "That scan is no longer available.", color = colors.text2, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            }
            return@Scaffold
        }

        val digits = 2
        val rec = viewModel.reconcileResult()
        val subs = viewModel.subtotalsResult()
        val balanced = rec?.ok ?: false
        val canSave = balanced && accountId != null && !saving

        LazyColumn(
            modifier = Modifier.padding(padding).fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                Card(colors = CardDefaults.cardColors(containerColor = colors.surface), shape = RoundedCornerShape(SanvyaRadius.radiusLg)) {
                    Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        OutlinedTextField(
                            value = d.merchant ?: "", onValueChange = { viewModel.setMerchant(it) },
                            label = { Text("Merchant") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
                        )
                        OutlinedTextField(
                            value = d.occurredAt ?: "", onValueChange = { viewModel.setOccurredAt(it) },
                            label = { Text("Date (YYYY-MM-DD)") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
                        )
                        Text("Paid from", fontSize = 12.sp, color = colors.text2)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            accounts.forEach { a ->
                                FilterChip(selected = accountId == a.id, onClick = { viewModel.setAccountId(a.id) }, label = { Text(a.name) })
                            }
                        }
                        Text("Category", fontSize = 12.sp, color = colors.text2)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            FilterChip(selected = categoryId == null, onClick = { viewModel.setCategoryId(null) }, label = { Text("Uncategorised") })
                            categories.forEach { c ->
                                FilterChip(selected = categoryId == c.id, onClick = { viewModel.setCategoryId(c.id) }, label = { Text(c.name) })
                            }
                        }
                    }
                }
            }

            item {
                Text("Items & charges", fontWeight = FontWeight.Bold, color = colors.text, fontSize = 15.sp)
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
                            SubtotalRow("Items", s.items, d.currency)
                            if (s.discount != 0L) SubtotalRow("Discount", s.discount, d.currency)
                            if (s.serviceCharge != 0L) SubtotalRow("Service charge", s.serviceCharge, d.currency)
                            if (s.tax != 0L) SubtotalRow("Tax", s.tax, d.currency)
                            if (s.tip != 0L) SubtotalRow("Tip", s.tip, d.currency)
                        }
                        OutlinedTextField(
                            value = d.total?.let { formatMajor(it, digits) } ?: "",
                            onValueChange = { v -> viewModel.setTotal(parseMajor(v, digits)) },
                            label = { Text("Total on the receipt") },
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
                                        else if (r.reason == "missing_total") "Enter the total printed on the receipt."
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
                        // "Split this bill" is intentionally disabled here --
                        // the itemized split-assignment screen pairs with
                        // automatic split detection (task #63/64), not this
                        // pass. See receipt-scan.md scope note #5.
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            AssistChip(onClick = {}, enabled = false, label = { Text("Split this bill — coming soon") })
                        }
                        error?.let { Text(it, color = colors.negative, fontSize = 12.sp) }
                        Button(onClick = { viewModel.saveAsTransaction() }, enabled = canSave, modifier = Modifier.fillMaxWidth()) {
                            Text(if (saving) "Saving…" else "Save transaction")
                        }
                        if (!balanced) {
                            Text("The lines need to add up to the total before this can be saved.", fontSize = 11.sp, color = colors.text2)
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
                    label = { Text("Description") },
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
                IconButton(onClick = onRemove) { Icon(Icons.Default.Close, contentDescription = "Remove line", tint = colors.text2) }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(
                    value = line.quantity?.let { (it / 1000.0).toString() } ?: "",
                    onValueChange = { v ->
                        val n = v.trim().toDoubleOrNull()
                        onChange(line.copy(quantity = if (v.isBlank() || n == null) null else Math.round(n * 1000)))
                    },
                    label = { Text("Qty") },
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
                OutlinedTextField(
                    value = formatMajor(line.amount, digits),
                    onValueChange = { v ->
                        val minor = parseMajor(v, digits) ?: 0L
                        onChange(line.copy(amount = if (line.kind == "discount") -Math.abs(minor) else Math.abs(minor)))
                    },
                    label = { Text("Amount") },
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
    return try {
        val fmt = NumberFormat.getCurrencyInstance(Locale.ROOT)
        fmt.currency = java.util.Currency.getInstance(currency)
        fmt.format(minor / 100.0)
    } catch (e: Exception) {
        "${minor / 100.0} $currency"
    }
}
