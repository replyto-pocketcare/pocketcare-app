package com.sanvya.app.ui.goals

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
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
import com.sanvya.app.ui.budgets.TimePickerDialogSimple
import kotlinx.coroutines.launch
import com.sanvya.app.ui.FormOptions
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.ui.components.SanvyaPage

private val GOAL_CURRENCIES = FormOptions.currencies

/**
 * Real create form, matching apps/web/app/goals/page.tsx's inline "New
 * goal" card field-for-field per docs/mobile/screen-specs/goals.md: name,
 * target + currency, alert time, EF checkbox (only when no EF goal exists
 * yet). New file -- Android had no Goals screens at all before this pass
 * (2026-08-06, task #25).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreateGoalScreen(
    onBack: () -> Unit = {},
    onSaved: () -> Unit = {},
    viewModel: GoalsViewModel = viewModel(),
) {
    val colors = LocalSanvyaColors.current
    val scope = rememberCoroutineScope()
    // Collected as state (not viewModel.hasEmergencyFund's plain getter)
    // so the EF checkbox's visibility actually recomposes once the
    // ViewModel's own init-time reload() finishes -- a bare getter read
    // once at first composition would miss that update.
    val goals by viewModel.goals.collectAsState()
    val hasEmergencyFund = goals.any { it.isEmergencyFund }

    // rememberSaveable (not remember): survives configuration change
    // (fold/unfold, rotation) without losing in-progress input -- see
    // docs/plans/native-mobile-apps.md's R1 / LIFE-1..2, retrofitted
    // 2026-08-06 (P3.19).
    var name by rememberSaveable { mutableStateOf("") }
    var targetText by rememberSaveable { mutableStateOf("") }
    var currency by rememberSaveable { mutableStateOf(FormOptions.DEFAULT_CURRENCY) }
    var currencyExpanded by rememberSaveable { mutableStateOf(false) }
    var isEmergencyFund by rememberSaveable { mutableStateOf(false) }
    var alertTime by rememberSaveable { mutableStateOf("09:00") }
    var saving by rememberSaveable { mutableStateOf(false) }
    var errorText by rememberSaveable { mutableStateOf<String?>(null) }
    var showTimePicker by rememberSaveable { mutableStateOf(false) }

    SanvyaPage(
        title = S.Goals.newGoal(sRes()),
        action = {

        },
    ) {
        Column(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text(S.Goals.goalName(sRes())) },
                placeholder = { Text("e.g. Emergency Fund") },
                modifier = Modifier.fillMaxWidth(),
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = targetText,
                    onValueChange = { targetText = it },
                    label = { Text("Target amount") },
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
                        GOAL_CURRENCIES.forEach { c ->
                            DropdownMenuItem(text = { Text(c) }, onClick = { currency = c; currencyExpanded = false })
                        }
                    }
                }
            }

            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Alert time", color = colors.text2, fontSize = 13.sp)
                TextButton(onClick = { showTimePicker = true }) { Text(alertTime) }
            }

            if (!hasEmergencyFund) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(checked = isEmergencyFund, onCheckedChange = { isEmergencyFund = it })
                    Text("This is my emergency fund", color = colors.text)
                }
            }

            errorText?.let { Text(it, color = colors.negative, fontSize = 13.sp) }

            Button(
                onClick = {
                    saving = true
                    errorText = null
                    scope.launch {
                        val err = viewModel.create(name, targetText, currency, isEmergencyFund, alertTime)
                        saving = false
                        if (err != null) errorText = err else onSaved()
                    }
                },
                enabled = !saving,
                modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
            ) {
                Text(if (saving) S.Translation.commonSaving(sRes()) else "Create Goal")
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
}
