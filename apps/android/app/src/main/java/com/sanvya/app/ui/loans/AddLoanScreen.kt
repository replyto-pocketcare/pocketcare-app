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
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.domain.finance.emiFromPrincipal
import com.sanvya.app.domain.money.fromMajor
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.ui.budgets.DatePickerDialogSimple
import com.sanvya.app.ui.budgets.TimePickerDialogSimple
import com.sanvya.app.ui.budgets.localToUtcTime
import kotlinx.coroutines.launch
import com.sanvya.app.ui.formatMoney
import com.sanvya.app.ui.baseCurrencyNow
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.ui.components.SanvyaPage
import com.sanvya.app.ui.formatMajorPlain

/**
 * Ported from apps/web/app/loans/page.tsx's `AddLoan` inline modal per
 * docs/mobile/screen-specs/loans.md's Add Loan section (task #27). New
 * file -- Android had no loan-creation screen at all before this pass.
 * Web's modal is used as a dedicated route here, matching this app's own
 * established Accounts/Budgets/Goals/Investments convention.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddLoanScreen(
    onBack: () -> Unit = {},
    onSaved: () -> Unit = {},
    viewModel: LoansViewModel = viewModel(),
) {
    val colors = LocalSanvyaColors.current
    val scope = rememberCoroutineScope()
    val fundingAccounts by viewModel.fundingAccounts.collectAsState()

    var lender by rememberSaveable { mutableStateOf("") }
    var rateType by rememberSaveable { mutableStateOf("fixed") }
    var principal by rememberSaveable { mutableStateOf("") }
    var tenure by rememberSaveable { mutableStateOf("") }
    var rate by rememberSaveable { mutableStateOf("") }
    var emi by rememberSaveable { mutableStateOf("") }
    var emiTouched by rememberSaveable { mutableStateOf(false) }
    var start by rememberSaveable { mutableStateOf(java.time.LocalDate.now().toString()) }
    var dueDay by rememberSaveable { mutableStateOf("") }
    var alertTime by rememberSaveable { mutableStateOf("09:00") }
    var autoMark by rememberSaveable { mutableStateOf(false) }
    var fundingId by rememberSaveable { mutableStateOf("") }
    var saving by rememberSaveable { mutableStateOf(false) }
    var errorText by rememberSaveable { mutableStateOf<String?>(null) }
    var showStartDatePicker by rememberSaveable { mutableStateOf(false) }
    var showTimePicker by rememberSaveable { mutableStateOf(false) }
    var fundingMenuExpanded by rememberSaveable { mutableStateOf(false) }

    val principalMinor = principal.toDoubleOrNull()?.let { fromMajor(it, baseCurrencyNow()).amount } ?: 0L
    val computedEmiMinor = if (rateType == "fixed") emiFromPrincipal(principalMinor, rate.toDoubleOrNull() ?: 0.0, tenure.toIntOrNull() ?: 0) else 0L
    val computedEmiMajor = if (computedEmiMinor > 0) formatMajorPlain(computedEmiMinor, baseCurrencyNow()) else ""
    val emiValue = if (rateType == "variable") "" else if (emiTouched) emi else computedEmiMajor

    SanvyaPage(
        title = S.Loans.addLoan(sRes()),
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
                    label = { Text("Principal (INR)") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
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
                        label = { Text("Monthly EMI (INR)") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.weight(1f),
                    )
                }
            }
            if (rateType == "fixed") {
                if (computedEmiMinor > 0) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(
                            if (emiTouched) "Auto-calculated EMI was ${formatMoney(computedEmiMinor, baseCurrencyNow())}" else "EMI auto-calculated from principal, rate & tenure.",
                            fontSize = 12.sp, color = colors.text2,
                        )
                        if (emiTouched) TextButton(onClick = { emiTouched = false; emi = "" }) { Text(S.Loans.useIt(sRes()), fontSize = 11.sp) }
                    }
                }
            } else {
                Text(
                    "Variable-rate loans: enter each month's EMI from the loan's detail page as bills come in.",
                    fontSize = 12.sp, color = colors.text2,
                )
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Started on", fontSize = 13.sp, color = colors.text2, modifier = Modifier.weight(1f))
                TextButton(onClick = { showStartDatePicker = true }) { Text(start) }
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

            Text(S.Loans.chargedTo(sRes()), fontSize = 13.sp, color = colors.text2)
            ExposedDropdownMenuBox(expanded = fundingMenuExpanded, onExpandedChange = { fundingMenuExpanded = it }) {
                val selected = fundingAccounts.find { it.id == fundingId }
                OutlinedTextField(
                    value = selected?.let { "${it.name}${if (it.isCreditCard) " · credit card" else ""}" } ?: S.Loans.notLinked(sRes()),
                    onValueChange = {}, readOnly = true,
                    modifier = Modifier.fillMaxWidth().menuAnchor(),
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = fundingMenuExpanded) },
                )
                ExposedDropdownMenu(expanded = fundingMenuExpanded, onDismissRequest = { fundingMenuExpanded = false }) {
                    DropdownMenuItem(text = { Text(S.Loans.notLinked(sRes())) }, onClick = { fundingId = ""; fundingMenuExpanded = false })
                    fundingAccounts.forEach { a ->
                        DropdownMenuItem(text = { Text("${a.name}${if (a.isCreditCard) " · credit card" else ""}") }, onClick = { fundingId = a.id; fundingMenuExpanded = false })
                    }
                }
            }
            Text(
                if (fundingAccounts.find { it.id == fundingId }?.isCreditCard == true)
                    S.Loans.chargedToCardHint(sRes())
                else S.Loans.chargedToHint(sRes()),
                fontSize = 11.5.sp, color = colors.text2,
            )

            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Checkbox(checked = autoMark, onCheckedChange = { autoMark = it })
                Column {
                    Text("Auto-mark EMIs paid once due", fontSize = 13.sp, color = colors.text)
                    Text("Past-due EMIs count as paid automatically -- toggle off any time to revert.", fontSize = 12.sp, color = colors.text2)
                }
            }

            errorText?.let { Text(it, color = colors.negative, fontSize = 13.sp) }

            Button(
                onClick = {
                    saving = true
                    errorText = null
                    scope.launch {
                        val err = viewModel.create(
                            lender = lender, principalMajorText = principal,
                            emiMajorText = if (rateType == "variable") null else emiValue.ifBlank { null },
                            interestRateText = rate, tenureText = tenure, startDate = start.ifBlank { null },
                            dueDayText = dueDay, autoMarkPaid = autoMark, rateType = rateType,
                            fundingAccountId = fundingId.ifBlank { null }, alertTimeUtc = localToUtcTime(alertTime),
                        )
                        saving = false
                        if (err != null) errorText = err else onSaved()
                    }
                },
                enabled = !saving && (lender.trim().isNotEmpty() || principal.isNotBlank()),
                modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
            ) {
                Text(if (saving) S.Translation.commonAdding(sRes()) else S.Loans.addLoan(sRes()))
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

