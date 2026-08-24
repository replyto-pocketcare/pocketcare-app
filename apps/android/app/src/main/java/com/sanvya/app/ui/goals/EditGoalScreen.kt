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
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes

/**
 * Real edit form + delete, matching apps/web/app/goals/page.tsx's
 * GoalCard openEdit()/saveEdit() field-for-field per
 * docs/mobile/screen-specs/goals.md: name/target/alert-time editable --
 * currency, is_emergency_fund, and priority are not (create-only/
 * immutable from this screen, matching web exactly). New file -- Android
 * had no edit screen for goals at all before this pass (2026-08-06, task
 * #25); GoalsScreen.kt's rows were not tappable.
 *
 * Resolves its GoalUiModel from this screen's own GoalsViewModel
 * instance's already-loaded list by id (nav-arg friendly), matching
 * EditBudgetScreen.kt's own per-screen-instance pattern.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditGoalScreen(
    goalId: String,
    onBack: () -> Unit = {},
    onSaved: () -> Unit = {},
    onDeleted: () -> Unit = {},
    viewModel: GoalsViewModel = viewModel(),
) {
    val colors = LocalSanvyaColors.current
    val goals by viewModel.goals.collectAsState()
    val goal = goals.find { it.id == goalId }
    val scope = rememberCoroutineScope()

    if (goal == null) {
        Scaffold(containerColor = colors.bg) { padding ->
            Box(modifier = Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.accent)
            }
        }
        return
    }

    // rememberSaveable (not remember): survives configuration change
    // (fold/unfold, rotation) without losing in-progress edits -- see
    // docs/plans/native-mobile-apps.md's R1 / LIFE-1..2, retrofitted
    // 2026-08-06 (P3.19).
    var name by rememberSaveable(goal.id) { mutableStateOf(goal.rawName) }
    var targetText by rememberSaveable(goal.id) { mutableStateOf(goal.targetMajor) }
    var alertTime by rememberSaveable(goal.id) { mutableStateOf(goal.alertTimeLocal) }
    var saving by rememberSaveable { mutableStateOf(false) }
    var errorText by rememberSaveable { mutableStateOf<String?>(null) }
    var showTimePicker by rememberSaveable { mutableStateOf(false) }
    var showDeleteConfirm by rememberSaveable { mutableStateOf(false) }

    Scaffold(
        containerColor = colors.bg,
        topBar = {
            TopAppBar(
                title = { Text("Edit Goal", fontWeight = FontWeight.Bold, color = colors.text) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = S.Translation.commonBack(sRes()), tint = colors.text2)
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
                label = { Text(S.Goals.goalName(sRes())) },
                modifier = Modifier.fillMaxWidth(),
            )

            OutlinedTextField(
                value = targetText,
                onValueChange = { targetText = it },
                label = { Text("Target amount (${goal.currency})") },
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Decimal),
                modifier = Modifier.fillMaxWidth(),
            )

            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Alert time", color = colors.text2, fontSize = 13.sp)
                TextButton(onClick = { showTimePicker = true }) { Text(alertTime) }
            }

            errorText?.let { Text(it, color = colors.negative, fontSize = 13.sp) }

            Button(
                onClick = {
                    saving = true
                    errorText = null
                    scope.launch {
                        val err = viewModel.update(goal.id, name, targetText, alertTime)
                        saving = false
                        if (err != null) errorText = err else onSaved()
                    }
                },
                enabled = !saving,
                modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
            ) {
                Text(if (saving) S.Translation.commonSaving(sRes()) else S.Translation.commonSaveChanges(sRes()))
            }

            OutlinedButton(
                onClick = { showDeleteConfirm = true },
                colors = ButtonDefaults.outlinedButtonColors(contentColor = colors.negative),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Delete Goal")
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
            title = { Text(S.Goals.deleteTitle(sRes())) },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    viewModel.delete(goal.id)
                    onDeleted()
                }) { Text(S.Goals.delete(sRes()), color = colors.negative) }
            },
            dismissButton = { TextButton(onClick = { showDeleteConfirm = false }) { Text(S.Goals.cancel(sRes())) } },
        )
    }
}
