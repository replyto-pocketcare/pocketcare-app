package com.sanvya.app.ui.loans

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
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
import com.sanvya.app.domain.finance.emiFromPrincipal
import com.sanvya.app.domain.money.fromMajor
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.ui.budgets.DatePickerDialogSimple
import com.sanvya.app.ui.budgets.TimePickerDialogSimple
import com.sanvya.app.ui.budgets.localToUtcTime
import kotlinx.coroutines.launch
import com.sanvya.app.ui.baseCurrencyNow
import com.sanvya.app.ui.formatMoney
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.ui.components.SanvyaPage

/**
 * Ported from apps/web/app/loans/[id]/page.tsx's `EditLoan` inline form per
 * docs/mobile/screen-specs/loans.md (task #27). New file -- referenced by
 * LoanDetailScreen.kt but didn't exist yet. Same field set as
 * AddLoanScreen.kt minus the funding-account/auto-mark fields (those are
 * only ever set via a mark-paid confirm or the add form, matching web's
 * `EditLoan` exactly -- it has no funding-account/auto-mark controls
 * either). Prefilled from LoanDetailUiModel's raw* fields, writes via the
 * SAME LoanDetailViewModel instance the detail screen is already using (not
 * a fresh LoansViewModel), so its live watchLoan() subscription picks the
 * edit up immediately -- no separate refresh needed.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditLoanScreen(
    model: LoanDetailUiModel,
    onBack: () -> Unit = {},
    onSaved: () -> Unit = {},
    viewModel: LoanDetailViewModel,
) {
    val colors = LocalSanvyaColors.current
    val scope = rememberCoroutineScope()

    var lender by rememberSaveable(model.id) { mutableStateOf(model.rawLender) }
    var rateType by rememberSaveable(model.id) { mutableStateOf(model.rawRateType) }
    var principal by rememberSaveable(model.id) { mutableStateOf(model.rawPrincipalMajor) }
    var tenure by rememberSaveable(model.id) { mutableStateOf(model.rawTenure) }
    var rate by rememberSaveable(model.id) { mutableStateOf(model.rawInterestRate) }
    var emi by rememberSaveable(model.id) { mutableStateOf(model.rawEmiMajor) }
    var emiTouched by rememberSaveable(model.id) { mutableStateOf(model.rawEmiMajor.isNotBlank()) }
    var start by rememberSaveable(model.id) { mutableStateOf(model.rawStartDate) }
    var dueDay by rememberSaveable(model.id) { mutableStateOf(model.rawDueDay) }
    var alertTime by rememberSaveable(model.id) { mutableStateOf(model.rawAlertTimeLocal) }
    var saving by rememberSaveable(model.id) { mutableStateOf(false) }
    var errorText by rememberSaveable(model.id) { mutableStateOf<String?>(null) }
    var showStartDatePicker by rememberSaveable(model.id) { mutableStateOf(false) }
    var showTimePicker by rememberSaveable(model.id) { mutableStateOf(false) }

    val principalMinor = principal.toDoubleOrNull()?.let { fromMajor(it, model.currency).amount } ?: 0L
    val computedEmiMinor = if (rateType == "fixed") emiFromPrincipal(principalMinor, rate.toDoubleOrNull() ?: 0.0, tenure.toIntOrNull() ?: 0) else 0L
    val computedEmiMajor = if (computedEmiMinor > 0) formatMajorPlain(computedEmiMinor, baseCurrencyNow()) else ""
    val emiValue = if (rateType == "variable") "" else if (emiTouched) emi else (emi.ifBlank { computedEmiMajor })

    SanvyaPage(
        title = S.Loans.editTitle(sRes()),
        action = {

        },
    ) {
        Column(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            OutlinedTextField(value = lender, onValueChange = { lender = it }, label = { Text(S.Loans.lender(sRes())) }, modifier = Modifier.fillMaxWidth())

            Text(S.Loans.interestType(sRes()), fontSize = 13.sp, color = colors.text2)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = rateType == "fixed", onClick = { rateType = "fixed" }, label = { Text(S.Loans.fixed(sRes())) })
                FilterChip(selected = rateType == "variable", onClick = { rateType = "variable" }, label = { Text(S.Loans.variable(sRes())) })
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = principal, onValueChange = { principal = it.filter { c -> c.isDigit() || c == '.' } },
                    label = { Text("Principal (${model.currency})") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.weight(1f),
                )
                OutlinedTextField(
                    value = tenure, onValueChange = { tenure = it.filter { c -> c.isDigit() } },
                    label = { Text(S.Loans.tenureMonths(sRes())) }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.weight(1f),
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = rate, onValueChange = { rate = it.filter { c -> c.isDigit() || c == '.' } },
                    label = { Text(if (rateType == "variable") "Current interest %" else S.Loans.interestPa(sRes())) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), modifier = Modifier.weight(1f),
                )
                if (rateType == "fixed") {
                    OutlinedTextField(
                        value = emiValue, onValueChange = { emi = it; emiTouched = true },
                        label = { Text("Monthly EMI (${model.currency})") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.weight(1f),
                    )
                }
            }
            if (rateType == "fixed") {
                if (computedEmiMinor > 0) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(
                            if (emiTouched) "Auto-calculated EMI would be ${formatMoney(computedEmiMinor, model.currency)}" else "EMI auto-calculated from principal, rate & tenure.",
                            fontSize = 12.sp, color = colors.text2,
                        )
                        if (emiTouched) TextButton(onClick = { emiTouched = false; emi = "" }) { Text(S.Loans.useIt(sRes()), fontSize = 11.sp) }
                    }
                }
            } else {
                Text(
                    "Variable-rate loans: enter each month's EMI from this loan's detail page as bills come in.",
                    fontSize = 12.sp, color = colors.text2,
                )
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Started on", fontSize = 13.sp, color = colors.text2, modifier = Modifier.weight(1f))
                TextButton(onClick = { showStartDatePicker = true }) { Text(start.ifBlank { "Pick a date" }) }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = dueDay, onValueChange = { dueDay = it.filter { c -> c.isDigit() }.take(2) },
                    label = { Text("Due day (1-31)") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.weight(1f),
                )
                Row(modifier = Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Alert time", fontSize = 13.sp, color = colors.text2)
                    TextButton(onClick = { showTimePicker = true }) { Text(alertTime) }
                }
            }

            errorText?.let { Text(it, color = colors.negative, fontSize = 13.sp) }

            Button(
                onClick = {
                    saving = true
                    errorText = null
                    scope.launch {
                        val err = viewModel.update(
                            lender = lender, principalMajorText = principal,
                            emiMajorText = if (rateType == "variable") "" else emiValue,
                            interestRateText = rate, tenureText = tenure, startDate = start,
                            dueDayText = dueDay, rateType = rateType, alertTimeUtc = localToUtcTime(alertTime),
                        )
                        saving = false
                        if (err != null) errorText = err else onSaved()
                    }
                },
                enabled = !saving && (lender.trim().isNotEmpty() || principal.isNotBlank()),
                modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
            ) {
                Text(if (saving) S.Loans.savingEllipsis(sRes()) else S.Translation.commonSaveChanges(sRes()))
            }
        }
    }

    if (showStartDatePicker) {
        DatePickerDialogSimple(onDismiss = { showStartDatePicker = false }, onConfirm = { start = it; showStartDatePicker = false })
    }
    if (showTimePicker) {
        TimePickerDialogSimple(initial = alertTime, onDismiss = { showTimePicker = false }, onConfirm = { alertTime = it; showTimePicker = false })
    }
}
