package com.sanvya.app.ui.accounts

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.ui.components.SanvyaPage
import com.sanvya.app.ui.components.ColorSwatchRow

/**
 * New account — ported from apps/web/app/accounts/new/page.tsx per
 * docs/mobile/screen-specs/accounts.md.
 *
 * The credit-card branch was built 2026-08-28. Until then a card created
 * natively silently dropped its limit, statement day, due day and amount due
 * — every field the Cards screen and its reminders are built on — so a card
 * added on the phone was an inert account with a name.
 *
 * Mirrors iOS's CreateAccountView.swift.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreateAccountScreen(
    onBack: () -> Unit = {},
    onSaved: (accountType: String) -> Unit = {},
    viewModel: CreateAccountViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val colors = LocalSanvyaColors.current

    LaunchedEffect(uiState.savedAccountId) {
        if (uiState.savedAccountId != null) onSaved(uiState.savedType ?: uiState.type)
    }

    SanvyaPage(
        title = S.Accounts.newAccount(sRes()),
        action = {

        },
    ) {
        Column(
            modifier = Modifier.fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            // Load-bearing copy, not decorative -- keep verbatim (spec).
            Text(
                S.Accounts.noBankLink(sRes()),
                fontSize = 13.5.sp,
                color = colors.text2,
            )
            OutlinedTextField(
                value = uiState.name,
                onValueChange = viewModel::setName,
                label = { Text(S.Accounts.accountName(sRes())) },
                modifier = Modifier.fillMaxWidth(),
            )

            Text(S.Accounts.typeLabel(sRes()), fontSize = 13.sp, color = colors.text2)
            ChipRow(
                options = ACCOUNT_TYPES,
                selected = uiState.type,
                label = { it.replace("_", " ").replaceFirstChar { c -> c.uppercase() } },
                onSelect = viewModel::setType,
                colors = colors,
            )

            Text(S.Accounts.currency(sRes()), fontSize = 13.sp, color = colors.text2)
            ChipRow(
                options = ACCOUNT_CURRENCIES,
                selected = uiState.currency,
                label = { it },
                onSelect = viewModel::setCurrency,
                colors = colors,
            )

            Text(S.Accounts.colour(sRes()), fontSize = 13.sp, color = colors.text2)
            ColorSwatchRow(selected = uiState.color) { viewModel.setColor(it) }

            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Checkbox(checked = uiState.includeInNetWorth, onCheckedChange = viewModel::setIncludeInNetWorth)
                Text(S.Accounts.includeShort(sRes()), fontSize = 14.sp, color = colors.text)
            }

            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Checkbox(checked = uiState.allowNegativeEffective, onCheckedChange = viewModel::setAllowNegative)
                Column {
                    Text(S.Accounts.allowNeg(sRes()), fontSize = 14.sp, color = colors.text)
                    Text(
                        if (uiState.allowNegativeEffective) {
                            S.Accounts.allowNegOn(sRes())
                        } else {
                            S.Accounts.allowNegOff(sRes())
                        },
                        fontSize = 12.sp,
                        color = colors.text2,
                    )
                }
            }

            when {
                uiState.isCard -> CardFields(uiState = uiState, viewModel = viewModel)
                uiState.isDemat -> {
                    AmountField(
                        value = uiState.openingBalance,
                        onChange = viewModel::setOpeningBalance,
                        label = S.Accounts.invested(sRes(), uiState.currency),
                    )
                    Text(
                        S.Accounts.dematNote(sRes()),
                        fontSize = 12.sp,
                        color = colors.text2,
                        modifier = Modifier.padding(top = (-4).dp),
                    )
                }
                else -> AmountField(
                    value = uiState.openingBalance,
                    onChange = viewModel::setOpeningBalance,
                    label = S.Accounts.openingBalance(sRes(), uiState.currency),
                )
            }

            Button(
                onClick = { viewModel.save() },
                enabled = uiState.name.isNotBlank() && !uiState.saving,
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
            ) {
                Text(if (uiState.saving) S.Accounts.saving(sRes()) else S.Accounts.save(sRes()))
            }
        }
    }
}

/**
 * The credit-card branch: limit, amount due, and the two cycle days, with the
 * live preview underneath.
 *
 * The preview is not decoration. The roll-forward rule -- enter a balance after
 * the statement has closed and it is due NEXT cycle -- is invisible in the
 * fields themselves, and a due date the user did not expect reads as a bug in
 * the app rather than as the rule it is. Web shows the sentence for exactly
 * that reason, and the date in it comes from Domain, under vectors.
 */
