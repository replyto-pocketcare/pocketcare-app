package com.sanvya.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.LocalSanvyaShadows
import com.sanvya.app.theme.SanvyaMetrics
import com.sanvya.app.theme.SanvyaShape

/**
 * `.card` — surface, hairline border, 24dp radius, the two-layer card shadow.
 *
 * `onClick` turns it into web's `a.card`, which additionally gets the gentler
 * 0.985 press scale rather than the standard 0.97.
 */
@Composable
fun SanvyaCard(
    modifier: Modifier = Modifier,
    shape: Shape = SanvyaShape.radiusLg,
    padding: PaddingValues = PaddingValues(16.dp),
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = LocalSanvyaColors.current
    val interaction = remember { MutableInteractionSource() }
    var m = modifier
    if (onClick != null) m = m.liftPress(interaction)
    m = m
        .sanvyaShadow(LocalSanvyaShadows.current.shadow, shape)
        .clip(shape)
        .background(colors.surface)
        .border(1.dp, colors.border, shape)
    if (onClick != null) {
        m = m.clickable(interactionSource = interaction, indication = null, onClick = onClick)
    }
    Column(modifier = m.padding(padding), content = content)
}

/**
 * `.row-tile` — a row inside a card, separated by space and a recessed surface
 * rather than a hairline divider. Web moved off dividers deliberately; keep it.
 */
@Composable
fun RowTile(
    modifier: Modifier = Modifier,
    open: Boolean = false,
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = LocalSanvyaColors.current
    val interaction = remember { MutableInteractionSource() }
    val shape = SanvyaShape.row
    var m = modifier
        .clip(shape)
        .background(if (open) colors.accentGhost else colors.surface2)
    if (onClick != null) {
        m = m.press(interaction)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
    }
    Column(modifier = m.padding(horizontal = 14.dp, vertical = 11.dp), content = content)
}

/** `.row-stack` — the 6dp gap between row tiles. */
@Composable
fun RowStack(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) = Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(6.dp), content = content)

/**
 * `.tap-row` — a tappable row that highlights *itself* rather than its
 * container. Web sets `-webkit-tap-highlight-color: transparent` globally and
 * gives each row its own feedback for exactly this reason: a tap inside a card
 * used to flash the whole card.
 */
@Composable
fun TapRow(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(10.dp))
            .press(interaction)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick),
        content = content,
    )
}

/**
 * `.list-grid` — `repeat(auto-fill, minmax(min(320px, 100%), 1fr))`.
 *
 * `GridCells.Adaptive` is the same rule: as many equal columns as fit at the
 * minimum width, one column when the viewport is narrower than the minimum.
 */
@Composable
fun ListGrid(
    modifier: Modifier = Modifier,
    minColumnWidth: Dp = SanvyaMetrics.ListGrid.minColumnWidth,
    contentPadding: PaddingValues = PaddingValues(0.dp),
    content: LazyGridScope.() -> Unit,
) = LazyVerticalGrid(
    columns = GridCells.Adaptive(minColumnWidth),
    modifier = modifier,
    contentPadding = contentPadding,
    horizontalArrangement = Arrangement.spacedBy(SanvyaMetrics.ListGrid.gap),
    verticalArrangement = Arrangement.spacedBy(SanvyaMetrics.ListGrid.gap),
    content = content,
)
