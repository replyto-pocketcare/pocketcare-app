package com.sanvya.app.ui.accounts

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.ui.components.SanvyaPage
import com.sanvya.app.ui.components.ColorSwatchRow

/**
 * Edit account — ported from apps/web/app/accounts/[id]/edit/page.tsx per
 * docs/mobile/screen-specs/accounts.md: name/type/color/include/allow-neg
 * editing, delete (cascade-or-keep, both soft-delete), and the balance-
 * adjustment tool (direct vs record-as-transaction).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditAccountScreen(
    onBack: () -> Unit = {},
    onSaved: () -> Unit = {},
    onDeleted: () -> Unit = {},
    viewModel: EditAccountViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val colors = LocalSanvyaColors.current

    LaunchedEffect(uiState.saved) { if (uiState.saved) onSaved() }
    LaunchedEffect(uiState.deleted) { if (uiState.deleted) onDeleted() }

    SanvyaPage(
        title = S.Accounts.editTitle(sRes()),
        action = {

        },
    ) {
        if (!uiState.loaded) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(S.Accounts.loading(sRes()), color = colors.text2)
            }
            return@SanvyaPage
        }

        Column(
            modifier = Modifier.fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            OutlinedTextField(
                value = uiState.name,
                onValueChange = viewModel::setName,
                label = { Text(S.Accounts.accountName(sRes())) },
                modifier = Modifier.fillMaxWidth(),
            )

            Text(S.Accounts.typeLabel(sRes()), fontSize = 13.sp, color = colors.text2)
            ChipRow(options = ACCOUNT_TYPES, selected = uiState.type,
                label = { it.replace("_", " ").replaceFirstChar { c -> c.uppercase() } },
                onSelect = viewModel::setType, colors = colors)

            Text(S.Accounts.colour(sRes()), fontSize = 13.sp, color = colors.text2)
            ColorSwatchRow(selected = uiState.color) { viewModel.setColor(it) }

            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Checkbox(checked = uiState.includeInNetWorth, onCheckedChange = viewModel::setIncludeInNetWorth)
                Text(S.Accounts.includeShort(sRes()), fontSize = 14.sp, color = colors.text)
            }
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Checkbox(checked = uiState.allowNegative, onCheckedChange = viewModel::setAllowNegative)
                Column {
                    Text("Allow negative balance", fontSize = 14.sp, color = colors.text)
                    Text(
                        if (uiState.allowNegative) "This account can go below zero without a warning."
                        else "You'll be warned before this account would go below zero.",
                        fontSize = 12.sp, color = colors.text2,
                    )
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Button(onClick = { viewModel.save() }, enabled = uiState.name.isNotBlank()) { Text(S.Accounts.saveChanges(sRes())) }
                OutlinedButton(onClick = onBack) { Text(S.Accounts.cancel(sRes())) }
                Spacer(Modifier.weight(1f))
                TextButton(onClick = { viewModel.setConfirmDelete(true) }) {
                    Text(S.Accounts.delete(sRes()), color = colors.negative)
                }
            }

            HorizontalDivider(Modifier.padding(vertical = 6.dp))

            // Balance-adjustment tool.
            Card(
                colors = CardDefaults.cardColors(containerColor = colors.surface),
                shape = RoundedCornerShape(20.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Adjust balance", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = colors.text)
                    Text(
                        "Current balance: ${uiState.currentBalanceFormatted}",
                        fontSize = 13.sp, color = colors.text2,
                    )
                    OutlinedTextField(
                        value = uiState.targetBalance,
                        onValueChange = viewModel::setTargetBalance,
                        label = { Text(S.Accounts.newBalance(sRes())) },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        AssistChip(
                            onClick = { viewModel.setBalanceMode(BalanceMode.Direct) },
                            label = { Text(S.Accounts.changeDirectly(sRes()), fontSize = 12.sp) },
                            colors = AssistChipDefaults.assistChipColors(
                                containerColor = if (uiState.balanceMode == BalanceMode.Direct) colors.accent else colors.surface2,
                                labelColor = if (uiState.balanceMode == BalanceMode.Direct) Color.White else colors.text,
                            ),
                        )
                        AssistChip(
                            onClick = { viewModel.setBalanceMode(BalanceMode.Transaction) },
                            label = { Text("Record as transaction", fontSize = 12.sp) },
                            colors = AssistChipDefaults.assistChipColors(
                                containerColor = if (uiState.balanceMode == BalanceMode.Transaction) colors.accent else colors.surface2,
                                labelColor = if (uiState.balanceMode == BalanceMode.Transaction) Color.White else colors.text,
                            ),
                        )
                    }
                    Text(
                        if (uiState.balanceMode == BalanceMode.Direct)
                            "A silent correction entry, no category, doesn't show up in insights."
                        else "A real income/expense entry, appears in history and insights.",
                        fontSize = 12.sp, color = colors.text2,
                    )
                    OutlinedButton(
                        onClick = { viewModel.applyBalance() },
                        enabled = uiState.currentBalance != null && uiState.targetBalance.isNotEmpty(),
                    ) { Text(S.Accounts.updateBalance(sRes())) }
                    uiState.balanceMessage?.let {
                        Text(it, fontSize = 13.sp, color = colors.text2)
                    }
                }
            }
        }

        if (uiState.confirmDelete) {
            AlertDialog(
                onDismissRequest = { if (!uiState.deleting) viewModel.setConfirmDelete(false) },
                title = { Text(S.Accounts.deleteTitle(sRes()), color = colors.negative) },
                text = {
                    Text(
                        "Deleting keeps your data safe -- this only marks the account (and optionally its transactions) as removed, it isn't a permanent hard delete.",
                        fontSize = 14.sp, color = colors.text2,
                    )
                },
                confirmButton = {
                    Column {
                        Button(onClick = { viewModel.delete(true) }, enabled = !uiState.deleting) { Text(S.Settings.deleteEverything(sRes())) }
                        Spacer(Modifier.height(8.dp))
                        OutlinedButton(onClick = { viewModel.delete(false) }, enabled = !uiState.deleting) { Text("Delete, keep transactions") }
                    }
                },
                dismissButton = {
                    TextButton(onClick = { viewModel.setConfirmDelete(false) }, enabled = !uiState.deleting) { Text(S.Accounts.cancel(sRes())) }
                },
            )
        }
    }
}
