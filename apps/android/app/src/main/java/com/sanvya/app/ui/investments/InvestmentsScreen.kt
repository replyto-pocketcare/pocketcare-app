package com.sanvya.app.ui.investments

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaRadius
import kotlinx.coroutines.launch
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes

/**
 * Ported from apps/web/app/investments/page.tsx per
 * docs/mobile/screen-specs/investments.md (task #26). Was completely
 * unbuilt before this pass (2026-08-06) -- an InvestmentsViewModel.kt
 * existed but was dead code (constructor-injected, no Screen, no nav
 * route, ungrouped placeholder shape -- see UiModels.kt's old header
 * comment), same "reported DONE, actually never real" pattern already
 * found and fixed for other screens.
 *
 * Web's grouping (by exchange for stocks, by asset class for everything
 * else) + drill-in navigation is preserved as in-screen state (selected
 * group key), not a separate nav route -- it's just a filtered view of the
 * same list, matching web's own DrillIn being page-local state rather than
 * a route. Edit is inline within the holding row (web's own EditHolding
 * behavior, unlike Budgets/Goals' separate-screen convention -- this
 * screen's edit fields are few enough, and the pattern this literally
 * mirrors, that a dedicated screen would be pure overhead).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InvestmentsScreen(
    onBack: () -> Unit = {},
    onAddInvestment: (groupKey: String?) -> Unit = {},
    onNoInvestmentAccount: () -> Unit = {},
    viewModel: InvestmentsViewModel = viewModel(),
) {
    val groups by viewModel.groups.collectAsState()
    val totalValue by viewModel.totalValueFormatted.collectAsState()
    val totalGain by viewModel.totalGainFormatted.collectAsState()
    val totalGainPositive by viewModel.totalGainPositive.collectAsState()
    val invAccounts by viewModel.invAccounts.collectAsState()
    val colors = LocalSanvyaColors.current
    val scope = rememberCoroutineScope()

    // Drill-in state: which group tile is expanded, or null for the group
    // grid. Bundle-savable (a plain String), matching this session's
    // fold/rotation lifecycle-retrofit convention (P3.19).
    var drilledKey by rememberSaveable { mutableStateOf<String?>(null) }
    val drilledGroup = groups.find { it.key == drilledKey }

    Scaffold(
        containerColor = colors.bg,
        topBar = {
            TopAppBar(
                title = {
                    Text(drilledGroup?.label ?: S.Translation.navInvestments(sRes()), fontWeight = FontWeight.Bold, color = colors.text)
                },
                navigationIcon = {
                    IconButton(onClick = { if (drilledGroup != null) drilledKey = null else onBack() }) {
                        Icon(Icons.Default.ArrowBack, contentDescription = S.Translation.commonBack(sRes()), tint = colors.text2)
                    }
                },
                actions = {
                    if (invAccounts.isNotEmpty()) {
                        IconButton(onClick = { if (invAccounts.isEmpty()) onNoInvestmentAccount() else onAddInvestment(drilledGroup?.key) }) {
                            Icon(Icons.Default.Add, contentDescription = "New investment", tint = colors.accent)
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.bg),
            )
        },
    ) { padding ->
        if (invAccounts.isEmpty()) {
            Box(modifier = Modifier.padding(padding).fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("▤", fontSize = 26.sp)
                    Text(S.Investments.noInvAccountTitle(sRes()), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.text)
                    Text(
                        "Add a demat, stocks, or mutual-funds account to start tracking investments.",
                        fontSize = 14.sp,
                        color = colors.text2,
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    )
                    Button(onClick = onNoInvestmentAccount, modifier = Modifier.padding(top = 4.dp)) {
                        Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Add account")
                    }
                }
            }
            return@Scaffold
        }

        Column(
            modifier = Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            if (drilledGroup == null) {
                PortfolioTotalCard(totalValue, totalGain, totalGainPositive)
                if (groups.isEmpty()) {
                    Box(modifier = Modifier.fillMaxWidth().padding(vertical = 24.dp), contentAlignment = Alignment.Center) {
                        Text("No holdings yet — tap + to add your first investment.", fontSize = 14.sp, color = colors.text2)
                    }
                } else {
                    groups.forEach { g ->
                        GroupTile(group = g, onClick = { drilledKey = g.key })
                    }
                }
            } else {
                drilledGroup.holdings.forEach { h ->
                    HoldingTile(
                        holding = h,
                        onUpdate = { qty, avgCost, curVal, rate ->
                            scope.launch { viewModel.updateHolding(h.id, qty, avgCost, curVal, rate, h.currency) }
                        },
                        onDelete = { viewModel.deleteHolding(h.id) },
                    )
                }
                TextButton(onClick = { onAddInvestment(drilledGroup.key) }) {
                    Text("+ Add to ${drilledGroup.label}", color = colors.accent, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@Composable
private fun PortfolioTotalCard(valueFormatted: String, gainFormatted: String, gainPositive: Boolean) {
    val colors = LocalSanvyaColors.current
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = colors.surface),
        shape = RoundedCornerShape(SanvyaRadius.radiusLg),
    ) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Total portfolio value", fontSize = 12.sp, fontWeight = FontWeight.Medium, color = colors.text2)
            Text(valueFormatted, fontSize = 30.sp, fontWeight = FontWeight.Bold, color = colors.text)
            Text(
                gainFormatted,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = if (gainPositive) colors.positive else colors.negative,
            )
        }
    }
}

@Composable
private fun GroupTile(group: GroupUiModel, onClick: () -> Unit) {
    val colors = LocalSanvyaColors.current
    val tint = if (group.gainPositive) colors.positive else colors.negative
    Card(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
        colors = CardDefaults.cardColors(containerColor = colors.surface),
        shape = RoundedCornerShape(SanvyaRadius.radiusLg),
    ) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Column {
                    Text(group.label, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = colors.text)
                    Text("${group.holdingsCount} holding${if (group.holdingsCount == 1) "" else "s"}", fontSize = 12.sp, color = colors.text2)
                }
                Text(group.gainPctFormatted, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = tint)
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(group.valueFormatted, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = colors.text)
                Text(group.gainFormatted, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = tint)
            }
        }
    }
}

/** "Zerodha-style" holding row, matching web's HoldingTile: left side is
 * label + off-list "untracked" chip + qty; right side is value + gain;
 * bottom row is asset-class meta + FD extras. Tapping the edit icon
 * expands an inline edit form in place (web's EditHolding), matching this
 * screen's own established inline-edit convention (see file header). */
