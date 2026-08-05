package com.sanvya.app.ui.transactions

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.ui.accounts.ChipRow

/**
 * Edit transaction — ported from transactions/[id]/edit/page.tsx per
 * docs/mobile/screen-specs/transactions.md. Edit-history and the split
 * SplitBanner are explicitly deferred (see spec's Scope section).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditTransactionScreen(
    onBack: () -> Unit = {},
    onSaved: () -> Unit = {},
    onDeleted: () -> Unit = {},
    viewModel: EditTransactionViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val accounts by viewModel.accounts.collectAsState()
    val account by viewModel.account.collectAsState()
    val relevantCategories by viewModel.relevantCategories.collectAsState()
    val relevantPaymentMethods by viewModel.relevantPaymentMethods.collectAsState()
    val labelOptions by viewModel.labels.collectAsState()
    val colors = LocalSanvyaColors.current

    LaunchedEffect(uiState.saved) { if (uiState.saved) onSaved() }
    LaunchedEffect(uiState.deleted) { if (uiState.deleted) onDeleted() }

    Scaffold(
        containerColor = colors.bg,
        topBar = {
            TopAppBar(
                title = { Text("Edit transaction", fontWeight = FontWeight.Bold, color = colors.text) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = colors.text2)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.bg),
            )
        },
    ) { padding ->
        if (!uiState.loaded) {
            Box(Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("Loading…", color = colors.text2)
            }
            return@Scaffold
        }

        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("expense", "income", "transfer").forEach { tp ->
                    FilterChip(
                        selected = tp == uiState.type,
                        onClick = { viewModel.setType(tp) },
                        label = { Text(tp.replaceFirstChar { it.uppercase() }) },
                        modifier = Modifier.weight(1f),
                    )
                }
            }

            Text("Account", fontSize = 13.sp, color = colors.text2)
            ChipRow(
                options = accounts.map { it.id },
                selected = uiState.accountId,
                label = { id -> accounts.find { it.id == id }?.name ?: "" },
                onSelect = viewModel::setAccountId,
                colors = colors,
            )

            if (uiState.type == "transfer") {
                OutlinedTextField(
                    value = uiState.transferAmount,
                    onValueChange = { viewModel.setTransferAmount(it.filter { c -> c.isDigit() || c == '.' }) },
                    label = { Text("Amount (${uiState.currency})") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.fillMaxWidth(),
                )
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    uiState.items.forEachIndexed { idx, item ->
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            OutlinedTextField(
                                value = item.description,
                                onValueChange = { viewModel.updateItem(item.id, description = it) },
                                placeholder = { Text(if (uiState.items.size > 1) "Item ${idx + 1}" else "What for?") },
                                modifier = Modifier.weight(1f),
                            )
                            OutlinedTextField(
                                value = item.value,
                                onValueChange = { viewModel.updateItem(item.id, value = it.filter { c -> c.isDigit() || c == '.' }) },
                                placeholder = { Text("0.00") },
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                                modifier = Modifier.width(120.dp),
                            )
                            if (uiState.items.size > 1) {
                                TextButton(onClick = { viewModel.removeItem(item.id) }) { Text("×") }
                            }
                        }
                    }
                    TextButton(onClick = { viewModel.addItem() }) { Text("+ Add item") }
                }

                Text("Category", fontSize = 13.sp, color = colors.text2)
                CategoryPicker(
                    categories = relevantCategories,
                    selectedId = uiState.categoryId,
                    onSelect = viewModel::setCategoryId,
                )

                if (relevantPaymentMethods.isNotEmpty()) {
                    Text("Payment method", fontSize = 13.sp, color = colors.text2)
                    ChipRow(
                        options = relevantPaymentMethods.map { it.id },
                        selected = uiState.paymentMethod,
                        label = { id -> relevantPaymentMethods.find { it.id == id }?.label ?: "" },
                        onSelect = viewModel::setPaymentMethod,
                        colors = colors,
                    )
                }
            }

            Text("Labels", fontSize = 13.sp, color = colors.text2)
            LabelPickerRow(
                available = labelOptions.map { it.name },
                selected = uiState.selectedLabels,
                onToggle = viewModel::toggleLabel,
                onAddNew = viewModel::addNewLabel,
                colors = colors,
            )

            if (uiState.type == "expense") {
                Text("Intent (mindfulness)", fontSize = 13.sp, color = colors.text2)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    IntentChip("Untagged", selected = uiState.intent == null, color = colors.text) { viewModel.setIntent(null) }
                    IntentChip("Need", selected = uiState.intent == "need", color = colors.positive) { viewModel.setIntent("need") }
                    IntentChip("Greed", selected = uiState.intent == "greed", color = colors.negative) { viewModel.setIntent("greed") }
                }
            }

            OutlinedTextField(
                value = uiState.note,
                onValueChange = viewModel::setNote,
                label = { Text("Note") },
                modifier = Modifier.fillMaxWidth(),
            )

            DateTimeField(value = uiState.occurredAt, onChange = viewModel::setOccurredAt)

            uiState.error?.let {
                Text(it, color = colors.negative, fontSize = 13.sp)
            }

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Button(onClick = { viewModel.save() }, enabled = !uiState.saving) {
                    Text(if (uiState.saving) "Saving…" else "Save changes")
                }
                OutlinedButton(onClick = onBack) { Text("Cancel") }
                Spacer(Modifier.weight(1f))
                TextButton(onClick = { viewModel.setConfirmDelete(true) }) {
                    Text("Delete", color = colors.negative)
                }
            }
        }

        if (uiState.confirmDelete) {
            AlertDialog(
                onDismissRequest = { if (!uiState.deleting) viewModel.setConfirmDelete(false) },
                title = { Text("Delete this transaction?", color = colors.negative) },
                text = { Text("This can't be undone from here.", fontSize = 14.sp, color = colors.text2) },
                confirmButton = {
                    TextButton(onClick = { viewModel.delete() }, enabled = !uiState.deleting) {
                        Text("Delete", color = colors.negative)
                    }
                },
                dismissButton = {
                    TextButton(onClick = { viewModel.setConfirmDelete(false) }, enabled = !uiState.deleting) { Text("Cancel") }
                },
            )
        }
    }
}

@Composable
private fun IntentChip(label: String, selected: Boolean, color: androidx.compose.ui.graphics.Color, onClick: () -> Unit) {
    val colors = LocalSanvyaColors.current
    AssistChip(
        onClick = onClick,
        label = { Text(label, fontSize = 12.sp) },
        colors = AssistChipDefaults.assistChipColors(
            containerColor = if (selected) color.copy(alpha = 0.18f) else colors.surface2,
            labelColor = if (selected) color else colors.text,
        ),
    )
}
