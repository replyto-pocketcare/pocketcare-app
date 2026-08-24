package com.sanvya.app.ui.budgets

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
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
import com.sanvya.app.ui.StringListSaver
import com.sanvya.app.ui.transactions.LabelPickerRow
import kotlinx.coroutines.launch
import com.sanvya.app.ui.FormOptions

private val BUDGET_CURRENCIES = FormOptions.currencies
private val BUDGET_PERIODS = FormOptions.periods

internal fun periodChipLabel(p: String) = when (p) {
    "daily" -> "Daily"
    "weekly" -> "Weekly"
    "yearly" -> "Yearly"
    else -> "Monthly"
}

/**
 * Real create form, matching apps/web/app/budgets/page.tsx's "New budget"
 * modal field-for-field per docs/mobile/screen-specs/budgets.md. Android had
 * no Budgets screens at all before this pass (2026-08-06, task #24).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreateBudgetScreen(
    onBack: () -> Unit = {},
    onSaved: () -> Unit = {},
    viewModel: BudgetsViewModel = viewModel(),
) {
    val colors = LocalSanvyaColors.current
    val expenseCategories by viewModel.expenseCategories.collectAsState()
    val labelNames by viewModel.labelNames.collectAsState()
    val scope = rememberCoroutineScope()

    // rememberSaveable (not remember): this whole form's state must survive
    // a configuration change (fold/unfold, rotation) without losing
    // in-progress input -- see docs/plans/native-mobile-apps.md's R1 /
    // LIFE-1..2, retrofitted 2026-08-06 (P3.19). `saving`/errorText and the
    // dialog-open booleans are included too, matching LIFE-2's "dialogs
    // stay open" requirement.
    var name by rememberSaveable { mutableStateOf("") }
    var limitText by rememberSaveable { mutableStateOf("") }
    var currency by rememberSaveable { mutableStateOf(FormOptions.DEFAULT_CURRENCY) }
    var currencyExpanded by rememberSaveable { mutableStateOf(false) }
    var thresholdText by rememberSaveable { mutableStateOf("80") }
    var alertTime by rememberSaveable { mutableStateOf("09:00") }
    var selectedCategoryIds by rememberSaveable(stateSaver = StringListSaver) { mutableStateOf(listOf<String>()) }
    var selectedLabels by rememberSaveable(stateSaver = StringListSaver) { mutableStateOf(listOf<String>()) }
    var isCustomDated by rememberSaveable { mutableStateOf(false) }
    var period by rememberSaveable { mutableStateOf("monthly") }
    var startDate by rememberSaveable { mutableStateOf("") }
    var endDate by rememberSaveable { mutableStateOf("") }
    var saving by rememberSaveable { mutableStateOf(false) }
    var errorText by rememberSaveable { mutableStateOf<String?>(null) }
    var showTimePicker by rememberSaveable { mutableStateOf(false) }
    var showStartDatePicker by rememberSaveable { mutableStateOf(false) }
    var showEndDatePicker by rememberSaveable { mutableStateOf(false) }

    Scaffold(
        containerColor = colors.bg,
        topBar = {
            TopAppBar(
                title = { Text("New budget", fontWeight = FontWeight.Bold, color = colors.text) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = colors.text2)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.bg),
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("Budget name (optional)") },
                placeholder = { Text("Falls back to the category/label scope") },
                modifier = Modifier.fillMaxWidth(),
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = limitText,
                    onValueChange = { limitText = it },
                    label = { Text("Limit") },
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.weight(1f),
                )
                ExposedDropdownMenuBox(expanded = currencyExpanded, onExpandedChange = { currencyExpanded = it }, modifier = Modifier.width(110.dp)) {
                    OutlinedTextField(
                        value = currency,
                        onValueChange = {},
                        readOnly = true,
                        modifier = Modifier.menuAnchor(),
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = currencyExpanded) },
                    )
                    ExposedDropdownMenu(expanded = currencyExpanded, onDismissRequest = { currencyExpanded = false }) {
                        BUDGET_CURRENCIES.forEach { c ->
                            DropdownMenuItem(text = { Text(c) }, onClick = { currency = c; currencyExpanded = false })
                        }
                    }
                }
            }

            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Alert at", color = colors.text2, fontSize = 13.sp)
                OutlinedTextField(
                    value = thresholdText,
                    onValueChange = { thresholdText = it.filter { c -> c.isDigit() } },
                    modifier = Modifier.width(70.dp),
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Number),
                )
                Text("% of limit, at", color = colors.text2, fontSize = 13.sp)
                TextButton(onClick = { showTimePicker = true }) { Text(alertTime) }
            }

            Text("Categories (optional)", color = colors.text2, fontSize = 13.sp)
            CategoryMultiSelectRow(options = expenseCategories, selectedIds = selectedCategoryIds, onToggle = { id ->
                selectedCategoryIds = if (id in selectedCategoryIds) selectedCategoryIds - id else selectedCategoryIds + id
            })

            Text("Labels (optional)", color = colors.text2, fontSize = 13.sp)
            LabelPickerRow(
                available = labelNames,
                selected = selectedLabels,
                onToggle = { n -> selectedLabels = if (n in selectedLabels) selectedLabels - n else selectedLabels + n },
                onAddNew = { n -> if (n.isNotBlank() && n !in selectedLabels) selectedLabels = selectedLabels + n },
                colors = colors,
            )

            Text("Timeframe", color = colors.text2, fontSize = 13.sp)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                TimeframeChip("Recurring", !isCustomDated) { isCustomDated = false }
                TimeframeChip("Custom dates", isCustomDated) { isCustomDated = true }
            }
            if (!isCustomDated) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    BUDGET_PERIODS.forEach { p -> TimeframeChip(periodChipLabel(p), period == p) { period = p } }
                }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = startDate,
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Start") },
                        modifier = Modifier.weight(1f),
                        trailingIcon = { TextButton(onClick = { showStartDatePicker = true }) { Text("Pick") } },
                    )
                    OutlinedTextField(
                        value = endDate,
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("End") },
                        modifier = Modifier.weight(1f),
                        trailingIcon = { TextButton(onClick = { showEndDatePicker = true }) { Text("Pick") } },
                    )
                }
            }

            errorText?.let { Text(it, color = colors.negative, fontSize = 13.sp) }

            Button(
                onClick = {
                    saving = true
                    errorText = null
                    scope.launch {
                        val err = viewModel.create(
                            name = name,
                            limitMajorText = limitText,
                            currency = currency,
                            thresholdPctText = thresholdText,
                            alertTimeLocal = alertTime,
                            categoryIds = selectedCategoryIds,
                            labelNamesInput = selectedLabels,
                            isCustomDated = isCustomDated,
                            period = period,
                            startDate = startDate.ifBlank { null },
                            endDate = endDate.ifBlank { null },
                        )
                        saving = false
                        if (err != null) errorText = err else onSaved()
                    }
                },
                enabled = !saving,
                modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
            ) {
                Text(if (saving) "Saving…" else "Create Budget")
            }
        }
    }

    if (showTimePicker) {
        TimePickerDialogSimple(
            initial = alertTime,
            onDismiss = { showTimePicker = false },
            onConfirm = { alertTime = it; showTimePicker = false },
        )
    }
    if (showStartDatePicker) {
        DatePickerDialogSimple(
            onDismiss = { showStartDatePicker = false },
            onConfirm = { startDate = it; if (endDate.isNotEmpty() && endDate < it) endDate = it; showStartDatePicker = false },
        )
    }
    if (showEndDatePicker) {
        DatePickerDialogSimple(
            onDismiss = { showEndDatePicker = false },
            onConfirm = { endDate = it; showEndDatePicker = false },
        )
    }
}

@Composable
internal fun TimeframeChip(label: String, active: Boolean, onClick: () -> Unit) {
    val colors = LocalSanvyaColors.current
    AssistChip(
        onClick = onClick,
        label = { Text(label, fontSize = 13.sp) },
        colors = AssistChipDefaults.assistChipColors(
            containerColor = if (active) colors.accent else colors.surface,
            labelColor = if (active) androidx.compose.ui.graphics.Color.White else colors.text,
        ),
    )
}

/** Toggleable-chip multi-select over expense categories -- native-idiomatic
 * equivalent of web's <MultiSelect>, matching LabelPickerRow's established
 * wrapping-chip-row pattern, id-based selection instead of name-based. */
