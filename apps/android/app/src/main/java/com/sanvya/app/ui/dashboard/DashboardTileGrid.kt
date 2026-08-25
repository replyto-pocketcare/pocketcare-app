package com.sanvya.app.ui.dashboard

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.sanvya.app.domain.dashboard.GridItem
import com.sanvya.app.domain.dashboard.packRows
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.SanvyaButton
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaText
import com.sanvya.app.ui.shell.LocalWindowClass
import com.sanvya.app.ui.shell.SanvyaWindowClass

/**
 * The dashboard tile grid — web's `.dash-grid`.
 *
 * Rows come from `packRows` in `:domain`, which both platforms share and which
 * is vector-tested; this file only draws what that function decides. Widths
 * become `Row` weights, so a two-of-four tile really is half the row rather
 * than a hardcoded fraction that stops being true when the column count
 * changes.
 *
 * **Column count.** Web is one column below 860px and four above. The native
 * window classes break at 600 and 840, and inventing a fourth breakpoint for
 * one screen would be worse than the 20px of daylight between 840 and 860. So:
 * one column until `EXPANDED`, four from there. A phone and a portrait tablet
 * both stack, which is what web does at those widths too.
 *
 * **The trailing Spacer is load-bearing.** A row that does not fill its columns
 * — the gap `packRows` deliberately leaves, since this is not `dense` — must
 * keep that gap. Without the spacer the row's weights would redistribute and a
 * lone tile would stretch to full width, which is a different layout from the
 * one the packing function computed.
 */
@Composable
fun DashboardTileGrid(
    editing: Boolean,
    isPaid: Boolean,
    onOpen: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val ids by DashboardPrefs.ids.collectAsState()
    val widths by DashboardPrefs.widths.collectAsState()
    val columns = if (LocalWindowClass.current == SanvyaWindowClass.EXPANDED) 4 else 1

    // Premium tiles disappear for an unentitled user rather than rendering
    // locked, mirroring web's `enabled.filter(isPaid || !premium)`. The id
    // stays in storage, so the tile returns the moment they upgrade.
    // `isBuilt` as well as the premium gate. The storage key is web's own, so
    // a saved dashboard can legitimately name a tile this platform has not
    // built yet; rendering it would produce an empty card, which is the dead
    // control the picker is already careful to avoid offering.
    val visible = remember(ids, isPaid) {
        ids.filter { it.isBuilt && (isPaid || !it.isPremium) }
    }
    val spanOf: (TileId) -> Int = { id ->
        (widths[id] ?: DashboardPrefs.defaultWidth).columns.coerceIn(1, columns)
    }
    val rows = remember(visible, widths, columns) {
        packRows(visible.map { GridItem(it.key, spanOf(it)) }, columns)
    }

    if (visible.isEmpty()) {
        EmptyTileGrid(modifier)
        return
    }

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(20.dp)) {
        rows.forEach { row ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(20.dp),
                verticalAlignment = Alignment.Top,
            ) {
                var used = 0
                row.forEach { key ->
                    val id = TileId.from(key) ?: return@forEach
                    val span = spanOf(id)
                    used += span
                    Box(Modifier.weight(span.toFloat())) {
                        TileSlot(
                            id = id,
                            editing = editing,
                            canMoveUp = visible.indexOf(id) > 0,
                            canMoveDown = visible.indexOf(id) < visible.lastIndex,
                            onOpen = { onOpen(id.destination) },
                        )
                    }
                }
                if (used < columns) Spacer(Modifier.weight((columns - used).toFloat()))
            }
        }
    }
}

/** Nothing enabled. Not an error — the user can remove every tile. */
@Composable
private fun EmptyTileGrid(modifier: Modifier = Modifier) {
    val colors = LocalSanvyaColors.current
    SanvyaCard(modifier = modifier.fillMaxWidth(), padding = androidx.compose.foundation.layout.PaddingValues(20.dp)) {
        SanvyaText(S.Dashboard.emptyTitle(sRes()), style = SanvyaType.body)
        SanvyaText(
            S.Dashboard.emptyBody(sRes()),
            style = SanvyaType.statLabel,
            color = colors.text2,
            modifier = Modifier.padding(top = 4.dp),
        )
    }
}

/**
 * One tile, plus the controls that only exist while editing.
 *
 * Web overlays the controls on top of the tile and freezes its interior with
 * `pointer-events: none`. This does the same: in edit mode the tile body is
 * drawn but not clickable, so a drag or a control tap can never fall through to
 * a link inside a tile.
 */
@Composable
private fun TileSlot(
    id: TileId,
    editing: Boolean,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    onOpen: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        TileView(id = id, editing = editing, onOpen = onOpen)
        if (editing) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                // Width first: it is the only control that does nothing on a
                // phone, and putting it where the eye lands first would make a
                // dead button the most prominent thing in edit mode.
                if (LocalWindowClass.current == SanvyaWindowClass.EXPANDED) {
                    EditChip(S.Dashboard.width(sRes())) {
                        DashboardPrefs.setWidth(id, DashboardPrefs.widthOf(id).next())
                    }
                }
                if (canMoveUp) EditChip(S.Dashboard.moveUp(sRes())) { DashboardPrefs.move(id, -1) }
                if (canMoveDown) EditChip(S.Dashboard.moveDown(sRes())) { DashboardPrefs.move(id, 1) }
                Spacer(Modifier.weight(1f))
                EditChip(S.Translation.commonRemove(sRes()), destructive = true) {
                    DashboardPrefs.setEnabled(id, false)
                }
            }
        }
    }
}

@Composable
private fun EditChip(label: String, destructive: Boolean = false, onClick: () -> Unit) {
    val colors = LocalSanvyaColors.current
    SanvyaButton(onClick = onClick, ghost = true) {
        SanvyaText(
            label,
            style = SanvyaType.button,
            color = if (destructive) colors.negative else colors.text,
        )
    }
}
