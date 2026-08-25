package com.sanvya.app.ui.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.DASHBOARD_CHART_COLORS
import com.sanvya.app.ui.baseCurrencyNow
import com.sanvya.app.ui.components.Eyebrow
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaText
import com.sanvya.app.ui.formatMoney
import com.sanvya.app.ui.transactions.TransactionRowCard

/**
 * Which tiles actually render something.
 *
 * The `when` has **no `else` branch**, and that is the guard: `TileId` is
 * generated from web's catalog, so the day a fifteenth tile appears there this
 * file stops compiling until somebody decides whether it is built. The
 * Add-a-widget picker reads this same property, so it is structurally
 * impossible for the picker to offer a tile that renders an empty card — the
 * dead control this audit keeps finding.
 */
val TileId.isBuilt: Boolean
    get() = when (this) {
        TileId.RECENT, TileId.SPENDING, TileId.UPCOMING -> true
        TileId.TRENDS,
        TileId.SPLITS,
        TileId.BUDGETS,
        TileId.GOALS,
        TileId.SUBSCRIPTIONS,
        TileId.CASHFLOW,
        TileId.NET_TREND,
        TileId.BY_CATEGORY,
        TileId.BY_LABEL,
        TileId.MONTH_COMPARE,
        TileId.CURRENCIES -> false
    }

/**
 * One tile's content.
 *
 * Each tile owns its own data, exactly as web does — every tile in `tiles.tsx`
 * runs its own `useQuery`. A tile the user has not enabled is never composed,
 * so its query never runs, which is what lets the catalog hold fourteen.
 */
@Composable
fun TileView(id: TileId, editing: Boolean, onOpen: () -> Unit) {
    // While editing, the tile is drawn but not clickable, mirroring web's
    // `pointer-events: none` on the tile body. A tap during edit belongs to the
    // move/remove controls, never to whatever is underneath them.
    val open: (() -> Unit)? = if (editing) null else onOpen
    when (id) {
        TileId.RECENT -> RecentTile(open)
        TileId.SPENDING -> SpendingTile(open)
        TileId.UPCOMING -> UpcomingTile(open)
        else -> Unit
    }
}

@Composable
private fun TileShell(
    title: String,
    onOpen: (() -> Unit)?,
    trailing: @Composable (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    SanvyaCard(
        modifier = Modifier.fillMaxWidth(),
        padding = PaddingValues(20.dp),
        onClick = onOpen,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Box(Modifier.weight(1f)) { Eyebrow(title) }
            trailing?.invoke()
        }
        Spacer(Modifier.height(10.dp))
        content()
    }
}

@Composable
private fun TileEmpty(text: String) {
    SanvyaText(text, style = SanvyaType.statLabel, color = LocalSanvyaColors.current.text2)
}

/* ------------------------------ Recent ------------------------------ */

@Composable
private fun RecentTile(onOpen: (() -> Unit)?) {
    val viewModel: RecentTileViewModel = viewModel()
    val rows by viewModel.rows.collectAsState()

    TileShell(S.Dashboard.tileRecent(sRes()), onOpen) {
        if (rows.isEmpty()) {
            TileEmpty(S.Dashboard.emptyRecent(sRes()))
            return@TileShell
        }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            // The SAME row web renders on Transactions, Search and Statements.
            // It was private inside TransactionsScreen until this tile needed
            // it; a second copy here is the re-inlining the component
            // inventory exists to prevent.
            rows.forEach { item ->
                TransactionRowCard(item = item, onClick = { onOpen?.invoke() })
            }
        }
    }
}

/* ----------------------------- Spending ----------------------------- */

@Composable
private fun SpendingTile(onOpen: (() -> Unit)?) {
    val colors = LocalSanvyaColors.current
    val viewModel: SpendingTileViewModel = viewModel()
    val state by viewModel.state.collectAsState()
    val currency = baseCurrencyNow()

    TileShell(
        title = S.Dashboard.tileSpending(sRes()),
        onOpen = onOpen,
        trailing = if (state.slices.isEmpty()) null else {
            { SanvyaText(formatMoney(state.totalMinor, currency), style = SanvyaType.body) }
        },
    ) {
        if (state.slices.isEmpty()) {
            TileEmpty(S.Dashboard.emptySpending(sRes()))
            return@TileShell
        }
        // Ranked horizontal bars, not a donut. Web's own comment: "a calmer,
        // more legible read than a donut", and bars are sized against the
        // LARGEST category so the leader always fills its track.
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            state.slices.forEachIndexed { index, slice ->
                Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Row(modifier = Modifier.fillMaxWidth()) {
                        SanvyaText(
                            slice.name,
                            style = SanvyaType.statLabel,
                            color = colors.text,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f),
                        )
                        SanvyaText(
                            "${formatMoney(slice.totalMinor, currency)} · ${slice.sharePct}%",
                            style = SanvyaType.statLabel,
                            color = colors.text2,
                        )
                    }
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(7.dp)
                            .clip(RoundedCornerShape(999.dp))
                            .background(colors.surface2),
                    ) {
                        Box(
                            Modifier
                                .fillMaxWidth(slice.fillPct / 100f)
                                .height(7.dp)
                                .clip(RoundedCornerShape(999.dp))
                                .background(DASHBOARD_CHART_COLORS[index % DASHBOARD_CHART_COLORS.size]),
                        )
                    }
                }
            }
            if (state.hiddenCount > 0) {
                SanvyaText(
                    S.Dashboard.moreCategories(sRes(), state.hiddenCount),
                    style = SanvyaType.statLabel,
                    color = colors.text2,
                )
            }
        }
    }
}

/* ----------------------------- Upcoming ----------------------------- */

@Composable
private fun UpcomingTile(onOpen: (() -> Unit)?) {
    val colors = LocalSanvyaColors.current
    val viewModel: UpcomingTileViewModel = viewModel()
    val rows by viewModel.rows.collectAsState()
    val currency = baseCurrencyNow()

    TileShell(S.Dashboard.tileUpcoming(sRes()), onOpen) {
        if (rows.isEmpty()) {
            TileEmpty(S.Dashboard.emptyUpcoming(sRes()))
            return@TileShell
        }
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            rows.forEach { row ->
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.weight(1f)) {
                        SanvyaText(
                            row.name,
                            style = SanvyaType.body,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        SanvyaText(
                            S.Cashflow.next(sRes(), row.dueIso),
                            style = SanvyaType.statLabel,
                            color = colors.text2,
                        )
                    }
                    row.amountMinor?.let {
                        SanvyaText(formatMoney(it, row.currency ?: currency), style = SanvyaType.body)
                    }
                }
            }
        }
    }
}
