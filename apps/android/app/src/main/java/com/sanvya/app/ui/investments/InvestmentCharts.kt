package com.sanvya.app.ui.investments

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sanvya.app.domain.insights.SeriesPoint
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.ui.components.SanvyaDonutChart
import com.sanvya.app.ui.components.resolveChartColor
import kotlin.math.abs
import kotlin.math.max

/**
 * The two Investments-only charts, and only the two.
 *
 * The donut, the area and the plain bars all already exist in
 * `ui/components/Charts.kt` and are reused as-is -- adding a charting library
 * for a screen the app can already draw would be the expensive way to get the
 * same picture, and the palette would stop matching Insights.
 *
 * What Charts.kt genuinely cannot draw is a SIGNED bar. `SanvyaBarsChart`
 * scales every bar as `value / max` from a zero baseline, so a losing group
 * renders as a bar of negative height -- which Compose clamps to nothing, and
 * the loss disappears from a chart whose entire subject is gains and losses.
 * Hence [SignedBarsChart].
 *
 * The donut gets a LEGEND here rather than the tooltip web uses: a tooltip
 * needs a hover, and a phone has none, so on native the labels have to be on
 * the screen or they do not exist.
 */

/** A slice as the donut and its legend need it. */
data class DonutSlice(val label: String, val valueMajor: Double, val amountFormatted: String, val sharePct: Double)

/**
 * Allocation donut plus an on-screen legend.
 *
 * [centerLabel]/[centerValue] are web's centred total. The legend shows each
 * slice's own formatted amount rather than recomputing one, so the masking
 * rule (hide-amounts) is honoured here exactly as it is everywhere else.
 */
@Composable
fun AllocationDonut(
    slices: List<DonutSlice>,
    centerLabel: String,
    centerValue: String,
    emptyLabel: String,
) {
    val colors = LocalSanvyaColors.current
    if (slices.isEmpty()) {
        Box(Modifier.fillMaxWidth().height(180.dp), contentAlignment = Alignment.Center) {
            Text(emptyLabel, fontSize = 13.sp, color = colors.text3)
        }
        return
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.fillMaxWidth().height(200.dp), contentAlignment = Alignment.Center) {
            SanvyaDonutChart(
                series = slices.map { SeriesPoint(it.label, it.valueMajor) },
                centerLabel = centerValue,
                centerSub = centerLabel,
                accent = colors.accent,
                colors = colors,
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            slices.forEachIndexed { i, s ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(
                        Modifier.size(9.dp).clip(RoundedCornerShape(50))
                            .background(resolveChartColor(null, i, colors.accent, colors)),
                    )
                    Text(
                        s.label,
                        fontSize = 12.sp,
                        color = colors.text,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    Text("${"%.0f".format(s.sharePct)}%", fontSize = 12.sp, color = colors.text2)
                    Spacer(Modifier.width(4.dp))
                    Text(s.amountFormatted, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = colors.text)
                }
            }
        }
    }
}

/** One signed bar: a gain (positive) or a loss (negative). */
data class SignedBar(val label: String, val valueMajor: Double, val amountFormatted: String, val positive: Boolean)

/**
 * Diverging horizontal bars around a centre line.
 *
 * Horizontal, where web is vertical, on purpose: group labels here are
 * exchange codes and scheme names, which do not fit under a vertical bar on a
 * phone without rotating them (web angles them -18 degrees, which needs the
 * width a desktop has). The information -- sign, magnitude, ranking -- is the
 * same, and this is the orientation `SanvyaBarsChart` already offers for the
 * same reason.
 */
@Composable
fun SignedBarsChart(bars: List<SignedBar>, emptyLabel: String) {
    val colors = LocalSanvyaColors.current
    if (bars.isEmpty()) {
        Box(Modifier.fillMaxWidth().height(120.dp), contentAlignment = Alignment.Center) {
            Text(emptyLabel, fontSize = 13.sp, color = colors.text3)
        }
        return
    }
    // One scale for both directions, so a small loss cannot render longer than
    // a large gain. `max(..., 1.0)` keeps an all-zero portfolio from dividing
    // by zero rather than special-casing it.
    val peak = max(bars.maxOf { abs(it.valueMajor) }, 1.0)
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        bars.forEach { b ->
            val fraction = (abs(b.valueMajor) / peak).toFloat().coerceIn(0f, 1f)
            val tint = if (b.positive) colors.positive else colors.negative
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(
                        b.label,
                        fontSize = 12.sp,
                        color = colors.text2,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    Text(b.amountFormatted, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = tint)
                }
                // Two half-width tracks meeting at the middle: the left half
                // fills leftwards for a loss, the right half rightwards for a
                // gain, so the zero line is a real, fixed position on screen
                // rather than wherever the data happens to put it.
                Row(modifier = Modifier.fillMaxWidth().height(10.dp)) {
                    Box(modifier = Modifier.weight(1f).fillMaxHeight(), contentAlignment = Alignment.CenterEnd) {
                        if (!b.positive) {
                            Box(
                                Modifier.fillMaxWidth(fraction).fillMaxHeight()
                                    .clip(RoundedCornerShape(topStart = 6.dp, bottomStart = 6.dp))
                                    .background(tint),
                            )
                        }
                    }
                    Box(Modifier.width(1.dp).fillMaxHeight().background(colors.borderStrong))
                    Box(modifier = Modifier.weight(1f).fillMaxHeight(), contentAlignment = Alignment.CenterStart) {
                        if (b.positive) {
                            Box(
                                Modifier.fillMaxWidth(fraction).fillMaxHeight()
                                    .clip(RoundedCornerShape(topEnd = 6.dp, bottomEnd = 6.dp))
                                    .background(tint),
                            )
                        }
                    }
                }
            }
        }
    }
}