@Composable
private fun CardFields(uiState: CreateAccountUiState, viewModel: CreateAccountViewModel) {
    val colors = LocalSanvyaColors.current
    val res = sRes()
    Text(S.Accounts.creditCardDetails(res), fontSize = 13.sp, color = colors.text2)
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        AmountField(
            value = uiState.creditLimit,
            onChange = viewModel::setCreditLimit,
            label = S.Accounts.creditLimit(res, uiState.currency),
            modifier = Modifier.weight(1f),
        )
        AmountField(
            value = uiState.dueAmount,
            onChange = viewModel::setDueAmount,
            label = S.Accounts.amountDue(res, uiState.currency),
            modifier = Modifier.weight(1f),
        )
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        OutlinedTextField(
            value = uiState.statementDay,
            onValueChange = viewModel::setStatementDay,
            label = { Text(S.Accounts.statementDay(res)) },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            modifier = Modifier.weight(1f),
        )
        OutlinedTextField(
            value = uiState.dueDay,
            onValueChange = viewModel::setDueDay,
            label = { Text(S.Accounts.dueDay(res)) },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            modifier = Modifier.weight(1f),
        )
    }
    uiState.cardPreview?.let { preview ->
        val amount = "${uiState.currency} ${uiState.dueAmount}"
        val date = formatCardDay(preview.dueOn)
        Text(
            if (preview.thisCycle) {
                S.Accounts.dueThisCycle(res, amount, date)
            } else {
                S.Accounts.dueNextCycle(res, amount, date)
            },
            fontSize = 12.5.sp,
            color = colors.text2,
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(10.dp))
                .background(colors.surface2)
                .border(1.dp, colors.border, RoundedCornerShape(10.dp))
                .padding(horizontal = 12.dp, vertical = 9.dp),
        )
    }
}

/**
 * `yyyy-MM-dd` in the device's own short date format.
 *
 * Web calls `toLocaleDateString()` with no locale, which is the browser's.
 * `DateFormat.SHORT` with the default locale is the same promise on Android:
 * the user's format, not ours.
 */
private fun formatCardDay(iso: String): String = runCatching {
    java.time.LocalDate.parse(iso).format(
        java.time.format.DateTimeFormatter.ofLocalizedDate(java.time.format.FormatStyle.SHORT),
    )
}.getOrDefault(iso)

/** A money field: decimal keyboard, and web's "digits, dot and minus" filter. */
@Composable
private fun AmountField(
    value: String,
    onChange: (String) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
) {
    OutlinedTextField(
        value = value,
        onValueChange = { v -> onChange(v.filter { it.isDigit() || it == '.' || it == '-' }) },
        label = { Text(label) },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        modifier = modifier.fillMaxWidth(),
    )
}

@Composable
internal fun <T> ChipRow(
    options: List<T>,
    selected: T,
    label: (T) -> String,
    onSelect: (T) -> Unit,
    colors: com.sanvya.app.theme.SanvyaColors,
) {
    androidx.compose.foundation.layout.FlowRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        options.forEach { opt ->
            val isSelected = opt == selected
            AssistChip(
                onClick = { onSelect(opt) },
                label = { Text(label(opt), fontSize = 13.sp) },
                colors = AssistChipDefaults.assistChipColors(
                    containerColor = if (isSelected) colors.accent else colors.surface,
                    labelColor = if (isSelected) Color.White else colors.text,
                ),
            )
        }
    }
}
