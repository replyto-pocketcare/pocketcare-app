package com.sanvya.app.ui.transactions

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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.ui.accounts.ChipRow
import com.sanvya.app.ui.baseCurrencyNow
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.ui.components.SanvyaPage

/**
 * New transaction — ported from transactions/new/page.tsx's regular
 * expense/income/transfer path per docs/mobile/screen-specs/transactions.md.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreateTransactionScreen(
    onBack: () -> Unit = {},
    onSaved: () -> Unit = {},
    onAddAccountFirst: () -> Unit = {},
    viewModel: CreateTransactionViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val accounts by viewModel.accounts.collectAsState()
    val account by viewModel.account.collectAsState()
    val toAccount by viewModel.toAccount.collectAsState()
    val isInvestment by viewModel.isInvestment.collectAsState()
    val relevantCategories by viewModel.relevantCategories.collectAsState()
    val relevantPaymentMethods by viewModel.relevantPaymentMethods.collectAsState()
    val labelOptions by viewModel.labels.collectAsState()
    val colors = LocalSanvyaColors.current

    LaunchedEffect(uiState.saved) { if (uiState.saved) onSaved() }

    SanvyaPage(
        title = S.Transactions.addTitle(sRes()),
        action = {

        },
    ) {
        if (accounts.isEmpty()) {
            Column(
                Modifier.fillMaxSize().padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Text("Add an account first", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = colors.text)
                Spacer(Modifier.height(12.dp))
                Button(onClick = onAddAccountFirst) { Text(S.Transactions.newAccountCta(sRes())) }
            }
            return@SanvyaPage
        }

        val currency = account?.currency ?: baseCurrencyNow()

        Column(
            modifier = Modifier.fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("expense", "income", "transfer").forEach { tp ->
                    val blocked = isInvestment && tp != "transfer"
                    FilterChip(
                        selected = tp == uiState.type,
                        onClick = { if (!blocked) viewModel.setType(tp) },
                        enabled = !blocked,
                        label = { Text(tp.replaceFirstChar { it.uppercase() }) },
                        modifier = Modifier.weight(1f),
                    )
                }
            }
            if (isInvestment) {
                Text(S.Transactions.investmentTransferOnly(sRes()), fontSize = 12.sp, color = colors.text2)
            }

            if (uiState.type == "transfer") {
                OutlinedTextField(
                    value = uiState.items.firstOrNull()?.value ?: "",
                    onValueChange = viewModel::setTransferAmount,
                    label = { Text("Amount ($currency)") },
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
            }

            Text(if (uiState.type == "transfer") S.Transactions.fromAccount(sRes()) else S.Transactions.account(sRes()), fontSize = 13.sp, color = colors.text2)
            ChipRow(
                options = accounts.map { it.id },
                selected = account?.id ?: "",
                label = { id -> accounts.find { it.id == id }?.let { "${it.name} · ${it.currency}" } ?: "" },
                onSelect = viewModel::setAccountId,
                colors = colors,
            )

            if (uiState.type == "transfer") {
                Text(S.Transactions.toAccount(sRes()), fontSize = 13.sp, color = colors.text2)
                ChipRow(
                    options = accounts.filter { it.id != account?.id }.map { it.id },
                    selected = toAccount?.id ?: "",
                    label = { id -> accounts.find { it.id == id }?.let { "${it.name} · ${it.currency}" } ?: "" },
                    onSelect = viewModel::setToAccountId,
                    colors = colors,
                )
                if (toAccount != null && toAccount!!.currency != currency) {
                    OutlinedTextField(
                        value = uiState.toValue,
                        onValueChange = viewModel::setToValue,
                        label = { Text("Amount received (${toAccount!!.currency})") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }

            if (uiState.type != "transfer") {
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

            Text(S.Transactions.labelsOptional(sRes()), fontSize = 13.sp, color = colors.text2)
            LabelPickerRow(
                available = labelOptions.map { it.name },
                selected = uiState.selectedLabels,
                onToggle = viewModel::toggleLabel,
                onAddNew = viewModel::addNewLabel,
                colors = colors,
            )

            OutlinedTextField(
                value = uiState.note,
                onValueChange = viewModel::setNote,
                label = { Text(S.Transactions.noteOptional(sRes())) },
                modifier = Modifier.fillMaxWidth(),
            )

            DateTimeField(value = uiState.occurredAt, onChange = viewModel::setOccurredAt)

            uiState.error?.let {
                Text(it, color = colors.negative, fontSize = 13.sp)
            }

            Button(
                onClick = { viewModel.save() },
                enabled = viewModel.canSave(),
                modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
            ) {
                Text(if (uiState.saving) S.Transactions.saving(sRes()) else S.Translation.commonSave(sRes()))
            }
        }
    }
}

/** Multi-select chip picker over existing labels + free-text add — matches
 * LabelPicker's behavior (pick existing, or type a new name and add it). */
@Composable
internal fun LabelPickerRow(
    available: List<String>,
    selected: List<String>,
    onToggle: (String) -> Unit,
    onAddNew: (String) -> Unit,
    colors: com.sanvya.app.theme.SanvyaColors,
) {
    var draft by rememberSaveable { mutableStateOf("") }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        val allNames = (available + selected).distinct()
        if (allNames.isNotEmpty()) {
            androidx.compose.foundation.layout.FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                allNames.forEach { name ->
                    val isSelected = name in selected
                    AssistChip(
                        onClick = { onToggle(name) },
                        label = { Text(name, fontSize = 13.sp) },
                        colors = AssistChipDefaults.assistChipColors(
                            containerColor = if (isSelected) colors.accent else colors.surface,
                            labelColor = if (isSelected) androidx.compose.ui.graphics.Color.White else colors.text,
                        ),
                    )
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(
                value = draft,
                onValueChange = { draft = it },
                placeholder = { Text(S.Labels.newLabel(sRes())) },
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = { onAddNew(draft); draft = "" }) { Text(S.Transactions.add(sRes())) }
        }
    }
}
