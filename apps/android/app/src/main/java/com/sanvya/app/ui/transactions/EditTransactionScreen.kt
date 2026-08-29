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
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaChip
import com.sanvya.app.ui.components.SanvyaPage
import com.sanvya.app.ui.formatMoneyUnmasked

/**
 * Edit transaction — ported from transactions/[id]/edit/page.tsx per
 * docs/mobile/screen-specs/transactions.md. The edit-history sheet and the
 * split-expense banner, deferred by the first port, are both here now.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditTransactionScreen(
    onBack: () -> Unit = {},
    onSaved: () -> Unit = {},
    onDeleted: () -> Unit = {},
    /** The group-detail route, opened from the split banner -- web's link out
     * to /groups/[id] from the same card. */
    onOpenGroup: (String) -> Unit = {},
    viewModel: EditTransactionViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val accounts by viewModel.accounts.collectAsState()
    val account by viewModel.account.collectAsState()
    val relevantCategories by viewModel.relevantCategories.collectAsState()
    val relevantPaymentMethods by viewModel.relevantPaymentMethods.collectAsState()
    val labelOptions by viewModel.labels.collectAsState()
    val total by viewModel.total.collectAsState()
    val categories by viewModel.categories.collectAsState()
    val paymentMethods by viewModel.paymentMethods.collectAsState()
    val split by viewModel.split.collectAsState()
    val history by viewModel.history.collectAsState()
    val myUserId by viewModel.myUserId.collectAsState()
    val colors = LocalSanvyaColors.current

    LaunchedEffect(uiState.saved) { if (uiState.saved) onSaved() }
    LaunchedEffect(uiState.deleted) { if (uiState.deleted) onDeleted() }

    SanvyaPage(
        title = S.Transactions.editTitle(sRes()),
        action = {
            // Web hides this behind a kebab with exactly one item. A chip is
            // the native equivalent and the convention this app already
            // settled on (see GroupDetailScreen, where the same kebab became a
            // chip row) -- a one-item overflow menu is a tap nobody needs.
            // Hidden entirely when nothing has been recorded yet, matching
            // web's `{audit.length > 0 && ...}`.
            if (history.isNotEmpty()) {
                SanvyaChip(
                    label = S.Transactions.viewHistory(sRes()),
                    active = false,
                    onClick = { viewModel.setShowHistory(true) },
                )
            }
        },
    ) {
        if (!uiState.loaded) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(S.Transactions.loading(sRes()), color = colors.text2)
            }
            return@SanvyaPage
        }

        Column(
            modifier = Modifier.fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            SplitBanner(split = split, myUserId = myUserId, onOpenGroup = onOpenGroup)

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("expense", "income", "transfer").forEach { tp ->
                    FilterChip(
                        selected = tp == uiState.type,
                        onClick = { viewModel.setType(tp) },
                        // The translated type name, not the KEY capitalised --
                        // `tp.replaceFirstChar {}` rendered "Expense"/"Income"
                        // in every language.
                        label = { Text(txTypeLabel(tp)) },
                        modifier = Modifier.weight(1f),
                    )
                }
            }

            Text(S.Transactions.account(sRes()), fontSize = 13.sp, color = colors.text2)
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
                    label = { Text(S.Transactions.amountCurrency(sRes(), uiState.currency)) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.fillMaxWidth(),
                )
            } else {
                // Web's amount card: the running total as the headline, the
                // item rows that feed it underneath. The rows each show a part;
                // this is the only place the edited transaction's new total
                // appears before it is saved.
                SanvyaCard(modifier = Modifier.fillMaxWidth(), padding = PaddingValues(22.dp)) {
                    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        Column {
                            Text(
                                if (uiState.items.size > 1) {
                                    S.Transactions.amountWithItems(sRes())
                                } else {
                                    S.Transactions.amount(sRes())
                                },
                                fontSize = 13.sp,
                                color = colors.text2,
                            )
                            Text(
                                // Unmasked: the user is editing this number,
                                // and the hide-amounts mask would make the form
                                // unusable. Web reaches past `useMoneyFmt` here
                                // for the same reason.
                                formatMoneyUnmasked(total),
                                fontSize = 40.sp,
                                fontWeight = FontWeight.Bold,
                                // Web's edit page has only the two colours --
                                // it draws the card for expense and income
                                // only, never for a transfer.
                                color = if (uiState.type == "expense") colors.negative else colors.positive,
                            )
                        }
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            uiState.items.forEachIndexed { idx, item ->
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                    OutlinedTextField(
                                        value = item.description,
                                        onValueChange = { viewModel.updateItem(item.id, description = it) },
                                        placeholder = {
                                            Text(
                                                if (uiState.items.size > 1) {
                                                    S.Transactions.item(sRes(), idx + 1)
                                                } else {
                                                    S.Transactions.whatFor(sRes())
                                                },
                                            )
                                        },
                                        modifier = Modifier.weight(1f),
                                    )
                                    OutlinedTextField(
                                        value = item.value,
                                        onValueChange = { viewModel.updateItem(item.id, value = it.filter { c -> c.isDigit() || c == '.' }) },
                                        placeholder = { Text(AMOUNT_PLACEHOLDER) },
                                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                                        modifier = Modifier.width(120.dp),
                                    )
                                    if (uiState.items.size > 1) {
                                        TextButton(onClick = { viewModel.removeItem(item.id) }) {
                                            Text("×", color = colors.text2)
                                        }
                                    }
                                }
                            }
                            TextButton(onClick = { viewModel.addItem() }) {
                                Text(S.Transactions.addItemSplit(sRes()))
                            }
                        }
                    }
                }

                Text(S.Transactions.category(sRes()), fontSize = 13.sp, color = colors.text2)
                CategoryPicker(
                    categories = relevantCategories,
                    selectedId = uiState.categoryId,
                    onSelect = viewModel::setCategoryId,
                )

                if (relevantPaymentMethods.isNotEmpty()) {
                    Text(S.Transactions.paymentMethod(sRes()), fontSize = 13.sp, color = colors.text2)
                    ChipRow(
                        options = relevantPaymentMethods.map { it.id },
                        selected = uiState.paymentMethod,
                        label = { id -> relevantPaymentMethods.find { it.id == id }?.label ?: "" },
                        onSelect = viewModel::setPaymentMethod,
                        colors = colors,
                    )
                }
            }

            Text(S.Transactions.labels(sRes()), fontSize = 13.sp, color = colors.text2)
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
                label = { Text(S.Transactions.note(sRes())) },
                // See EditTransactionUiState.noteLocked: an envelope this
                // session cannot open is shown (web parity) but must not be
                // editable, because editing it destroys the note silently.
                readOnly = uiState.noteLocked,
                supportingText = if (uiState.noteLocked) {
                    { Text(S.Security.lockedNoteHint(sRes()), fontSize = 12.sp) }
                } else {
                    null
                },
                modifier = Modifier.fillMaxWidth(),
            )

            DateTimeField(value = uiState.occurredAt, onChange = viewModel::setOccurredAt)

            uiState.error?.let {
                Text(it, color = colors.negative, fontSize = 13.sp)
            }

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Button(onClick = { viewModel.save() }, enabled = !uiState.saving) {
                    Text(if (uiState.saving) S.Transactions.saving(sRes()) else S.Transactions.saveChanges(sRes()))
                }
                OutlinedButton(onClick = onBack) { Text(S.Transactions.cancel(sRes())) }
                Spacer(Modifier.weight(1f))
                TextButton(onClick = { viewModel.setConfirmDelete(true) }) {
                    Text(S.Transactions.delete(sRes()), color = colors.negative)
                }
            }
        }

        EditHistorySheet(
            open = uiState.showHistory,
            onClose = { viewModel.setShowHistory(false) },
            entries = history,
            currency = uiState.currency,
            categories = categories,
            accounts = accounts,
            paymentMethods = paymentMethods,
        )

        if (uiState.confirmDelete) {
            AlertDialog(
                onDismissRequest = { if (!uiState.deleting) viewModel.setConfirmDelete(false) },
                title = { Text(S.Transactions.deleteConfirmTitle(sRes()), color = colors.negative) },
                text = { Text("This can't be undone from here.", fontSize = 14.sp, color = colors.text2) },
                confirmButton = {
                    TextButton(onClick = { viewModel.delete() }, enabled = !uiState.deleting) {
                        Text(S.Transactions.delete(sRes()), color = colors.negative)
                    }
                },
                dismissButton = {
                    TextButton(onClick = { viewModel.setConfirmDelete(false) }, enabled = !uiState.deleting) { Text(S.Transactions.cancel(sRes())) }
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
