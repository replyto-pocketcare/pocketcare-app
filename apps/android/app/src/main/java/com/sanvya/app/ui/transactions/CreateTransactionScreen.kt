package com.sanvya.app.ui.transactions

import androidx.compose.foundation.background
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
import com.sanvya.app.ui.accounts.ChipRow
import com.sanvya.app.ui.baseCurrencyNow
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaPage
import com.sanvya.app.ui.formatMoneyUnmasked

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
    /** Web's `?split=<id>`: the group a caller (a group's "Add expense") wants
     * this expense split with, already chosen when the form opens. */
    preselectSplitGroupId: String = "",
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
    val total by viewModel.total.collectAsState()
    val colors = LocalSanvyaColors.current

    LaunchedEffect(uiState.saved) { if (uiState.saved) onSaved() }
    LaunchedEffect(preselectSplitGroupId) { viewModel.preselectSplitGroup(preselectSplitGroupId) }

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
                Text(S.Transactions.createAccountFirst(sRes()), fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = colors.text)
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
                        // The translated type name, not the KEY capitalised --
                        // `tp.replaceFirstChar {}` rendered "Expense"/"Income"
                        // in every language, the same defect the list's filter
                        // chips already carry a comment about.
                        label = { Text(txTypeLabel(tp)) },
                        modifier = Modifier.weight(1f),
                    )
                }
            }
            if (isInvestment) {
                Text(S.Transactions.investmentTransferOnly(sRes()), fontSize = 12.sp, color = colors.text2)
            }

            // Web's amount card: the running total as the headline, the inputs
            // that feed it directly underneath. Neither phone showed the total
            // at all, so a three-item bill was saved without the user ever
            // seeing what it came to.
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
                            // Unmasked on purpose. This is the number the user
                            // is typing, not one being shown to them, and the
                            // hide-amounts mask would make the form unusable --
                            // which is why web reaches past `useMoneyFmt` here
                            // too.
                            formatMoneyUnmasked(total),
                            fontSize = 40.sp,
                            fontWeight = FontWeight.Bold,
                            color = when (uiState.type) {
                                "income" -> colors.positive
                                "transfer" -> colors.forest
                                else -> colors.negative
                            },
                        )
                    }

                    if (uiState.type == "transfer") {
                        OutlinedTextField(
                            value = uiState.items.firstOrNull()?.value ?: "",
                            onValueChange = viewModel::setTransferAmount,
                            label = { Text(S.Transactions.amountCurrency(sRes(), currency)) },
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
                        label = { Text(S.Transactions.amountReceived(sRes(), toAccount!!.currency)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }

            if (uiState.type != "transfer") {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(S.Transactions.category(sRes()), fontSize = 13.sp, color = colors.text2)
                    // Web draws this badge over the top-right corner of the
                    // category select. On a phone it sits on the label's line
                    // instead -- same place in the reading order, without
                    // overlapping a control the user is about to tap.
                    if (uiState.autoCategorizeWorking || uiState.autoApplied) {
                        AutoCategoriseBadge(
                            working = uiState.autoCategorizeWorking,
                            categoryName = relevantCategories.find { it.id == uiState.categoryId }?.name,
                            colors = colors,
                        )
                    }
                }
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

            // Web places the two split cards immediately above Labels, after
            // category and payment method and before the free-text fields.
            // Both are expense-only and mutually exclusive; SplitEditor
            // decides which (if either) to draw.
            SplitEditor(viewModel = viewModel, currency = currency)

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
                Text(
                    if (uiState.saving) {
                        S.Transactions.saving(sRes())
                    } else {
                        // "Save · ₹1,240" -- web's own label. On a long form
                        // the button is the only place the total is still on
                        // screen when the user commits.
                        S.Transactions.saveWithTotal(sRes(), formatMoneyUnmasked(total))
                    },
                )
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

/**
 * The translated name of a transaction type -- web's `t(`type.${tp}`)`.
 *
 * `internal`, not file-private: the Edit screen draws the same three chips from
 * the same three keys, and a second copy of a mapping is how the two drift.
 */
@Composable
internal fun txTypeLabel(key: String): String = when (key) {
    "income" -> S.Transactions.typeIncome(sRes())
    "transfer" -> S.Transactions.typeTransfer(sRes())
    else -> S.Transactions.typeExpense(sRes())
}

/**
 * "Finding category…" while the categoriser runs, "Auto-categorised · Food"
 * once it lands.
 *
 * Web shows exactly these two states and nothing between them, and the pair is
 * the point: a category that changes under the user's hands with no explanation
 * reads as a bug, and one that appears 220ms after they stop typing with no
 * warning reads as a glitch. Both ports had the categoriser and neither had the
 * badge, so it was doing precisely that.
 */
@Composable
private fun AutoCategoriseBadge(
    working: Boolean,
    categoryName: String?,
    colors: com.sanvya.app.theme.SanvyaColors,
) {
    val label = if (working) {
        S.Transactions.findingCategory(sRes())
    } else {
        val base = S.Transactions.autoCategorised(sRes())
        if (categoryName != null) "$base · $categoryName" else base
    }
    Text(
        "$AUTO_CATEGORISE_GLYPH $label",
        fontSize = 11.sp,
        fontWeight = FontWeight.SemiBold,
        color = colors.accent,
        modifier = Modifier
            // The theme has no 4px token (web's `borderRadius: 4`);
            // `checkbox` is its smallest square-ish corner and the nearest
            // thing to it. Adding a token belongs to the design system, not to
            // one badge.
            .clip(RoundedCornerShape(SanvyaRadius.checkbox))
            .background(colors.accentGhost)
            .padding(horizontal = 6.dp, vertical = 2.dp),
    )
}

/**
 * The four-pointed star web puts in front of both auto-categorise states.
 *
 * A glyph, not copy: it is the same mark in every language and carries no
 * meaning a translator could change, so it stays out of the string files
 * rather than being duplicated into three of them.
 */
private const val AUTO_CATEGORISE_GLYPH = "\u2726"

/**
 * The numeric hint in an amount field.
 *
 * Not translated, and web does not translate it either: it is a NUMBER shaped
 * like the input, and localising the separators would put a hint on screen that
 * the decimal keypad cannot type.
 */
internal const val AMOUNT_PLACEHOLDER = "0.00"
