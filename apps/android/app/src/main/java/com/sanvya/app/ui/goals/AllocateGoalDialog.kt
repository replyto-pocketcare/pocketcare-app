package com.sanvya.app.ui.goals

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sanvya.app.theme.LocalSanvyaColors
import kotlinx.coroutines.launch
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.domain.money.toMajor
import com.sanvya.app.domain.money.money
import com.sanvya.app.ui.formatMoney

/**
 * "+ Add funds" / "+ Block funds" dialog, matching apps/web/app/goals/
 * page.tsx's allocate() Modal per docs/mobile/screen-specs/goals.md: a
 * source savings-account picker, an amount field, a "left to target"
 * hint, and a submit capped at the goal's remaining amount. New file --
 * no allocate path existed on Android before this pass (2026-08-06, task
 * #25).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AllocateGoalDialog(goal: GoalUiModel, viewModel: GoalsViewModel, onDismiss: () -> Unit) {
    val colors = LocalSanvyaColors.current
    val savingsAccounts by viewModel.savingsAccounts.collectAsState()
    val scope = rememberCoroutineScope()

    // rememberSaveable: keeps the entered amount/picked account across a
    // configuration change while this dialog is open -- see
    // docs/plans/native-mobile-apps.md's R1 / LIFE-2 ("dialogs stay open"),
    // retrofitted 2026-08-06 (P3.19).
    var sourceAccountId by rememberSaveable { mutableStateOf(savingsAccounts.firstOrNull()?.id ?: "") }
    var amountText by rememberSaveable { mutableStateOf("") }
    var expanded by rememberSaveable { mutableStateOf(false) }
    var saving by rememberSaveable { mutableStateOf(false) }
    var errorText by rememberSaveable { mutableStateOf<String?>(null) }

    // Web has TWO labels here, not one: `allocLabel` titles the dialog ("Add
    // funds" / "Block funds") and a shorter verb sits on the submit button
    // ("Add" / "Block"). They were collapsed into one English literal.
    val allocLabel = if (goal.isEmergencyFund) S.Goals.addFunds(sRes()) else S.Goals.blockFunds(sRes())
    val submitLabel = if (goal.isEmergencyFund) S.Goals.add(sRes()) else S.Goals.block(sRes())
    // `toMajor`, not `/ 100.0`: the goal carries its own currency and a
    // zero-decimal one would read as a hundredth of itself.
    val remainingMajor = toMajor(money(goal.remainingMinor, goal.currency))
    val overCap = (amountText.toDoubleOrNull() ?: 0.0) > remainingMajor

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("$allocLabel · ${goal.name}") },
        text = {
            if (savingsAccounts.isEmpty()) {
                Text(S.Goals.addSavingsFirst(sRes()), color = colors.text2)
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
                        OutlinedTextField(
                            value = savingsAccounts.find { it.id == sourceAccountId }?.name ?: savingsAccounts.first().name,
                            onValueChange = {},
                            readOnly = true,
                            label = { Text(S.Goals.fromAccount(sRes())) },
                            modifier = Modifier.menuAnchor().fillMaxWidth(),
                            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                        )
                        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                            savingsAccounts.forEach { acc ->
                                DropdownMenuItem(text = { Text(acc.name) }, onClick = { sourceAccountId = acc.id; expanded = false })
                            }
                        }
                    }
                    OutlinedTextField(
                        value = amountText,
                        onValueChange = { amountText = it },
                        label = { Text(S.Goals.amount(sRes(), goal.currency)) },
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    // `formatMoney`, not a "%.2f CUR" literal: it is the one
                    // formatter, it is currency-aware, and it honours
                    // hide-amounts -- which a raw number in a dialog does not.
                    Text(
                        S.Goals.leftToTarget(sRes(), formatMoney(goal.remainingMinor, goal.currency)) +
                            if (overCap) S.Goals.willCap(sRes()) else "",
                        fontSize = 12.sp,
                        color = colors.text2,
                    )
                    errorText?.let { Text(it, color = colors.negative, fontSize = 12.sp) }
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = !saving && savingsAccounts.isNotEmpty() && amountText.isNotBlank(),
                onClick = {
                    val src = sourceAccountId.ifBlank { savingsAccounts.firstOrNull()?.id ?: return@TextButton }
                    saving = true
                    errorText = null
                    scope.launch {
                        val err = viewModel.allocate(goal.id, src, amountText, goal.remainingMinor, goal.currency)
                        saving = false
                        if (err != null) errorText = err else onDismiss()
                    }
                },
            ) { Text(if (saving) S.Translation.commonSaving(sRes()) else submitLabel) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(S.Goals.cancel(sRes())) } },
    )
}
