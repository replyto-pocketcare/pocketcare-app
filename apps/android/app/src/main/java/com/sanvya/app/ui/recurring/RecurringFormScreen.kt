package com.sanvya.app.ui.recurring

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Checkbox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.budgets.TimePickerDialogSimple
import com.sanvya.app.ui.budgets.utcToLocalTime
import com.sanvya.app.ui.components.Eyebrow
import com.sanvya.app.ui.components.ISO_DATE_HINT
import com.sanvya.app.ui.components.SanvyaButton
import com.sanvya.app.ui.components.SanvyaChip
import com.sanvya.app.ui.components.SanvyaInput
import com.sanvya.app.ui.components.SanvyaPage
import com.sanvya.app.ui.components.SanvyaText

/**
 * Create / edit a recurring income or payment.
 *
 * Ported from `apps/web/src/cashflow/RecurringModal.tsx`. This is what the "+"
 * on the Recurring screens now opens — until this existed, both were
 * deliberately without one.
 *
 * It is a `formDestination`, so W2.1's rule applies for free: a full page below
 * 600dp, a dialog at 600dp and up.
 *
 * **Recurring SAVINGS are not created here**, matching web: a SIP is a transfer
 * into an investment account and is set up in Investments, next to the holding
 * it funds.
 *
 * **Absent, recorded in ABSENT-BY-DECISION.md:**
 * - **Preset name chips** ("Salary", "Rent", …). They only fill the name field,
 *   so they are pure convenience, and web's own list is hardcoded English —
 *   porting it would put untranslated strings in a screen that is otherwise
 *   fully localised.
 *
 * **Alert time is no longer in that list.** It shipped as a hardcoded null,
 * which is not "absent by decision" -- the column is what the engine reads to
 * decide when to nudge, so every item created here was quietly unremindable.
 * It is now a time picker, the same Material 3 one the budget forms use.
 */
