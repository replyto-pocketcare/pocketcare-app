package com.sanvya.app.ui.accounts

import android.content.res.Resources
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
// `item` and `items(count)` are MEMBERS of LazyGridScope and arrive with the
// scope; only the `items(List<T>)` overload below is an extension that needs an
// import of its own.
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaColors
import com.sanvya.app.theme.SanvyaRadius
import com.sanvya.app.ui.accountColor
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaPage
import com.sanvya.app.ui.components.Skeleton

/**
 * Accounts list — ported from apps/web/app/accounts/page.tsx per
 * docs/mobile/screen-specs/accounts.md.
 *
 * The spec deferred web's MultiCurrencyCard; it is built now
 * ([AcrossCurrenciesCard]), so a user holding two currencies sees the same
 * share bar, native amounts and base-converted amounts web shows.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountsScreen(
    onBack: () -> Unit = {},
    onNewAccount: () -> Unit = {},
    onEditAccount: (String) -> Unit = {},
    viewModel: AccountsViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val showSkeleton by viewModel.showSkeleton.collectAsState()
    val colors = LocalSanvyaColors.current

    SanvyaPage(
        title = S.Accounts.title(sRes()),
        action = {
            if (uiState.archivedCount > 0) {
                AssistChip(
                    onClick = { viewModel.toggleShowArchived() },
                    label = {
                        Text(
                            if (uiState.showArchived) S.Accounts.hideArchived(sRes()) else S.Accounts.showArchived(sRes(), uiState.archivedCount),
                            fontSize = 12.sp,
                        )
                        },
                        modifier = Modifier.padding(end = 8.dp),
                    )
                }
                IconButton(onClick = onNewAccount) {
                    Icon(Icons.Default.Add, contentDescription = S.Accounts.newAccount(sRes()), tint = colors.accent)
                }
        },
    ) {
        if (uiState.visible.isEmpty() && showSkeleton) {
            // Web's `CardsSkeleton count={4} minWidth={260}` -- the same four
            // cards in the same adaptive grid, so the screen does not resize
            // when the real accounts land.
            LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 260.dp),
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(ACCOUNT_SKELETON_CARDS) { _ ->
                    SanvyaCard(modifier = Modifier.fillMaxWidth()) {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Skeleton(height = 12.dp, modifier = Modifier.fillMaxWidth(0.4f))
                            Skeleton(height = 24.dp, modifier = Modifier.fillMaxWidth(0.7f))
                        }
                    }
                }
            }
        } else if (uiState.visible.isEmpty()) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                Text(S.Accounts.noAccounts(sRes()), color = colors.text2, fontSize = 14.sp)
            }
        } else {
            LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 260.dp),
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                // Web renders <MultiCurrencyCard /> above the grid. In a
                // LazyVerticalGrid the equivalent is a full-span item, which
                // keeps one scrolling container instead of nesting the grid
                // inside an outer scroll (illegal in Compose -- unbounded
                // height).
                uiState.breakdown?.let { breakdown ->
                    item(span = { GridItemSpan(maxLineSpan) }, key = "across-currencies") {
                        AcrossCurrenciesCard(breakdown = breakdown, colors = colors)
                    }
                }
                items(uiState.visible, key = { it.id }) { acct ->
                    AccountCard(
                        acct = acct,
                        colors = colors,
                        onToggleIncludeInNetWorth = { viewModel.toggleIncludeInNetWorth(acct.id, acct.includeInNetWorth) },
                        onUnarchive = { viewModel.setArchived(acct.id, false) },
                        onEdit = { onEditAccount(acct.id) },
                    )
                }
            }
        }
    }
}

@Composable
private fun AccountCard(
    acct: AccountUiModel,
    colors: SanvyaColors,
    onToggleIncludeInNetWorth: () -> Unit,
    onUnarchive: () -> Unit,
    onEdit: () -> Unit,
) {
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(SanvyaRadius.radiusLg))
            .background(colors.surface)
            .alpha(if (acct.isArchived) 0.6f else 1f),
    ) {
        Box(
            modifier = Modifier
                .width(6.dp)
                .fillMaxHeight()
                .background(accountColor(acct.color, acct.id)),
        )
        Column(
            modifier = Modifier.padding(18.dp).weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                text = accountTypeLabel(sRes(), acct.type) + " · " + acct.currency +
                    if (acct.isArchived) " · " + S.Accounts.archivedTag(sRes()) else "",
                fontSize = 12.sp,
                color = colors.text2,
            )
            Text(acct.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = colors.text)
            Text(acct.balance, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = colors.text)
            Row(
                modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (acct.isArchived) {
                    AssistChip(onClick = onUnarchive, label = { Text(S.Accounts.unarchive(sRes()), fontSize = 12.sp) })
                } else {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.clickable(onClick = onToggleIncludeInNetWorth),
                    ) {
                        Checkbox(checked = acct.includeInNetWorth, onCheckedChange = { onToggleIncludeInNetWorth() })
                        Text(S.Accounts.inNetWorth(sRes()), fontSize = 12.sp, color = colors.text2)
                    }
                }
                AssistChip(onClick = onEdit, label = { Text(S.Accounts.edit(sRes()), fontSize = 12.sp) })
            }
        }
    }
}

/**
 * The localised name of an account type.
 *
 * Web is `t(`type.${account.type}`, account.type.replace("_", " "))` -- a
 * lookup with the raw type as its fallback, so a type added to the schema
 * before its string still renders as something readable. The `else` branch is
 * that fallback, not a shrug.
 */