@Composable
internal fun CategoryMultiSelectRow(options: List<CategoryOption>, selectedIds: List<String>, onToggle: (String) -> Unit) {
    val colors = LocalSanvyaColors.current
    if (options.isEmpty()) {
        Text("No expense categories yet", color = colors.text2, fontSize = 13.sp)
    } else {
        androidx.compose.foundation.layout.FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            options.forEach { option ->
                val isSelected = option.id in selectedIds
                AssistChip(
                    onClick = { onToggle(option.id) },
                    label = { Text(option.name, fontSize = 13.sp) },
                    colors = AssistChipDefaults.assistChipColors(
                        containerColor = if (isSelected) colors.accent else colors.surface,
                        labelColor = if (isSelected) androidx.compose.ui.graphics.Color.White else colors.text,
                    ),
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun TimePickerDialogSimple(initial: String, onDismiss: () -> Unit, onConfirm: (String) -> Unit) {
    val parts = initial.split(":")
    val initialHour = parts.getOrNull(0)?.toIntOrNull() ?: 9
    val initialMinute = parts.getOrNull(1)?.toIntOrNull() ?: 0
    val state = rememberTimePickerState(initialHour = initialHour, initialMinute = initialMinute, is24Hour = true)
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = { onConfirm(String.format("%02d:%02d", state.hour, state.minute)) }) { Text("Done") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
        text = { Column { TimePicker(state = state) } },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun DatePickerDialogSimple(onDismiss: () -> Unit, onConfirm: (String) -> Unit) {
    val state = rememberDatePickerState()
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = {
                val millis = state.selectedDateMillis
                if (millis != null) {
                    val date = java.time.Instant.ofEpochMilli(millis).atZone(java.time.ZoneOffset.UTC).toLocalDate()
                    onConfirm(date.toString())
                } else {
                    onDismiss()
                }
            }) { Text("OK") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    ) {
        DatePicker(state = state)
    }
}
