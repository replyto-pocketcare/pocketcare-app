package com.sanvya.app.ui.investments

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenu
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import android.content.res.Resources
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.domain.investments.AssetClass
import com.sanvya.app.domain.investments.Instrument
import com.sanvya.app.domain.investments.clampSipDay
import com.sanvya.app.domain.investments.isListed
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaRadius
import com.sanvya.app.ui.baseCurrencyNow
import com.sanvya.app.ui.components.DateField
import com.sanvya.app.ui.components.SanvyaPage
import kotlinx.coroutines.launch
import java.time.LocalDate

/**
 * Port of apps/web/src/investments/AddDialog.tsx's AddInvestmentDialog.
 *
 * Two things web has that this did not, both added this pass and both
 * load-bearing rather than cosmetic:
 *
 *  - **The SIP branch.** "SIP" was a selectable type that collected nothing:
 *    no amount, no frequency, no debit day, no source account. The row it
 *    wrote had `planned_id = null` and no `sip_amount`, so a SIP could not be
 *    created on a phone at all, and the Stop-SIP control added the week before
 *    could only ever appear on a holding created on web.
 *  - **The instrument picker.** Symbol and exchange were free text, so every
 *    holding a phone created was written `off_list = 1` -- unpriceable,
 *    unmatchable to a dividend row, and a different thing from the same
 *    instrument added on web.
 *
 * [initialGroupKey] prefills the asset class / exchange from a group tile's
 * "+ Add to {group}" button, matching web's addCtx context.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddHoldingScreen(
    initialGroupKey: String? = null,
    onBack: () -> Unit = {},
    onSaved: () -> Unit = {},
    viewModel: InvestmentsViewModel = viewModel(),
) {
    val colors = LocalSanvyaColors.current
    val res = sRes()
    val scope = rememberCoroutineScope()
    val invAccounts by viewModel.invAccounts.collectAsState()
    val fundingAccounts by viewModel.fundingAccounts.collectAsState()
    val instrumentResults by viewModel.instrumentResults.collectAsState()
    val instrumentQuery by viewModel.instrumentQuery.collectAsState()
    val instrumentExchange by viewModel.instrumentExchange.collectAsState()

    val initialClass = when {
        initialGroupKey?.startsWith("ex:") == true -> AssetClass.STOCK
        initialGroupKey?.startsWith("cls:") == true -> AssetClass.fromKey(initialGroupKey.substring(4))
        else -> AssetClass.STOCK
    }
    val initialExchange = initialGroupKey?.takeIf { it.startsWith("ex:") }?.substring(3)?.takeIf { it != "OTHER" }

    var assetClass by rememberSaveable { mutableStateOf(initialClass) }
    var accountId by rememberSaveable { mutableStateOf(invAccounts.firstOrNull()?.id ?: "") }
    LaunchedEffect(invAccounts) { if (accountId.isBlank()) accountId = invAccounts.firstOrNull()?.id ?: "" }
    // Scope the catalog to the exchange the drill-in came from, so "+ Add to
    // NSE_IN" opens on NSE_IN rather than the whole world.
    LaunchedEffect(initialExchange) { if (initialExchange != null) viewModel.instrumentExchange.value = initialExchange }
    val account = invAccounts.find { it.id == accountId }

    // Web's `listed` toggle: a listed class can still be entered by hand, and
    // then it is off_list like anything else.
    var fromCatalog by rememberSaveable { mutableStateOf(true) }
    // The chosen instrument is a value type, so it is kept as its catalog key
    // (savable) and resolved back out of the current result set.
    var chosenKey by rememberSaveable { mutableStateOf<String?>(null) }
    val chosen: Instrument? = instrumentResults.find { "${it.symbol}|${it.exchange}" == chosenKey }
    val usePicker = isListed(assetClass) && fromCatalog

    var name by rememberSaveable { mutableStateOf("") }
    var quantityText by rememberSaveable { mutableStateOf("") }
    var costText by rememberSaveable { mutableStateOf("") }
    var currentValueText by rememberSaveable { mutableStateOf("") }
    var rateText by rememberSaveable { mutableStateOf("") }
    var maturityText by rememberSaveable { mutableStateOf("") }
    var fundingExisting by rememberSaveable { mutableStateOf(true) }
    var sourceAccountId by rememberSaveable { mutableStateOf(fundingAccounts.firstOrNull()?.id ?: "") }
    var sipAmountText by rememberSaveable { mutableStateOf("") }
    var sipFrequency by rememberSaveable { mutableStateOf(SIP_CYCLES[1]) }
    var sipStartDate by rememberSaveable { mutableStateOf(LocalDate.now().toString()) }
    var sipDayText by rememberSaveable { mutableStateOf(clampSipDay(LocalDate.now().dayOfMonth).toString()) }
    var sipSourceAccountId by rememberSaveable { mutableStateOf(fundingAccounts.firstOrNull()?.id ?: "") }
    LaunchedEffect(fundingAccounts) {
        if (sourceAccountId.isBlank()) sourceAccountId = fundingAccounts.firstOrNull()?.id ?: ""
        if (sipSourceAccountId.isBlank()) sipSourceAccountId = fundingAccounts.firstOrNull()?.id ?: ""
    }
    var saving by rememberSaveable { mutableStateOf(false) }
    var errorText by rememberSaveable { mutableStateOf<String?>(null) }
    var accountMenuExpanded by rememberSaveable { mutableStateOf(false) }
    var sourceMenuExpanded by rememberSaveable { mutableStateOf(false) }
    var sipSourceMenuExpanded by rememberSaveable { mutableStateOf(false) }
    var exchangeMenuExpanded by rememberSaveable { mutableStateOf(false) }

    val isSip = assetClass == AssetClass.SIP
    val isLump = assetClass == AssetClass.FD
    // Web: a catalog instrument trades in its OWN currency, which is not
    // necessarily the demat account's -- an NSE holding in an account
    // denominated in USD is still priced in INR.
    val currency = (if (usePicker) chosen?.currency else null) ?: account?.currency ?: baseCurrencyNow()
    val nameOk = if (usePicker) chosen != null else name.isNotBlank()

    SanvyaPage(title = S.Investments.addInvestment(res)) {
        Column(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(S.Accounts.typeLabel(res), fontSize = 13.sp, color = colors.text2)
            // Six type chips do not fit across a phone, so the row scrolls
            // rather than wrapping -- web wraps because it has the width.
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            ) {
                AssetClass.values().forEach { c ->
                    FilterChip(
                        selected = c == assetClass,
                        onClick = {
                            assetClass = c
                            // Leaving a listed class clears the catalog pick:
                            // a crypto coin is not an NSE ticker.
                            if (!isListed(c)) { fromCatalog = false; chosenKey = null } else fromCatalog = true
                        },
                        label = { Text("${c.icon} ${assetClassDisplayLabel(c.key, res)}", fontSize = 12.sp) },
                    )
                }
            }

            if (invAccounts.size > 1) {
                Text(S.Investments.investmentAccount(res), fontSize = 13.sp, color = colors.text2)
                ExposedDropdownMenuBox(expanded = accountMenuExpanded, onExpandedChange = { accountMenuExpanded = it }) {
                    OutlinedTextField(
                        value = account?.name ?: "",
                        onValueChange = {},
                        readOnly = true,
                        modifier = Modifier.fillMaxWidth().menuAnchor(),
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = accountMenuExpanded) },
                    )
                    ExposedDropdownMenu(expanded = accountMenuExpanded, onDismissRequest = { accountMenuExpanded = false }) {
                        invAccounts.forEach { a ->
                            DropdownMenuItem(text = { Text(a.name) }, onClick = { accountId = a.id; accountMenuExpanded = false })
                        }
                    }
                }
            }

            // --- instrument -------------------------------------------------
            if (isListed(assetClass)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        selected = fromCatalog,
                        onClick = { fromCatalog = true },
                        label = { Text(S.Investments.inOurList(res), fontSize = 12.sp) },
                    )
                    FilterChip(
                        selected = !fromCatalog,
                        onClick = { fromCatalog = false; chosenKey = null },
                        label = { Text(S.Investments.notListed(res), fontSize = 12.sp) },
                    )
                }
            }

            if (usePicker) {
                ExposedDropdownMenuBox(expanded = exchangeMenuExpanded, onExpandedChange = { exchangeMenuExpanded = it }) {
                    OutlinedTextField(
                        value = instrumentExchange ?: S.Investments.allExchanges(res),
                        onValueChange = {},
                        readOnly = true,
                        label = { Text(S.Investments.exchangeLabel(res)) },
                        modifier = Modifier.fillMaxWidth().menuAnchor(),
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = exchangeMenuExpanded) },
                    )
                    ExposedDropdownMenu(expanded = exchangeMenuExpanded, onDismissRequest = { exchangeMenuExpanded = false }) {
                        DropdownMenuItem(
                            text = { Text(S.Investments.allExchanges(res)) },
                            onClick = { viewModel.instrumentExchange.value = null; chosenKey = null; exchangeMenuExpanded = false },
                        )
                        viewModel.catalogExchanges.forEach { ex ->
                            DropdownMenuItem(
                                text = { Text(ex) },
                                onClick = { viewModel.instrumentExchange.value = ex; chosenKey = null; exchangeMenuExpanded = false },
                            )
                        }
                    }
                }
                OutlinedTextField(
                    value = instrumentQuery,
                    onValueChange = { viewModel.instrumentQuery.value = it; chosenKey = null },
                    label = { Text(S.Investments.instrumentSearch(res)) },
                    modifier = Modifier.fillMaxWidth(),
                )
                if (chosen == null) {
                    if (instrumentResults.isEmpty()) {
                        Text(
                            if (instrumentQuery.isBlank()) S.Investments.startTypingInstrument(res) else S.Investments.noInstrumentMatches(res),
                            fontSize = 12.sp,
                            color = colors.text2,
                        )
                    } else {
                        // Eight, not all thirty: this list sits inside the
                        // form's own scroll, so a second scrolling area would
                        // fight it for the gesture. Eight suggestions is what
                        // fits without one.
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            instrumentResults.take(8).forEach { i ->
                                InstrumentRow(i) { chosenKey = "${i.symbol}|${i.exchange}" }
                            }
                        }
                    }
                } else {
                    InstrumentRow(chosen, selected = true) { chosenKey = null }
                }
                Text(S.Investments.catalogSeedNote(res), fontSize = 11.sp, color = colors.text3)
            } else {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text(S.Investments.nameLabel(res, assetClassDisplayLabel(assetClass.key, res))) },
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            // --- amount / quantity ------------------------------------------
            // A SIP is amount-based and collects its amount below, so it never
            // asks for units or a price here -- web does the same.
            if (!isSip) {
                if (isLump) {
                    OutlinedTextField(
                        value = costText,
                        onValueChange = { costText = it },
                        label = { Text(S.Investments.amountInvested(res, currency)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.fillMaxWidth(),
                    )
                } else {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedTextField(
                            value = quantityText,
                            onValueChange = { quantityText = it },
                            label = {
                                Text(if (assetClass == AssetClass.MF) S.Investments.units(res) else S.Investments.qty(res))
                            },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                            modifier = Modifier.weight(1f),
                        )
                        OutlinedTextField(
                            value = costText,
                            onValueChange = { costText = it },
                            label = {
                                Text(
                                    if (assetClass == AssetClass.MF) S.Investments.navAvgCost(res, currency)
                                    else S.Investments.avgCost(res, currency),
                                )
                            },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }

            if (isLump) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = rateText,
                        onValueChange = { rateText = it },
                        label = { Text(S.Investments.interestPa(res)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.weight(1f),
                    )
                    DateField(
                        value = maturityText,
                        onValueChange = { maturityText = it },
                        label = S.Investments.maturityDate(res),
                        modifier = Modifier.weight(1f),
                    )
                }
            }

            // --- SIP ---------------------------------------------------------
            if (isSip) {
                HorizontalDivider()
                OutlinedTextField(
                    value = sipAmountText,
                    onValueChange = { sipAmountText = it },
                    label = { Text(S.Investments.sipAmount(res, currency)) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(S.Investments.sipFrequency(res), fontSize = 13.sp, color = colors.text2)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    SIP_CYCLES.forEach { c ->
                        FilterChip(
                            selected = c == sipFrequency,
                            onClick = { sipFrequency = c },
                            label = { Text(sipFrequencyLabel(c, res), fontSize = 12.sp) },
                        )
                    }
                }
                DateField(
                    value = sipStartDate,
                    onValueChange = { sipStartDate = it },
                    label = S.Investments.sipStartDate(res),
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = sipDayText,
                    // Digits only, two of them: the column is documented 1-28
                    // and the value is clamped into that range on submit by
                    // `clampSipDay`, so a typed 31 becomes 28 rather than a
                    // schedule that walks backwards through February.
                    onValueChange = { sipDayText = it.filter { ch -> ch.isDigit() }.take(2) },
                    label = { Text(S.Investments.sipDebitDay(res)) },
                    placeholder = { Text(S.Investments.sipDebitDayHint(res)) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.fillMaxWidth(),
                )
                if (fundingAccounts.isEmpty()) {
                    Text(S.Investments.addBankFirst(res), fontSize = 12.sp, color = colors.negative)
                } else {
                    val sipSource = fundingAccounts.find { it.id == sipSourceAccountId }
                    ExposedDropdownMenuBox(expanded = sipSourceMenuExpanded, onExpandedChange = { sipSourceMenuExpanded = it }) {
                        OutlinedTextField(
                            value = sipSource?.let { "${it.name} · ${it.balanceFormatted}" } ?: S.Investments.selectAccount(res),
                            onValueChange = {},
                            readOnly = true,
                            label = { Text(S.Investments.debitsFrom(res)) },
                            modifier = Modifier.fillMaxWidth().menuAnchor(),
                            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = sipSourceMenuExpanded) },
                        )
                        ExposedDropdownMenu(expanded = sipSourceMenuExpanded, onDismissRequest = { sipSourceMenuExpanded = false }) {
                            fundingAccounts.forEach { f ->
                                DropdownMenuItem(
                                    text = { Text("${f.name} · ${f.balanceFormatted}") },
                                    onClick = { sipSourceAccountId = f.id; sipSourceMenuExpanded = false },
                                )
                            }
                        }
                    }
                }
                Text(
                    S.Investments.sipNote(
                        res,
                        sipAmountText.ifBlank { S.Investments.theAmount(res) },
                        account?.name ?: S.Investments.thisAccount(res),
                    ),
                    fontSize = 11.sp,
                    color = colors.text3,
                )
            }

            if (!isSip && !isListed(assetClass)) {
                OutlinedTextField(
                    value = currentValueText,
                    onValueChange = { currentValueText = it },
                    label = { Text(S.Investments.currentValueOptional(res, currency)) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            // --- funding ------------------------------------------------------
            // Not offered for a SIP: its money movement IS the recurring
            // transfer, so an existing-vs-new choice here would post a second,
            // imaginary one.
            if (!isSip) {
                HorizontalDivider()
                Text(S.Investments.newOrHold(res), fontSize = 13.sp, color = colors.text2)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        selected = fundingExisting,
                        onClick = { fundingExisting = true },
                        label = { Text(S.Investments.alreadyHold(res), fontSize = 12.sp) },
                    )
                    FilterChip(
                        selected = !fundingExisting,
                        onClick = { fundingExisting = false },
                        enabled = fundingAccounts.isNotEmpty(),
                        label = { Text(S.Investments.newFund(res), fontSize = 12.sp) },
                    )
                }
                if (!fundingExisting) {
                    if (fundingAccounts.isEmpty()) {
                        Text(S.Investments.noFundAccount(res), fontSize = 12.sp, color = colors.negative)
                    } else {
                        val source = fundingAccounts.find { it.id == sourceAccountId }
                        ExposedDropdownMenuBox(expanded = sourceMenuExpanded, onExpandedChange = { sourceMenuExpanded = it }) {
                            OutlinedTextField(
                                value = source?.let { "${it.name} · ${it.balanceFormatted}" } ?: "",
                                onValueChange = {},
                                readOnly = true,
                                label = { Text(S.Investments.deductFrom(res, S.Investments.theAmount(res))) },
                                modifier = Modifier.fillMaxWidth().menuAnchor(),
                                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = sourceMenuExpanded) },
                            )
                            ExposedDropdownMenu(expanded = sourceMenuExpanded, onDismissRequest = { sourceMenuExpanded = false }) {
                                fundingAccounts.forEach { f ->
                                    DropdownMenuItem(
                                        text = { Text("${f.name} · ${f.balanceFormatted}") },
                                        onClick = { sourceAccountId = f.id; sourceMenuExpanded = false },
                                    )
                                }
                            }
                        }
                    }
                } else {
                    Text(S.Investments.existingNote(res), fontSize = 11.sp, color = colors.text3)
                }
            }

            errorText?.let { Text(it, color = colors.negative, fontSize = 13.sp) }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                TextButton(onClick = onBack) { Text(S.Investments.cancel(res)) }
                Button(
                    onClick = {
                        saving = true
                        errorText = null
                        scope.launch {
                            val failure = viewModel.addHolding(
                                investmentAccountId = accountId,
                                assetClass = assetClass,
                                // Gated on `usePicker`, not just on `chosen`:
                                // toggling to "Not listed" after picking must
                                // write an off_list holding, and a stale
                                // selection would quietly make it catalogued.
                                instrument = if (usePicker) chosen else null,
                                name = name,
                                exchange = instrumentExchange,
                                quantityText = quantityText,
                                avgCostMajorText = costText,
                                currentValueMajorText = currentValueText,
                                annualRateText = rateText,
                                maturityDate = maturityText.ifBlank { null },
                                currency = currency,
                                fundingExisting = fundingExisting,
                                fundingSourceAccountId = if (fundingExisting) null else sourceAccountId,
                                sipAmountMajorText = sipAmountText,
                                sipFrequency = sipFrequency,
                                sipStartDate = sipStartDate,
                                sipDayText = sipDayText,
                                sipSourceAccountId = sipSourceAccountId,
                            )
                            saving = false
                            if (failure != null) errorText = investmentFormMessage(failure, res) else onSaved()
                        }
                    },
                    // Web's `canAdd`, which folds in `nameOk = useCatalogPicker
                    // ? !!instrument : !!name.trim()`. Gating the BUTTON rather
                    // than erroring on submit is the point: with the picker open
                    // there is no name field on screen, so an "Enter a name"
                    // error would name a control the user cannot see.
                    enabled = !saving && accountId.isNotBlank() && nameOk,
                    modifier = Modifier.weight(1f),
                ) {
                    Text(if (saving) S.Investments.adding(res) else S.Investments.addInvestment(res))
                }
            }
        }
    }
}

/** Web's SIP_CYCLES. Daily is deliberately absent: `sipFreq` has three
 * translations because web offers three cycles. */
private val SIP_CYCLES = listOf("weekly", "monthly", "yearly")

private fun sipFrequencyLabel(key: String, res: Resources): String = when (key) {
    "weekly" -> S.Investments.sipFreqWeekly(res)
    "yearly" -> S.Investments.sipFreqYearly(res)
    else -> S.Investments.sipFreqMonthly(res)
}

/** One catalog row: ticker and name on the left, exchange and trading
 * currency on the right -- web's InstrumentPicker option, verbatim. */
@Composable
private fun InstrumentRow(instrument: Instrument, selected: Boolean = false, onClick: () -> Unit) {
    val colors = LocalSanvyaColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(SanvyaRadius.radiusSm))
            .background(if (selected) colors.accentGhost else colors.surface)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(instrument.symbol, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = colors.text, maxLines = 1)
            Text(instrument.name, fontSize = 11.sp, color = colors.text2, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Text("${instrument.exchange} · ${instrument.currency}", fontSize = 11.sp, color = colors.text2)
    }
}
