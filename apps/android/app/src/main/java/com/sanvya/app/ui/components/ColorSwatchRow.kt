package com.sanvya.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.ui.ACCOUNT_COLORS_HEX
import com.sanvya.app.ui.parseHexColor

/**
 * The palette swatch row.
 *
 * Was inline in `CreateAccountScreen`, private, until Labels needed the same
 * control -- a second copy is the re-inlining the audit's component inventory
 * exists to prevent. Mirrors iOS's `ColorSwatchRow`.
 *
 * The palette is the generated `FormOptions.accountColors`, which is web's own
 * `ACCOUNT_COLORS`. Web's Labels screen uses a free `<input type="color">`
 * instead; Compose has no equivalent, and adopting a free picker on iOS alone
 * would put the two platforms out of step over a control neither spec has
 * settled. A curated palette also cannot produce white-on-white the way a free
 * picker can. Recorded in PARITY_AUDIT.
 */
@Composable
fun ColorSwatchRow(
    selected: String,
    modifier: Modifier = Modifier,
    onSelect: (String) -> Unit,
) {
    val colors = LocalSanvyaColors.current
    FlowRow(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        ACCOUNT_COLORS_HEX.forEach { hex ->
            val isSelected = hex == selected
            Box(
                modifier = Modifier
                    .size(30.dp)
                    .clip(CircleShape)
                    .background(parseHexColor(hex))
                    .border(
                        if (isSelected) 3.dp else 2.dp,
                        if (isSelected) colors.text else colors.border,
                        CircleShape,
                    )
                    .clickable { onSelect(hex) },
            )
        }
    }
}
