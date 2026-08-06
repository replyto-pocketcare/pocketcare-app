package com.sanvya.app.ui.investments

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
import com.sanvya.app.domain.investments.AssetClass
import com.sanvya.app.theme.LocalSanvyaColors
import kotlinx.coroutines.launch

/**
 * Scoped-down port of apps/web/src/investments/AddDialog.tsx's
 * AddInvestmentDialog per docs/mobile/screen-specs/investments.md's
 * Deferred section (task #26, new file 2026-08-06). Deferred vs. web:
 * the live instrument catalog picker (InstrumentPicker/ExchangeSelect --
 * every holding here is entered free-text/manually, i.e. always
 * off_list=true) and SIP recurring-transfer setup. Kept, and REAL (not
 * cosmetic): the existing-vs-new funding choice and its actual
 * transfer/adjustment transaction write (InvestmentsRepository.addHolding),
 * matching web's write.ts exactly -- skipping that would silently break
 * ledger integrity for any holding added on mobile (CLAUDE.md golden rule
 * "balances are derived from an append-only ledger").
 *
 * [initialGroupKey] prefills the asset class / exchange from a group
 * tile's "+ Add to {group}" button, matching web's addCtx context.
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
    val scope = rememberCoroutineScope()
    val invAccounts by viewModel.invAccounts.collectAsState()
    val fundingAccounts by viewModel.fundingAccounts.collectAsState()

    val initialClass = when {
        initialGroupKey?.startsWith("ex:") == true -> AssetClass.STOCK
        initialGroupKey?.startsWith("cls:") == true -> AssetClass.fromKey(initialGroupKey.substring(4))
        else -> AssetClass.STOCK
    }
    val initialExchange = initialGroupKey?.takeIf { it.startsWith("ex:") }?.substring(3)?.takeIf { it != "OTHER" }

    var assetClass by rememberSaveable { mutableStateOf(initialClass) }
    var accountId by rememberSaveable { mutableStateOf(invAccounts.firstOrNull()?.id ?: "") }
    LaunchedEffect(invAccounts) { if (accountId.isBlank()) accountId = invAccounts.firstOrNull()?.id ?: "" }
    val account = invAccounts.find { it.id == accountId }
    val currency = account?.currency ?: "INR"

    var name by rememberSaveable { mutableStateOf("") }
    var exchange by rememberSaveable { mutableStateOf(initialExchange ?: "") }
    var quantityText by rememberSaveable { mutableStateOf("") }
    var costText by rememberSaveable { mutableStateOf("") }
    var currentValueText by rememberSaveable { mutableStateOf("") }
    var rateText by rememberSaveable { mutableStateOf("") }
    var maturityText by rememberSaveable { mutableStateOf("") }
    var fundingExisting by rememberSaveable { mutableStateOf(true) }
    var sourceAccountId by rememberSaveable { mutableStateOf(fundingAccounts.firstOrNull()?.id ?: "") }
    LaunchedEffect(fundingAccounts) { if (sourceAccountId.isBlank()) sourceAccountId = fundingAccounts.firstOrNull()?.id ?: "" }
    var saving by rememberSaveable { mutableStateOf(false) }
    var errorText by rememberSaveable { mutableStateOf<String?>(null) }
    var classMenuExpanded by rememberSaveable { mutableStateOf(false) }
    var accountMenuExpanded by rememberSaveable { mutableStateOf(false) }
    var sourceMenuExpanded by rememberSaveable { mutableStateOf(false) }

    val isLump = assetClass == AssetClass.FD

    Scaffold(
        containerColor = colors.bg,
        topBar = {
            TopAppBar(
                title = { Text("Add investment", fontWeight = FontWeight.Bold, color = colors.text) },
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
            Text("Type", fontSize = 13.sp, color = colors.text2)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                AssetClass.values().forEach { c ->
                    FilterChip(
                        selected = c == assetClass,
                        onClick = { assetClass = c },
                        label = { Text("${c.icon} ${c.label}", fontSize = 12.sp) },
                    )
                }
            }

            if (invAccounts.size > 1) {
                Text("Investment account", fontSize = 13.sp, color = colors.text2)
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

            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text(if (assetClass == AssetClass.STOCK || assetClass == AssetClass.MF) "Symbol / name" else "Name") },
                placeholder = { Text("e.g. ${if (assetClass == AssetClass.STOCK) "RELIANCE" else assetClass.label}") },
                modifier = Modifier.fillMaxWidth(),
            )
            if (assetClass == AssetClass.STOCK) {
                OutlinedTextField(
                    value = exchange,
                    onValueChange = { exchange = it.uppercase() },
                    label = { Text("Exchange") },
                    placeholder = { Text("NSE / BSE") },
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            if (isLump) {
                OutlinedTextField(
                    value = costText,
                    onValueChange = { costText = it },
                    label = { Text("Amount invested ($currency)") },
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.fillMaxWidth(),
                )
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = quantityText,
                        onValueChange = { quantityText = it },
                        label = { Text(assetClass.unitWord.replaceFirstChar { it.uppercase() }.ifBlank { "Quantity" }) },
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.weight(1f),
                    )
                    OutlinedTextField(
                        value = costText,
                        onValueChange = { costText = it },
                        label = { Text(if (assetClass == AssetClass.MF || assetClass == AssetClass.SIP) "NAV / avg cost" else "Avg cost ($currency)") },
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.weight(1f),
                    )
                }
            }

            if (assetClass == AssetClass.FD) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = rateText,
                        onValueChange = { rateText = it },
                        label = { Text("Interest % p.a.") },
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.weight(1f),
                    )
                    OutlinedTextField(
                        value = maturityText,
                        onValueChange = { maturityText = it },
                        label = { Text("Maturity (YYYY-MM-DD)") },
                        modifier = Modifier.weight(1f),
                    )
                }
            }
            if (assetClass != AssetClass.STOCK && assetClass != AssetClass.MF && assetClass != AssetClass.SIP) {
                OutlinedTextField(
                    value = currentValueText,
                    onValueChange = { currentValueText = it },
                    label = { Text("Current value ($currency, optional)") },
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            HorizontalDivider()
            Text("Is this money already invested, or new?", fontSize = 13.sp, color = colors.text2)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = fundingExisting, onClick = { fundingExisting = true }, label = { Text("Already hold it") })
                FilterChip(
                    selected = !fundingExisting,
                    onClick = { fundingExisting = false },
                    enabled = fundingAccounts.isNotEmpty(),
                    label = { Text("Fund it now") },
                )
            }
            if (!fundingExisting) {
                if (fundingAccounts.isEmpty()) {
                    Text("Add a funding account first.", fontSize = 12.sp, color = colors.negative)
                } else {
                    val source = fundingAccounts.find { it.id == sourceAccountId }
                    ExposedDropdownMenuBox(expanded = sourceMenuExpanded, onExpandedChange = { sourceMenuExpanded = it }) {
                        OutlinedTextField(
                            value = source?.let { "${it.name} · ${it.balanceFormatted}" } ?: "",
                            onValueChange = {},
                            readOnly = true,
                            label = { Text("Deduct from") },
                            modifier = Modifier.fillMaxWidth().menuAnchor(),
                            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = sourceMenuExpanded) },
                        )
                        ExposedDropdownMenu(expanded = sourceMenuExpanded, onDismissRequest = { sourceMenuExpanded = false }) {
                            fundingAccounts.forEach { f ->
                                DropdownMenuItem(text = { Text("${f.name} · ${f.balanceFormatted}") }, onClick = { sourceAccountId = f.id; sourceMenuExpanded = false })
                            }
                        }
                    }
                }
            }

            errorText?.let { Text(it, color = colors.negative, fontSize = 13.sp) }

            Button(
                onClick = {
                    saving = true
                    errorText = null
                    scope.launch {
                        val err = viewModel.addHolding(
                            investmentAccountId = accountId,
                            assetClass = assetClass,
                            name = name,
                            exchange = exchange.ifBlank { null },
                            quantityText = quantityText,
                            avgCostMajorText = costText,
                            currentValueMajorText = currentValueText,
                            annualRateText = rateText,
                            maturityDate = maturityText.ifBlank { null },
                            currency = currency,
                            fundingExisting = fundingExisting,
                            fundingSourceAccountId = if (fundingExisting) null else sourceAccountId,
                        )
                        saving = false
                        if (err != null) errorText = err else onSaved()
                    }
                },
                enabled = !saving && accountId.isNotBlank(),
                modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
            ) {
                Text(if (saving) "Adding…" else "Add investment")
            }
        }
    }
}
