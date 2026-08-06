package com.sanvya.app.ui.loans

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaRadius
import com.sanvya.app.ui.budgets.DatePickerDialogSimple
import com.sanvya.app.ui.budgets.TimePickerDialogSimple
import com.sanvya.app.ui.budgets.localToUtcTime
import kotlinx.coroutines.launch

/**
 * Loan detail (summary, next-EMI/remaining/interest strip, auto-mark
 * toggle, amortization/variable schedule, mark-paid dialog, edit/delete).
 * Ported from apps/web/app/loans/[id]/page.tsx per docs/mobile/
 * screen-specs/loans.md (task #27). New file -- Android had no per-loan
 * detail screen at all before this pass.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LoanDetailScreen(
    loanId: String,
    onBack: () -> Unit = {},
    onDeleted: () -> Unit = {},
    viewModel: LoanDetailViewModel = viewModel(),
) {
    LaunchedEffect(loanId) { viewModel.select(loanId) }
    val ui by viewModel.uiModel.collectAsState()
    val markPaidAccounts by viewModel.markPaidAccounts.collectAsState()
    val defaultFundingAccountId by viewModel.defaultFundingAccountId.collectAsState()
    val colors = LocalSanvyaColors.current
    val scope = rememberCoroutineScope()

    var editing by rememberSaveable(loanId) { mutableStateOf(false) }
    var showDeleteConfirm by rememberSaveable(loanId) { mutableStateOf(false) }
    var payForMonth by rememberSaveable(loanId) { mutableStateOf<Int?>(null) }

    val model = ui
    if (model == null) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        return
    }

    if (editing) {
        EditLoanScreen(model = model, onBack = { editing = false }, onSaved = { editing = false }, viewModel = viewModel)
        return
    }

    Scaffold(
        containerColor = colors.bg,
        topBar = {
            TopAppBar(
                title = { Text(model.lender, fontWeight = FontWeight.Bold, color = colors.text) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = colors.text2)
                    }
                },
                actions = {
                    TextButton(onClick = { editing = true }) { Text("Edit") }
                    TextButton(onClick = { showDeleteConfirm = true }) { Text("Delete", color = colors.negative) }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.bg),
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Summary cards
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SummaryCard("Principal", model.principalFormatted, Modifier.weight(1f))
                SummaryCard("Monthly EMI", model.emiFormatted, Modifier.weight(1f))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SummaryCard("Interest rate", model.interestRateText, Modifier.weight(1f))
                SummaryCard("EMIs paid", model.emisPaidText, Modifier.weight(1f))
            }

            Card(colors = CardDefaults.cardColors(containerColor = colors.surface), shape = RoundedCornerShape(SanvyaRadius.radiusLg)) {
                Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                        Column {
                            Text("Next EMI due", fontSize = 12.sp, color = colors.text2)
                            Text(model.nextEmiDueFormatted, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = colors.text)
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            Text("Remaining", fontSize = 12.sp, color = colors.text2)
                            Text(model.remainingText, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = colors.text)
                        }
                    }
                    if (model.isVariable) {
                        model.variablePaidFormatted?.let {
                            Column {
                                Text("Paid so far", fontSize = 12.sp, color = colors.text2)
                                Text(it, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = colors.text)
                            }
                        }
                    } else {
                        model.totalInterestFormatted?.let {
                            Column {
                                Text("Total interest (schedule)", fontSize = 12.sp, color = colors.text2)
                                Text(it, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = colors.negative)
                            }
                        }
                    }
                    if (model.hasTenure) {
                        Box(modifier = Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(50)).background(colors.border)) {
                            Box(
                                modifier = Modifier.fillMaxWidth(fraction = model.progress.coerceIn(0.0, 1.0).toFloat())
                                    .fillMaxHeight().clip(RoundedCornerShape(50)).background(colors.accent),
                            )
                        }
                    }
                }
            }

            if (model.rows.isNotEmpty()) {
                Card(colors = CardDefaults.cardColors(containerColor = colors.surface), shape = RoundedCornerShape(SanvyaRadius.radius)) {
                    Row(
                        modifier = Modifier.padding(16.dp).fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("Auto-mark past-due EMIs paid", fontWeight = FontWeight.SemiBold, fontSize = 14.sp, color = colors.text)
                            Text(
                                (if (model.autoMarkPaid) "On" else "Off") + (if (model.autoMarkDueDayText.isNotBlank()) " · ${model.autoMarkDueDayText}" else ""),
                                fontSize = 12.sp, color = colors.text2,
                            )
                        }
                        Switch(checked = model.autoMarkPaid, onCheckedChange = { viewModel.toggleAutoMark() })
                    }
                }
            }

            Text(if (model.isVariable) "Month-by-month EMIs" else "Amortization schedule", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = colors.text2)

            if (model.rows.isEmpty()) {
                Text(if (model.emptyScheduleHint) "Add an interest rate, tenure, or EMI to see a payoff schedule." else "No EMIs yet.", fontSize = 13.sp, color = colors.text2)
            } else {
                model.rows.forEach { row ->
                    EmiRowCard(
                        row = row,
                        isVariable = model.isVariable,
                        currency = model.currency,
                        onMark = { payForMonth = row.month },
                        onUnmark = { viewModel.unmarkPaid(row.month) },
                        onSaveVariableAmount = { major -> viewModel.setVariableAmount(row.month, major, model.currency) },
                    )
                }
            }
        }
    }

    payForMonth?.let { month ->
        val row = model.rows.find { it.month == month }
        val emiMinorForPay = row?.emiMinor ?: 0L
        MarkPaidDialog(
            month = month,
            dueLabel = row?.dueFormatted ?: "",
            emiAmountMinor = emiMinorForPay,
            emiAmountFormatted = if (emiMinorForPay > 0) row?.amountFormatted else null,
            currency = model.currency,
            accounts = markPaidAccounts,
            defaultAccountId = defaultFundingAccountId,
            onDismiss = { payForMonth = null },
            onConfirm = { paidOn, accountId ->
                viewModel.markPaid(month, paidOn, accountId, emiMinorForPay, model.currency)
                payForMonth = null
            },
        )
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("Delete ${model.lender}?") },
            text = { Text("This removes the loan and its EMI history.") },
            confirmButton = {
                TextButton(onClick = { viewModel.delete(onDeleted); showDeleteConfirm = false }) { Text("Delete", color = colors.negative) }
            },
            dismissButton = { TextButton(onClick = { showDeleteConfirm = false }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun SummaryCard(label: String, value: String, modifier: Modifier = Modifier) {
    val colors = LocalSanvyaColors.current
    Card(modifier = modifier, colors = CardDefaults.cardColors(containerColor = colors.surface), shape = RoundedCornerShape(SanvyaRadius.radius)) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(label, fontSize = 11.sp, color = colors.text2)
            Text(value, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = colors.text)
        }
    }
}

@Composable
private fun EmiRowCard(
    row: EmiRowUiModel,
    isVariable: Boolean,
    currency: String,
    onMark: () -> Unit,
    onUnmark: () -> Unit,
    onSaveVariableAmount: (String) -> Unit,
) {
    val colors = LocalSanvyaColors.current
    var amountText by rememberSaveable(row.month, row.rawAmountMajor) { mutableStateOf(row.rawAmountMajor) }
    Card(colors = CardDefaults.cardColors(containerColor = colors.surface), shape = RoundedCornerShape(SanvyaRadius.radius)) {
        Column {
            Row(modifier = Modifier.padding(14.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                EmiStateDot(row.state)
                Column(modifier = Modifier.weight(1f)) {
                    Text("EMI #${row.month}", fontSize = 11.sp, color = colors.text2)
                    Text(row.amountFormatted, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = colors.text)
                }
                Column(horizontalAlignment = Alignment.End) {
                    when (row.state) {
                        EmiRowState.AUTO_MARKED -> Chip("Auto-marked", colors.positive)
                        EmiRowState.PAID -> Chip("Paid", colors.positive, onClick = onUnmark)
                        EmiRowState.DUE -> Chip("Mark paid", colors.warning, onClick = onMark)
                    }
                    Text(
                        if (row.state != EmiRowState.DUE) "on ${row.paidOnOrDueFormatted}" else "due ${row.dueFormatted}",
                        fontSize = 11.sp, color = colors.text2,
                    )
                }
            }
            HorizontalDivider()
            if (isVariable) {
                Row(modifier = Modifier.padding(14.dp).fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Text("EMI this month", fontSize = 11.sp, color = colors.text2)
                    OutlinedTextField(
                        value = amountText,
                        onValueChange = { amountText = it },
                        modifier = Modifier.width(130.dp),
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        trailingIcon = {
                            TextButton(onClick = { onSaveVariableAmount(amountText) }) { Text("Save", fontSize = 12.sp) }
                        },
                    )
                }
            } else {
                Row(modifier = Modifier.padding(14.dp).fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Column {
                        Text("Principal", fontSize = 11.sp, color = colors.text2)
                        Text(row.principalFormatted ?: "—", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = colors.text)
                    }
                    if (row.hasInterest) {
                        Column(horizontalAlignment = Alignment.End) {
                            Text("Interest", fontSize = 11.sp, color = colors.text2)
                            Text(row.interestFormatted ?: "—", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = colors.negative)
                        }
                    } else {
                        Column(horizontalAlignment = Alignment.End) {
                            Text("Balance", fontSize = 11.sp, color = colors.text2)
                            Text(row.balanceFormatted ?: "—", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = colors.text)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun EmiStateDot(state: EmiRowState) {
    val colors = LocalSanvyaColors.current
    val (bg, ch) = when (state) {
        EmiRowState.PAID, EmiRowState.AUTO_MARKED -> colors.positive to "✓"
        EmiRowState.DUE -> colors.warning to "!"
    }
    Box(
        modifier = Modifier.size(24.dp).clip(RoundedCornerShape(50)).background(bg),
        contentAlignment = Alignment.Center,
    ) { Text(ch, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = androidx.compose.ui.graphics.Color.White) }
}

@Composable
private fun Chip(text: String, tint: androidx.compose.ui.graphics.Color, onClick: (() -> Unit)? = null) {
    var modifier = Modifier.clip(RoundedCornerShape(50)).background(tint.copy(alpha = 0.15f))
    if (onClick != null) modifier = modifier.clickable(onClick = onClick)
    Box(modifier = modifier.padding(horizontal = 9.dp, vertical = 3.dp)) {
        Text(text, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = tint)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MarkPaidDialog(
    month: Int,
    dueLabel: String,
    emiAmountMinor: Long,
    emiAmountFormatted: String?,
    currency: String,
    accounts: List<MarkPaidAccountOption>,
    defaultAccountId: String?,
    onDismiss: () -> Unit,
    onConfirm: (paidOn: String, accountId: String?) -> Unit,
) {
    val colors = LocalSanvyaColors.current
    var paidOn by rememberSaveable(month) { mutableStateOf(java.time.LocalDate.now().toString()) }
    var accountId by rememberSaveable(month) { mutableStateOf(defaultAccountId ?: "") }
    var showDatePicker by rememberSaveable(month) { mutableStateOf(false) }
    var menuExpanded by rememberSaveable(month) { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Mark EMI #$month paid") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    if (dueLabel.isNotBlank() && emiAmountFormatted != null) "Due $dueLabel · $emiAmountFormatted"
                    else if (emiAmountFormatted != null) emiAmountFormatted
                    else if (dueLabel.isNotBlank()) "Due $dueLabel"
                    else "",
                    fontSize = 13.sp, color = colors.text2,
                )
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Paid on", fontSize = 13.sp, color = colors.text2)
                    TextButton(onClick = { showDatePicker = true }) { Text(paidOn) }
                }
                val selected = accounts.find { it.id == accountId }
                ExposedDropdownMenuBox(expanded = menuExpanded, onExpandedChange = { menuExpanded = it }) {
                    OutlinedTextField(
                        value = selected?.let { "${it.name} · ${it.balanceFormatted}" } ?: "Don't record",
                        onValueChange = {}, readOnly = true, label = { Text("Also record as an expense") },
                        modifier = Modifier.fillMaxWidth().menuAnchor(),
                    )
                    ExposedDropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                        DropdownMenuItem(text = { Text("Don't record") }, onClick = { accountId = ""; menuExpanded = false })
                        accounts.forEach { a ->
                            DropdownMenuItem(text = { Text("${a.name} · ${a.balanceFormatted}") }, onClick = { accountId = a.id; menuExpanded = false })
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(paidOn, accountId.ifBlank { null }) }) { Text(if (accountId.isNotBlank()) "Mark paid & record" else "Mark paid") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )

    if (showDatePicker) {
        DatePickerDialogSimple(onDismiss = { showDatePicker = false }, onConfirm = { paidOn = it; showDatePicker = false })
    }
}
