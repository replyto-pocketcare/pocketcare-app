package com.sanvya.app.ui.search

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.text.KeyboardOptions
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.domain.search.SEARCH_TYPES
import com.sanvya.app.domain.search.SearchPrefill
import com.sanvya.app.domain.search.activeFilterCount
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaColors
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaPage
import com.sanvya.app.ui.transactions.TransactionRowCard

/**
 * Search -- ported from apps/web/app/search/page.tsx.
 *
 * The list rows are [TransactionRowCard], the same component Transactions and
 * the dashboard's Recent tile use, because web renders the same
 * `<TransactionTile>` on all three. The filter is domain's, vector-tested.
 *
 * The deep-link prefill (`?q=&type=&account=...`) arrives as [prefill], already
 * decoded by Domain's `searchPrefillFromQuery`. It is applied ONCE, in the view
 * model, exactly as web's effect guards itself with a `prefilled` flag -- a
 * recomposition must not undo what the user has since typed.
 */
@Composable
fun SearchScreen(
    prefill: SearchPrefill? = null,
    onEditTransaction: (String) -> Unit = {},
    viewModel: SearchViewModel = viewModel(),
) {
    LaunchedEffect(prefill) { prefill?.let(viewModel::applyPrefill) }
    val state by viewModel.state.collectAsState()
    val criteria by viewModel.criteria.collectAsState()
    val showFilters by viewModel.showFilters.collectAsState()
    val colors = LocalSanvyaColors.current
    val active = activeFilterCount(criteria)

    SanvyaPage(title = S.Search.title(sRes())) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedTextField(
                value = criteria.query,
                onValueChange = viewModel::setQuery,
                placeholder = { Text(S.Search.searchEverything(sRes())) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                // "Filters" on its own, "Filters · 3" once something is set --
                // web puts the count in the chip so a collapsed panel still
                // says it is doing something.
                val filtersLabel = S.Search.filters(sRes()) + if (active > 0) " · $active" else ""
                Chip(filtersLabel, selected = showFilters, colors = colors) { viewModel.toggleFilters() }
                if (active > 0) {
                    Chip(S.Search.clear(sRes()), selected = false, colors = colors) { viewModel.clearFilters() }
                }
            }

            if (showFilters) {
                SanvyaCard(modifier = Modifier.fillMaxWidth(), padding = PaddingValues(14.dp)) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            SEARCH_TYPES.forEach { ty ->
                                Chip(searchTypeLabel(ty), selected = criteria.type == ty, colors = colors) {
                                    viewModel.setType(ty)
                                }
                            }
                        }

                        // Chips, not a dropdown. Web uses a `<select>`, but this
                        // codebase draws every one-of-a-few choice as chips (see
                        // RecurringFormScreen) and a menu here would be the only
                        // one. "All accounts" is web's empty first option.
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Chip(
                                S.Search.allAccounts(sRes()),
                                selected = criteria.accountId.isEmpty(),
                                colors = colors,
                            ) { viewModel.setAccountId("") }
                            state.accounts.forEach { account ->
                                Chip(
                                    account.name,
                                    selected = criteria.accountId == account.id,
                                    colors = colors,
                                ) { viewModel.setAccountId(account.id) }
                            }
                        }

                        // Both ends labelled. Web's comment says why: an empty
                        // date input gives no clue which end of the range it is.
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            LabelledField(
                                S.Search.fromDate(sRes()),
                                criteria.from,
                                // Plain ISO text, same as Recurring and
                                // Statements and the same as iOS -- see
                                // RecurringFormScreen for why a date picker is
                                // not adopted on one platform only.
                                placeholder = "YYYY-MM-DD",
                                colors = colors,
                                modifier = Modifier.weight(1f),
                                onChange = viewModel::setFrom,
                            )
                            LabelledField(
                                S.Search.toDate(sRes()),
                                criteria.to,
                                placeholder = "YYYY-MM-DD",
                                colors = colors,
                                modifier = Modifier.weight(1f),
                                onChange = viewModel::setTo,
                            )
                        }

                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            LabelledField(
                                S.Search.minAmount(sRes()),
                                criteria.min,
                                colors = colors,
                                modifier = Modifier.weight(1f),
                                numeric = true,
                                onChange = viewModel::setMin,
                            )
                            LabelledField(
                                S.Search.maxAmount(sRes()),
                                criteria.max,
                                colors = colors,
                                modifier = Modifier.weight(1f),
                                numeric = true,
                                onChange = viewModel::setMax,
                            )
                        }
                    }
                }
            }

            Text(
                S.Search.resultsCount(sRes(), state.resultCount),
                fontSize = 13.sp,
                color = colors.text2,
            )
        }

        if (state.items.isEmpty()) {
            SanvyaCard(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
                Text(S.Search.noMatching(sRes()), fontSize = 14.sp, color = colors.text2)
            }
        } else {
            LazyColumn(
                contentPadding = PaddingValues(16.dp, 4.dp, 16.dp, 24.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(state.items, key = { it.id }) { item ->
                    TransactionRowCard(item = item, colors = colors, onClick = { onEditTransaction(item.id) })
                }
            }
        }
    }
}

@Composable
private fun searchTypeLabel(key: String): String = when (key) {
    "income" -> S.Search.typeIncome(sRes())
    "expense" -> S.Search.typeExpense(sRes())
    "transfer" -> S.Search.typeTransfer(sRes())
    else -> S.Search.typeAll(sRes())
}

@Composable
private fun Chip(label: String, selected: Boolean, colors: SanvyaColors, onClick: () -> Unit) {
    AssistChip(
        onClick = onClick,
        label = { Text(label, fontSize = 12.sp) },
        colors = AssistChipDefaults.assistChipColors(
            containerColor = if (selected) colors.accent else colors.surface2,
            labelColor = if (selected) Color.White else colors.text,
        ),
    )
}

@Composable
private fun LabelledField(
    label: String,
    value: String,
    colors: SanvyaColors,
    modifier: Modifier = Modifier,
    placeholder: String? = null,
    numeric: Boolean = false,
    onChange: (String) -> Unit,
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(label, fontSize = 12.sp, color = colors.text2)
        OutlinedTextField(
            value = value,
            onValueChange = onChange,
            placeholder = placeholder?.let { { Text(it) } },
            singleLine = true,
            keyboardOptions = if (numeric) {
                KeyboardOptions(keyboardType = KeyboardType.Decimal)
            } else {
                KeyboardOptions.Default
            },
            modifier = Modifier.fillMaxWidth(),
        )
    }
}
