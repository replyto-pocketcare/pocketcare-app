package com.sanvya.app.ui.transactions

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.ui.components.SanvyaPage

/**
 * Transactions list — ported from apps/web/app/transactions/page.tsx +
 * src/ui/TransactionTile.tsx per docs/mobile/screen-specs/transactions.md.
 *
 * Split-row collapsing was deferred by that spec and shipped 2026-08-26: a
 * split expense writes up to three ledger rows, and until then this list showed
 * one dinner as three lines with three different amounts where the browser has
 * always shown one. It lives in the view model, not here — see
 * `TransactionsViewModel`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TransactionsScreen(
    onBack: () -> Unit = {},
    onAddTransaction: () -> Unit = {},
    onEditTransaction: (String) -> Unit = {},
    viewModel: TransactionsViewModel = viewModel(),
) {
    val items by viewModel.items.collectAsState()
    val query by viewModel.query.collectAsState()
    val typeFilter by viewModel.typeFilter.collectAsState()
    val colors = LocalSanvyaColors.current

    SanvyaPage(
        title = S.Transactions.title(sRes()),
        action = {
            IconButton(onClick = onAddTransaction) {
                Icon(Icons.Default.Add, contentDescription = S.Transactions.addTitle(sRes()), tint = colors.accent)
            }
        },
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Column(Modifier.padding(16.dp, 12.dp, 16.dp, 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    value = query,
                    onValueChange = viewModel::setQuery,
                    placeholder = { Text(S.Transactions.searchPlaceholder(sRes())) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TX_TYPE_FILTERS.forEach { ty ->
                        val selected = ty == typeFilter
                        AssistChip(
                            onClick = { viewModel.setTypeFilter(ty) },
                            // The chip labels are translated strings, not the
                            // filter KEY capitalised. `ty.replaceFirstChar {}`
                            // rendered "All"/"Income" in every language.
                            label = { Text(txTypeFilterLabel(ty), fontSize = 12.sp) },
                            colors = AssistChipDefaults.assistChipColors(
                                containerColor = if (selected) colors.accent else colors.surface2,
                                labelColor = if (selected) Color.White else colors.text,
                            ),
                        )
                    }
                }
            }

            if (items.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(S.Transactions.noMatching(sRes()), color = colors.text2, fontSize = 14.sp)
                }
            } else {
                LazyColumn(
                    contentPadding = PaddingValues(16.dp, 4.dp, 16.dp, 24.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(items, key = { it.id }) { item ->
                        TransactionRowCard(item = item, colors = colors, onClick = { onEditTransaction(item.id) })
                    }
                }
            }
        }
    }
}

/**
 * The translated label for a type-filter key.
 *
 * Shared with the Search screen, which offers the same four chips from the same
 * `search` namespace on web -- the keys differ per namespace, the mapping does
 * not, so it is written once here.
 */
@Composable
fun txTypeFilterLabel(key: String): String = when (key) {
    "income" -> S.Transactions.filterIncome(sRes())
    "expense" -> S.Transactions.filterExpense(sRes())
    "transfer" -> S.Transactions.filterTransfer(sRes())
    else -> S.Transactions.filterAll(sRes())
}
