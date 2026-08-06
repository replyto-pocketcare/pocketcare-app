package com.sanvya.app.ui.budgets

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
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
import com.sanvya.app.ui.transactions.LabelPickerRow
import kotlinx.coroutines.launch

/**
 * Real edit form + delete, matching apps/web/app/budgets/page.tsx's
 * BudgetRow openEdit()/saveEdit() field-for-field per
 * docs/mobile/screen-specs/budgets.md: name/limit/threshold/alert-time/
 * categories/labels editable; currency and start/end dates are NOT (web's
 * edit form has no currency picker; the period chips are hidden entirely
 * for a custom-dated budget). Mirrors iOS's EditBudgetView.swift. Android
 * had no edit screen for budgets at all before this pass (2026-08-06,
 * task #24) -- BudgetsScreen.kt's rows were not tappable.
 *
 * Takes a budgetId (nav-arg friendly) and resolves the live BudgetUiModel
 * from this screen's own BudgetsViewModel instance once its list loads,
 * same "own instance per screen" pattern iOS uses (@State private var
 * viewModel = BudgetsViewModel() per view).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditBudgetScreen(
    budgetId: String,
    onBack: () -> Unit = {},
    onSaved: () -> Unit = {},
    onDeleted: () -> Unit = {},
    viewModel: BudgetsViewModel = viewModel(),
) {
    val colors = LocalSanvyaColors.current
    val budgets by viewModel.budgets.collectAsState()
    val expenseCategories by viewModel.expenseCategories.collectAsState()
    val labelNames by viewModel.labelNames.collectAsState()
    val budget = budgets.find { it.id == budgetId }
    val scope = rememberCoroutineScope()

    if (budget == null) {
        Scaffold(containerColor = colors.bg) { padding ->
            Box(modifier = Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.accent)
            }
        }
        return
    }

    var name by remember(budget.id) { mutableStateOf(budget.rawName) }
    var limitText by remember(budget.id) { mutableStateOf(budget.limitMajor) }
    var thresholdText by remember(budget.id) { mutableStateOf(budget.thresholdPct.toString()) }
    var alertTime by remember(budget.id) { mutableStateOf(budget.alertTimeLocal) }
    var selectedCategoryIds by remember(budget.id) { mutableStateOf(budget.categoryIds) }
    var selectedLabels by remember(budget.id) { mutableStateOf(budget.labelNames) }
    var period by remember(budget.id) { mutableStateOf(budget.period) }
    var saving by remember { mutableStateOf(false) }
    var errorText by remember { mutableStateOf<String?>(null) }
    var showTimePicker by remember { mutableStateOf(false) }
    var showDeleteConfirm by remember { mutableStateOf(false) }

    Scaffold(
        containerColor = colors.bg,
        topBar = {
            TopAppBar(
                title = { Text("Edit Budget", fontWeight = FontWeight.Bold, color = colors.text) },
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

            OutlinedTextField(
                value = limitText,
                onValueChange = { limitText = it },
                label = { Text("Limit (${budget.currency})") },
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Decimal),
                modifier = Modifier.fillMaxWidth(),
            )

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

            // Period chips only for a recurring budget -- a custom-dated one
            // can't be converted back to recurring from the edit form,
            // matching web's `{!budget.start_date && <chips>}` and iOS's
            // `if !budget.isCustomDated`.
            if (!budget.isCustomDated) {
                Text("Recurrence", color = colors.text2, fontSize = 13.sp)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf("daily", "weekly", "monthly", "yearly").forEach { p ->
                        TimeframeChip(periodChipLabel(p), period == p) { period = p }
                    }
                }
            }

            errorText?.let { Text(it, color = colors.negative, fontSize = 13.sp) }

            Button(
                onClick = {
                    saving = true
                    errorText = null
                    scope.launch {
                        val err = viewModel.update(
                            id = budget.id,
                            name = name,
                            limitMajorText = limitText,
                            currency = budget.currency,
                            period = period,
                            thresholdPctText = thresholdText,
                            alertTimeLocal = alertTime,
                            categoryIds = selectedCategoryIds,
                            labelNamesInput = selectedLabels,
                        )
                        saving = false
                        if (err != null) errorText = err else onSaved()
                    }
                },
                enabled = !saving,
                modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
            ) {
                Text(if (saving) "Saving…" else "Save Changes")
            }

            OutlinedButton(
                onClick = { showDeleteConfirm = true },
                colors = ButtonDefaults.outlinedButtonColors(contentColor = colors.negative),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Delete Budget")
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

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("Delete this budget?") },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    viewModel.delete(budget.id)
                    onDeleted()
                }) { Text("Delete", color = colors.negative) }
            },
            dismissButton = { TextButton(onClick = { showDeleteConfirm = false }) { Text("Cancel") } },
        )
    }
}
