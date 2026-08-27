package com.sanvya.app.ui.splits

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaColors
import com.sanvya.app.theme.SanvyaRadius
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.ui.components.SanvyaChip
import com.sanvya.app.ui.components.SanvyaPage

/**
 * Real port of apps/web/app/groups/[id]/page.tsx (task #30). See
 * docs/mobile/screen-specs/splits.md for the deliberate scope cut (equal-
 * split "Add expense" only; invite/itemized deferred).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GroupDetailScreen(
    groupId: String,
    onBack: () -> Unit,
    viewModel: GroupDetailViewModel = viewModel(),
) {
    LaunchedEffect(groupId) { viewModel.select(groupId) }

    val colors = LocalSanvyaColors.current
    val group by viewModel.group.collectAsState()
    val members by viewModel.members.collectAsState()
    val expenses by viewModel.expenses.collectAsState()
    val settlements by viewModel.settlements.collectAsState()
    val loaded by viewModel.loaded.collectAsState()
    var showAddExpense by remember { mutableStateOf(false) }
    var settleTarget by remember { mutableStateOf<MemberUiModel?>(null) }

    SanvyaPage(
        title = group?.name ?: S.Groups.kindGroup(sRes()),
        // The sheet below was fully implemented and UNREACHABLE: nothing ever
        // set `showAddExpense`, and this action was an empty lambda, so a group
        // was read-only on Android while iOS could add to one. Web puts the
        // same button in the same place (`groups/[id]/page.tsx`).
        action = {
            SanvyaChip(
                S.Splits.addExpense(sRes()),
                active = false,
                onClick = { showAddExpense = true },
            )
        },
    ) {
        if (!loaded) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            return@SanvyaPage
        }

        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            item {
                Text(S.Groups.membersTitle(sRes()), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = colors.text2)
            }
            items(members, key = { it.userId }) { m ->
                MemberRow(m, colors) { if (!m.isSelf) settleTarget = m }
            }

            if (expenses.isNotEmpty()) {
                item { Spacer(Modifier.height(4.dp)); Text(S.Groups.expensesTitle(sRes()), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = colors.text2) }
                items(expenses, key = { it.id }) { e ->
                    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                        Column {
                            Text(e.description, color = colors.text, fontWeight = FontWeight.Medium)
                            Text(e.date, fontSize = 11.sp, color = colors.text2)
                        }
                        Text(e.amountFormatted, color = colors.text, fontWeight = FontWeight.Bold)
                    }
                }
            }

            if (settlements.isNotEmpty()) {
                item { Spacer(Modifier.height(4.dp)); Text("Settlements", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = colors.text2) }
                items(settlements, key = { it.id }) { s ->
                    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                        Column {
                            Text("${s.fromName} → ${s.toName}", color = colors.text, fontWeight = FontWeight.Medium, fontSize = 13.sp)
                            Text(s.date, fontSize = 11.sp, color = colors.text2)
                        }
                        Text(s.amountFormatted, color = colors.text2, fontWeight = FontWeight.SemiBold)
                    }
                }
            }

            item { Spacer(Modifier.height(72.dp)) }
        }
    }

    if (showAddExpense) {
        AddExpenseSheet(viewModel = viewModel, members = members, onDismiss = { showAddExpense = false })
    }

    settleTarget?.let { target ->
        SettleUpSheet(viewModel = viewModel, target = target, onDismiss = { viewModel.resetUpiStage(); settleTarget = null })
    }
}

@Composable
private fun MemberRow(m: MemberUiModel, colors: SanvyaColors, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(enabled = !m.isSelf, onClick = onClick).padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(m.name, color = colors.text, fontWeight = FontWeight.Medium)
        val net = m.net
        Text(
            when {
                net == 0L -> S.Groups.settledTitle(sRes())
                net > 0 -> "Owes you ${m.netFormatted}"
                else -> "You owe ${m.netFormatted}"
            },
            fontSize = 13.sp,
            color = if (net == 0L) colors.text2 else if (net > 0) colors.positive else colors.negative,
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AddExpenseSheet(viewModel: GroupDetailViewModel, members: List<MemberUiModel>, onDismiss: () -> Unit) {
    val colors = LocalSanvyaColors.current
    val accounts by viewModel.accounts.collectAsState()
    var description by remember { mutableStateOf("") }
    var amount by remember { mutableStateOf("") }
    var payerId by remember { mutableStateOf(members.firstOrNull { it.isSelf }?.userId ?: members.firstOrNull()?.userId ?: "") }
    var accountId by remember { mutableStateOf(accounts.firstOrNull()?.id) }
    var participants by remember { mutableStateOf(members.map { it.userId }.toSet()) }
    var error by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = colors.surface) {
        Column(Modifier.padding(20.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(S.Splits.addExpense(sRes()), fontWeight = FontWeight.Bold, fontSize = 18.sp, color = colors.text)
            Text("Split equally among the people you select below.", fontSize = 12.sp, color = colors.text2)

            OutlinedTextField(description, { description = it }, label = { Text(S.Receipts.reviewDescription(sRes())) }, singleLine = true, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(amount, { amount = it }, label = { Text(S.Translation.transactionAmount(sRes())) }, singleLine = true, modifier = Modifier.fillMaxWidth())

            Text("Paid by", fontSize = 12.sp, color = colors.text2)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                members.forEach { m ->
                    FilterChip(selected = payerId == m.userId, onClick = { payerId = m.userId }, label = { Text(m.name) })
                }
            }

            if (accounts.isNotEmpty()) {
                Text(S.Receipts.reviewAccount(sRes()), fontSize = 12.sp, color = colors.text2)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    accounts.forEach { a ->
                        FilterChip(selected = accountId == a.id, onClick = { accountId = a.id }, label = { Text(a.name) })
                    }
                }
            }

            Text(S.Transactions.splitBetween(sRes()), fontSize = 12.sp, color = colors.text2)
            Column {
                members.forEach { m ->
                    Row(
                        Modifier.fillMaxWidth().clickable { participants = if (m.userId in participants) participants - m.userId else participants + m.userId }.padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Checkbox(checked = m.userId in participants, onCheckedChange = { checked -> participants = if (checked) participants + m.userId else participants - m.userId })
                        Text(m.name, color = colors.text)
                    }
                }
            }

            error?.let { Text(it, fontSize = 12.sp, color = colors.negative) }

            Button(
                onClick = {
                    saving = true
                    viewModel.addExpense(description, amount, payerId, accountId, participants.toList()) { err ->
                        saving = false
                        error = err
                        if (err == null) onDismiss()
                    }
                },
                enabled = amount.isNotBlank() && payerId.isNotBlank() && participants.isNotEmpty() && !saving,
                modifier = Modifier.fillMaxWidth(),
            ) { Text(if (saving) S.Translation.commonSaving(sRes()) else S.Splits.addExpense(sRes())) }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettleUpSheet(viewModel: GroupDetailViewModel, target: MemberUiModel, onDismiss: () -> Unit) {
    val colors = LocalSanvyaColors.current
    val accounts by viewModel.accounts.collectAsState()
    val upiStage by viewModel.upiStage.collectAsState()
    // direction from the CALLER's perspective: target.net > 0 means they owe
    // us (we "received"), target.net < 0 means we owe them (we "paid").
    val direction = if (target.net >= 0) "received" else "paid"
    var amount by remember { mutableStateOf(String.format("%.2f", kotlin.math.abs(target.net) / 100.0)) }
    var accountId by remember { mutableStateOf(accounts.firstOrNull()?.id) }
    var error by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = colors.surface) {
        Column(Modifier.padding(20.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("Settle up with ${target.name}", fontWeight = FontWeight.Bold, fontSize = 18.sp, color = colors.text)
            OutlinedTextField(amount, { amount = it }, label = { Text(S.Translation.transactionAmount(sRes())) }, singleLine = true, modifier = Modifier.fillMaxWidth())

            if (direction == "paid") {
                Button(
                    onClick = { viewModel.startUpiFetch(target.userId) },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text(S.Payments.payButton(sRes())) }
            }

            if (accounts.isNotEmpty()) {
                Text(S.Translation.settingsAccount(sRes()), fontSize = 12.sp, color = colors.text2)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    accounts.forEach { a ->
                        FilterChip(selected = accountId == a.id, onClick = { accountId = a.id }, label = { Text(a.name) })
                    }
                }
            }

            error?.let { Text(it, fontSize = 12.sp, color = colors.negative) }

            OutlinedButton(
                onClick = {
                    saving = true
                    viewModel.settleManually(target.userId, amount, direction, accountId) { err ->
                        saving = false
                        error = err
                        if (err == null) onDismiss()
                    }
                },
                enabled = amount.isNotBlank() && !saving,
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Mark settled manually") }
        }
    }

    when (val stage = upiStage) {
        is UpiStage.Fetching -> AlertDialog(
            onDismissRequest = {},
            confirmButton = {},
            text = { Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) { CircularProgressIndicator(modifier = Modifier.size(20.dp)); Text(S.Payments.payPreparing(sRes())) } },
        )
        is UpiStage.Ready -> PayViaUpiDialog(
            counterpartyName = target.name,
            vpa = stage.vpa,
            amountMinor = (amount.toDoubleOrNull()?.times(100))?.toLong() ?: kotlin.math.abs(target.net),
            onDismiss = { viewModel.resetUpiStage() },
            onPaid = { ref ->
                viewModel.recordUpiSettlement(target.userId, amount, direction, ref) { err ->
                    viewModel.resetUpiStage()
                    if (err == null) onDismiss()
                }
            },
        )
        is UpiStage.Error -> AlertDialog(
            onDismissRequest = { viewModel.resetUpiStage() },
            title = { Text("Couldn't fetch payment details") },
            text = { Text(if (stage.code == "no_handle") "${target.name} hasn't added a UPI ID yet." else stage.message) },
            confirmButton = { TextButton(onClick = { viewModel.resetUpiStage() }) { Text("OK") } },
        )
        UpiStage.Idle -> {}
    }
}