@Composable
private fun HoldingTile(holding: HoldingUiModel, onUpdate: (String, String, String, String) -> Unit, onDelete: () -> Unit) {
    val colors = LocalSanvyaColors.current
    var editing by rememberSaveable(holding.id) { mutableStateOf(false) }
    var showDeleteConfirm by rememberSaveable(holding.id) { mutableStateOf(false) }
    var quantityText by rememberSaveable(holding.id, editing) { mutableStateOf(if (holding.rawQuantity == Math.floor(holding.rawQuantity)) holding.rawQuantity.toLong().toString() else holding.rawQuantity.toString()) }
    var avgCostText by rememberSaveable(holding.id, editing) { mutableStateOf(holding.rawAvgCostMajor) }
    var currentValueText by rememberSaveable(holding.id, editing) { mutableStateOf(holding.rawCurrentValueMajor) }
    var annualRateText by rememberSaveable(holding.id, editing) { mutableStateOf(holding.rawAnnualRate) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = colors.surface),
        shape = RoundedCornerShape(SanvyaRadius.radiusLg),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.Top) {
                Column(modifier = Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(holding.label, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = colors.text)
                        if (holding.offList) {
                            Box(
                                modifier = Modifier.clip(RoundedCornerShape(50)).background(colors.border).padding(horizontal = 6.dp, vertical = 2.dp),
                            ) { Text("untracked", fontSize = 10.sp, color = colors.text2) }
                        }
                    }
                    if (holding.quantityLine.isNotBlank()) Text(holding.quantityLine, fontSize = 12.sp, color = colors.text2)
                }
                Column(horizontalAlignment = Alignment.End) {
                    Text(holding.valueFormatted, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = colors.text)
                    Text(holding.gainFormatted, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = if (holding.gainPositive) colors.positive else colors.negative)
                }
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text(holding.fdExtra?.let { "${holding.metaLine} · $it" } ?: holding.metaLine, fontSize = 11.sp, color = colors.text2)
                Row {
                    IconButton(onClick = { editing = !editing }, modifier = Modifier.size(32.dp)) {
                        Icon(Icons.Default.Edit, contentDescription = S.Investments.edit(sRes()), tint = colors.text2, modifier = Modifier.size(16.dp))
                    }
                    IconButton(onClick = { showDeleteConfirm = true }, modifier = Modifier.size(32.dp)) {
                        Icon(Icons.Default.Delete, contentDescription = S.Investments.remove(sRes()), tint = colors.negative, modifier = Modifier.size(16.dp))
                    }
                }
            }

            if (editing) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = quantityText, onValueChange = { quantityText = it },
                        label = { Text(if (holding.isListedClass) S.Investments.quantity(sRes()) else S.Investments.quantity(sRes())) },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        value = avgCostText, onValueChange = { avgCostText = it },
                        label = { Text("Avg cost (${holding.currency})") },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    if (!holding.isListedClass) {
                        OutlinedTextField(
                            value = currentValueText, onValueChange = { currentValueText = it },
                            label = { Text("Current value (${holding.currency})") },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                    if (holding.fdExtra != null || annualRateText.isNotBlank()) {
                        OutlinedTextField(
                            value = annualRateText, onValueChange = { annualRateText = it },
                            label = { Text("Annual rate (%)") },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TextButton(onClick = { editing = false }) { Text(S.Investments.cancel(sRes())) }
                        Button(onClick = {
                            onUpdate(quantityText, avgCostText, currentValueText, annualRateText)
                            editing = false
                        }) { Text(S.Investments.save(sRes())) }
                    }
                }
            }

            if (showDeleteConfirm) {
                AlertDialog(
                    onDismissRequest = { showDeleteConfirm = false },
                    title = { Text("Remove ${holding.label}?") },
                    text = { Text("This removes the holding. It doesn't reverse any transfer used to fund it.") },
                    confirmButton = {
                        TextButton(onClick = { onDelete(); showDeleteConfirm = false }) { Text(S.Investments.remove(sRes()), color = colors.negative) }
                    },
                    dismissButton = { TextButton(onClick = { showDeleteConfirm = false }) { Text(S.Investments.cancel(sRes())) } },
                )
            }
        }
    }
}