@Composable
fun RecurringFormScreen(
    slug: RecurringDirectionSlug,
    editingId: String? = null,
    onDone: () -> Unit = {},
    viewModel: RecurringFormViewModel = viewModel(),
) {
    val colors = LocalSanvyaColors.current
    // Read once, in composable scope: LaunchedEffect's block is a suspend
    // lambda and cannot call baseCurrencyNow() itself.
    val currency = com.sanvya.app.ui.baseCurrencyNow()
    val options by viewModel.options.collectAsState()
    val busy by viewModel.busy.collectAsState()
    val error by viewModel.error.collectAsState()
    val existing by remember(editingId) { viewModel.load(editingId) }.collectAsState()

    var name by rememberSaveable { mutableStateOf("") }
    var amount by rememberSaveable { mutableStateOf("") }
    var accountId by rememberSaveable { mutableStateOf<String?>(null) }
    var categoryId by rememberSaveable { mutableStateOf<String?>(null) }
    var frequency by rememberSaveable { mutableStateOf("monthly") }
    var firstDue by rememberSaveable { mutableStateOf(RecurringFormViewModel.todayIso()) }
    var alertTime by rememberSaveable { mutableStateOf(RecurringFormViewModel.defaultAlertTimeLocal()) }
    var autoPost by rememberSaveable { mutableStateOf(false) }
    var showTimePicker by rememberSaveable { mutableStateOf(false) }
    var prefilled by rememberSaveable { mutableStateOf(false) }

    // Fill from the row being edited, once. Re-running on every emission would
    // overwrite what the user is typing each time the watch re-fires.
    LaunchedEffect(existing?.id) {
        val item = existing ?: return@LaunchedEffect
        if (prefilled) return@LaunchedEffect
        prefilled = true
        name = item.name
        amount = item.amount?.let { minor -> majorText(minor, currency) } ?: ""
        accountId = item.accountId
        categoryId = item.categoryId
        frequency = item.frequency
        firstDue = item.nextDue
        // Stored UTC, shown local -- web's `utcToLocalTime(edit?.alert_time_utc)`.
        alertTime = utcToLocalTime(item.alertTimeUtc)
        autoPost = item.autoPost
    }

    // A new item defaults to the first spendable account, as web does.
    LaunchedEffect(options.accounts, editingId) {
        if (editingId == null && accountId == null) accountId = options.accounts.firstOrNull()?.id
    }

    val isPayment = slug == RecurringDirectionSlug.EXPENSE
    val canSave = name.isNotBlank() && amount.toDoubleOrNull() != null && !accountId.isNullOrBlank()

    // Web's own heading: "Add recurring payment" / "Edit recurring income",
    // assembled from modalAdd/modalEdit and dirLabel. NOT the direction screen's
    // "Payments" -- a form titled the same as the list behind it reads as the
    // list, which is exactly the confusion the modal title avoids.
    val what = if (isPayment) S.Cashflow.dirLabelPayment(sRes()) else S.Cashflow.dirLabelIncome(sRes())
    SanvyaPage(
        title = if (editingId != null) S.Cashflow.modalEdit(sRes(), what) else S.Cashflow.modalAdd(sRes(), what),
        modifier = Modifier.verticalScroll(rememberScrollState()),
    ) {
        Field(S.Cashflow.name(sRes())) {
            SanvyaInput(
                value = name,
                onValueChange = { name = it },
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        // "Amount (INR)" -- web's FloatingInput carries the base currency in
        // its label, which is the only place the form says which currency the
        // number is in.
        Field(S.Cashflow.amountCur(sRes(), currency)) {
            SanvyaInput(
                value = amount,
                onValueChange = { amount = it },
                placeholder = S.Cashflow.amount(sRes()),
                enabled = !busy,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                modifier = Modifier.fillMaxWidth(),
            )
        }

        // Account — chips, not a dropdown. This codebase has no select
        // component; chips are how every other form here picks one of a few.
        Field(if (isPayment) S.Cashflow.payFrom(sRes()) else S.Cashflow.depositInto(sRes())) {
            if (options.accounts.isEmpty()) {
                // Web's disabled placeholder option. Without it an empty chip
                // row is indistinguishable from a row still loading.
                SanvyaText(
                    S.Cashflow.selectAccount(sRes()),
                    style = SanvyaType.statLabel,
                    color = colors.text2,
                )
            }
            ChipRow(
                options = options.accounts,
                selectedId = accountId,
                enabled = !busy,
                onSelect = { accountId = it },
            )
        }

        // Web attaches a category to payments only; an income category would
        // show up in expense breakdowns.
        if (isPayment) {
            Field(S.Cashflow.categoryOptional(sRes())) {
                // Web's first <option> is "No category" with an empty value.
                // Here that is a chip: tapping it clears the choice, which is
                // also what re-tapping the active chip does.
                ChipRow(
                    options = listOf(PickerOption("", S.Cashflow.noCategory(sRes()))) + options.categories,
                    selectedId = categoryId ?: "",
                    enabled = !busy,
                    onSelect = { categoryId = it.takeIf { id -> id.isNotEmpty() } },
                )
            }
        }

        Field(S.Cashflow.frequency(sRes())) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                RecurringFormViewModel.FREQUENCIES.forEach { f ->
                    SanvyaChip(
                        label = frequencyLabel(f),
                        active = frequency == f,
                        onClick = { if (!busy) frequency = f },
                    )
                }
            }
        }

        Field(S.Cashflow.firstDue(sRes())) {
            // Plain ISO text, same as Statements — Compose has no date-picker
            // primitive and adopting Material3's on one platform only would put
            // the two out of step. Tracked.
            SanvyaInput(
                value = firstDue,
                onValueChange = { firstDue = it },
                placeholder = ISO_DATE_HINT,
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        // Web's `<input type="time">`. A button carrying the current value
        // rather than a text field: "HH:MM" typed free-hand is a validation
        // problem the platform already solves, and the budget forms next door
        // solve it the same way.
        Field(S.Recurring.alertTime(sRes())) {
            SanvyaButton(
                onClick = { showTimePicker = true },
                ghost = true,
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
            ) {
                SanvyaText(alertTime, style = SanvyaType.button)
            }
        }

        // A checkbox, not a chip: web's control is a checkbox with a
        // consequence line under it, and the consequence is the half that
        // matters -- "off" is not "nothing happens", it is "we ask you first".
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Checkbox(checked = autoPost, onCheckedChange = { if (!busy) autoPost = it }, enabled = !busy)
            Column(modifier = Modifier.padding(start = 4.dp, top = 12.dp)) {
                SanvyaText(S.Cashflow.postAuto(sRes()), style = SanvyaType.body)
                SanvyaText(
                    S.Cashflow.postAutoOff(sRes()),
                    style = SanvyaType.statLabel,
                    color = colors.text2,
                )
            }
        }

        error?.let {
            SanvyaText(it, style = SanvyaType.statLabel, color = colors.negative)
        }

        Spacer(Modifier.height(4.dp))
        SanvyaButton(
            onClick = {
                viewModel.save(
                    editingId = editingId,
                    direction = if (isPayment) "expense" else "income",
                    name = name,
                    amountMajor = amount,
                    accountId = accountId,
                    categoryId = categoryId,
                    frequency = frequency,
                    firstDue = firstDue,
                    alertTimeLocal = alertTime,
                    autoPost = autoPost,
                    onSaved = onDone,
                )
            },
            enabled = !busy && canSave,
            modifier = Modifier.fillMaxWidth(),
        ) {
            // Web: saving ? "Saving…" : edit ? "Save" : "Add". The previous
            // version showed "Create" while busy, which named the action rather
            // than reporting that it was under way.
            SanvyaText(
                when {
                    busy -> S.Cashflow.savingEllipsis(sRes())
                    editingId != null -> S.Cashflow.save(sRes())
                    else -> S.Cashflow.add(sRes())
                },
                style = SanvyaType.button,
            )
        }
        SanvyaButton(
            onClick = onDone,
            ghost = true,
            enabled = !busy,
            modifier = Modifier.fillMaxWidth(),
        ) {
            SanvyaText(S.Cashflow.cancel(sRes()), style = SanvyaType.button)
        }
    }

    // The budget forms' dialog, not a second one. It is `internal` to :app for
    // exactly this -- a second time picker is how two clock conventions end up
    // in one app.
    if (showTimePicker) {
        TimePickerDialogSimple(
            initial = alertTime,
            onDismiss = { showTimePicker = false },
            onConfirm = { alertTime = it; showTimePicker = false },
        )
    }
}

@Composable
private fun Field(label: String, content: @Composable () -> Unit) {
    Eyebrow(label)
    Spacer(Modifier.height(4.dp))
    content()
    Spacer(Modifier.height(12.dp))
}

@Composable
private fun ChipRow(
    options: List<PickerOption>,
    selectedId: String?,
    enabled: Boolean,
    onSelect: (String) -> Unit,
) {
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        options.forEach { option ->
            SanvyaChip(
                label = option.label,
                active = option.id == selectedId,
                onClick = { if (enabled) onSelect(option.id) },
            )
        }
    }
}

/**
 * Minor units back to an editable major-unit string, for the edit prefill.
 *
 * NOT @Composable: it is called from inside a LaunchedEffect, whose block is a
 * suspend lambda and not a composable scope. `minorUnits(currency)` rather than
 * a hardcoded 100 — the same reason the save path uses `fromMajor`.
 */
private fun majorText(minor: Long, currency: String): String {
    val units = com.sanvya.app.domain.money.minorUnits(currency)
    if (units == 0) return minor.toString()
    val divisor = Math.pow(10.0, units.toDouble())
    return (minor / divisor).toString()
}

@Composable
private fun frequencyLabel(frequency: String): String = when (frequency) {
    "daily" -> S.Cashflow.freqDaily(sRes())
    "weekly" -> S.Cashflow.freqWeekly(sRes())
    "yearly" -> S.Cashflow.freqYearly(sRes())
    else -> S.Cashflow.freqMonthly(sRes())
}