private fun accountTypeLabel(res: Resources, type: String): String = when (type) {
    "savings" -> S.Accounts.typeSavings(res)
    "current" -> S.Accounts.typeCurrent(res)
    "credit_card" -> S.Accounts.typeCreditCard(res)
    "cash" -> S.Accounts.typeCash(res)
    "mutual_funds" -> S.Accounts.typeMutualFunds(res)
    "stocks" -> S.Accounts.typeStocks(res)
    "demat" -> S.Accounts.typeDemat(res)
    else -> type.replace("_", " ")
}

/**
 * "Across currencies" — where the money is held, converted to base.
 *
 * Port of web's `MultiCurrencyCard` (accounts/page.tsx): a stacked share bar
 * over one row per currency, each showing the native amount and — for anything
 * that is not the base currency — its converted value.
 */
@Composable
private fun AcrossCurrenciesCard(breakdown: CurrencyBreakdownUiModel, colors: SanvyaColors) {
    // Web's CCY_COLORS, in order. A palette, not theming: the bar segments only
    // have to be distinguishable from each other.
    val palette = listOf(colors.accent, colors.teal, colors.forest, colors.warning, colors.positive, colors.accentSoft)
    SanvyaCard(modifier = Modifier.fillMaxWidth(), padding = PaddingValues(20.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Bottom,
            ) {
                Text(S.Accounts.acrossCurrencies(sRes()), fontSize = 17.sp, fontWeight = FontWeight.Bold, color = colors.text)
                Text(
                    S.Accounts.totalCurrencies(sRes(), breakdown.totalFormatted, breakdown.slices.size),
                    fontSize = 13.sp,
                    color = colors.text2,
                )
            }

            // Stacked share bar. `weight` rather than a fraction of a measured
            // width: Row already distributes by weight, and a zero-share slice
            // must contribute nothing rather than a hairline.
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(12.dp)
                    .clip(RoundedCornerShape(999.dp))
                    .background(colors.surface2),
            ) {
                breakdown.slices.forEachIndexed { i, slice ->
                    if (slice.barSharePct > 0f) {
                        Box(
                            modifier = Modifier
                                .weight(slice.barSharePct)
                                .fillMaxHeight()
                                .background(palette[i % palette.size]),
                        )
                    }
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                breakdown.slices.forEachIndexed { i, slice ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Row(
                            modifier = Modifier.weight(1f),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(9.dp)
                                    .clip(RoundedCornerShape(999.dp))
                                    .background(palette[i % palette.size]),
                            )
                            Text(slice.currency, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = colors.text)
                            Text(slice.nativeFormatted, fontSize = 13.sp, color = colors.text2)
                        }
                        Text(
                            // The base currency shows no "≈ base" line -- it
                            // would restate the amount already on the row.
                            (if (slice.isBase) "" else S.Accounts.approx(sRes(), slice.baseFormatted)) + "${slice.sharePct}%",
                            fontSize = 13.sp,
                            color = colors.text2,
                        )
                    }
                }
            }

            Text(S.Accounts.convertedNote(sRes(), breakdown.base), fontSize = 11.5.sp, color = colors.text2)
        }
    }
}

/**
 * Placeholder cards drawn while the first sync lands.
 *
 * Web's `CardsSkeleton count={4}`; kept identical so the two clients settle at
 * the same visual weight while they wait.
 */
private const val ACCOUNT_SKELETON_CARDS = 4
