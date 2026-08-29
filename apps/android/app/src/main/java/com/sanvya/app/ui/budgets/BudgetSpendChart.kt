package com.sanvya.app.ui.budgets

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sanvya.app.domain.budget.SpendPoint
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.ui.dayMonthLabel
import com.sanvya.app.ui.formatMoney
import com.sanvya.app.ui.majorScale
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.sqrt

/** The plot area's height. Web's `ResponsiveContainer height={120}` less the
 *  row of date labels, which recharts draws inside its own 120. */
private val PlotHeight = 96.dp

/**
 * The cumulative spend-vs-limit curve on a budget card -- web's
 * `BudgetSpendChart` in apps/web/app/budgets/page.tsx (a recharts `AreaChart`
 * with a dashed `ReferenceLine` at the limit).
 *
 * NOT added to `ui/components/Charts.kt`. That file draws `VisualSpec`, the
 * insight/dashboard shape, which has no reference line and no date axis; a
 * budget-shaped variant there would either widen `VisualSpec` for one caller or
 * sit beside it as a second unrelated API. No charting dependency either way --
 * this is the same `Canvas` the rest of the chart layer uses, with its text
 * drawn as real `Text` composables around it, exactly as `SanvyaBarsChart`
 * already does rather than measuring glyphs inside the draw scope.
 *
 * Deliberate faithfulness to two of recharts' quirks:
 *
 * - **The Y domain is `[0, max(cum)]`,** recharts' default for an area whose
 *   values are all positive.
 * - **The limit line is DISCARDED when it falls outside that domain.** That is
 *   recharts' `ifOverflow="discard"` default for `ReferenceLine`, and it is why
 *   the dashed line only appears once spending is in the neighbourhood of the
 *   limit. Drawing it always would rescale the axis and squash every real
 *   budget's curve into the bottom few pixels.
 *
 * The one addition: a tap or drag picks a point and prints its running total.
 * That is the mobile equivalent of the `Tooltip` web gets from hover, and it
 * goes through `formatMoney`, so the reading is masked when hide-amounts is on
 * -- web's tooltip prints the raw number regardless, which is the leak class
 * PARITY_AUDIT trap 7 is about.
 */
@Composable
fun BudgetSpendChart(
    series: List<SpendPoint>,
    limitMinor: Long,
    currency: String,
    tint: Color,
) {
    // Web returns null below two points: one dot is not a trend, and the axis
    // has nothing to span.
    if (series.size < 2) return

    val colors = LocalSanvyaColors.current
    var selected by remember(series) { mutableStateOf<Int?>(null) }

    // `majorScale`, not `/ 100.0`: a JPY budget drawn against a hundredth of
    // its real limit would put every curve on the floor.
    val scale = majorScale(currency)
    val values = series.map { it.cumulativeMinor.toDouble() / scale }
    val limitMajor = limitMinor.toDouble() / scale
    val maxValue = values.maxOrNull() ?: 0.0
    // A budget with no spend at all still draws: a flat line on the floor is
    // the honest picture, where an auto-scaled empty domain would put a
    // meaningless line through the middle of the card.
    val top = if (maxValue > 0.0) maxValue else 1.0
    val limitVisible = limitMinor > 0L && limitMajor <= top

    val chartLabel = S.Budgets.spendChartAria(sRes())
    val limitLabel = S.Budgets.spendChartLimit(sRes(), formatMoney(limitMinor, currency))
    val dayLabels = series.map { dayMonthLabel(it.dayIso) }

    Column(Modifier.fillMaxWidth().semantics { contentDescription = chartLabel }) {
        Box(Modifier.fillMaxWidth().height(PlotHeight)) {
            Canvas(
                Modifier
                    .fillMaxSize()
                    .pointerInput(series) {
                        // Two detectors in one node: `detectTapGestures` never
                        // sees a drag and `detectHorizontalDragGestures` never
                        // sees a tap, and running them as siblings in one
                        // `coroutineScope` is the documented way to have both.
                        // Two separate `pointerInput` modifiers would race for
                        // the same down event.
                        coroutineScope {
                            launch {
                                detectTapGestures { offset ->
                                    selected = nearestIndex(offset.x, size.width.toFloat(), series.size)
                                }
                            }
                            launch {
                                detectHorizontalDragGestures(
                                    onDragStart = { offset ->
                                        selected = nearestIndex(offset.x, size.width.toFloat(), series.size)
                                    },
                                    onHorizontalDrag = { change, _ ->
                                        selected = nearestIndex(change.position.x, size.width.toFloat(), series.size)
                                    },
                                )
                            }
                        }
                    },
            ) {
                val stepX = size.width / (series.size - 1)
                val ys = FloatArray(series.size) { i ->
                    (size.height - (values[i] / top * size.height)).toFloat()
                }
                val line = monotonePath(series.size, { i -> i * stepX }, { i -> ys[i] })
                val fill = Path().apply {
                    addPath(line)
                    lineTo((series.size - 1) * stepX, size.height)
                    lineTo(0f, size.height)
                    close()
                }
                drawPath(
                    fill,
                    // Web's gradient stops exactly: 0.35 at the curve, 0.02 at
                    // the baseline.
                    brush = Brush.verticalGradient(
                        colors = listOf(tint.copy(alpha = 0.35f), tint.copy(alpha = 0.02f)),
                        startY = 0f,
                        endY = size.height,
                    ),
                )
                drawPath(line, color = tint, style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round))

                // recharts discards a reference line outside the domain; so
                // does this. See the doc comment.
                if (limitVisible) {
                    val y = (size.height - (limitMajor / top * size.height)).toFloat()
                    drawLine(
                        color = colors.text2.copy(alpha = 0.7f),
                        start = Offset(0f, y),
                        end = Offset(size.width, y),
                        strokeWidth = 1.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 4.dp.toPx())),
                    )
                }

                val index = selected
                if (index != null) {
                    val x = index * stepX
                    drawLine(
                        color = colors.border,
                        start = Offset(x, 0f),
                        end = Offset(x, size.height),
                        strokeWidth = 1.dp.toPx(),
                    )
                    drawCircle(color = tint, radius = 3.dp.toPx(), center = Offset(x, ys[index]))
                }
            }

            if (limitVisible) {
                Text(
                    limitLabel,
                    fontSize = 10.sp,
                    color = colors.text2,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        // The label sits just above its own line. Clamped to
                        // zero so a limit already reached does not push it off
                        // the top of the card.
                        .offset(y = labelOffset(limitMajor, top)),
                )
            }

            selected?.let { index ->
                // Pinned top-start rather than following the touch: a floating
                // label near the right edge of a phone-width card clips, and
                // web's tooltip has a cursor to anchor to that a finger does
                // not.
                Text(
                    "${dayLabels[index]} · ${formatMoney(series[index].cumulativeMinor, currency)}",
                    fontSize = 11.sp,
                    color = colors.text,
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .clip(RoundedCornerShape(6.dp))
                        .background(colors.surface2)
                        .padding(horizontal = 6.dp, vertical = 2.dp),
                )
            }
        }

        // Web's `interval="preserveStartEnd"` with `minTickGap={24}`: the ends
        // always, and the middle one only when there is room for it. Three
        // labels is what recharts settles on at a phone-width card, and a Row
        // cannot overlap them the way absolute tick positions can.
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(dayLabels.first(), fontSize = 10.sp, color = colors.text2)
            if (dayLabels.size >= 5) {
                Text(dayLabels[dayLabels.size / 2], fontSize = 10.sp, color = colors.text2)
            }
            Text(dayLabels.last(), fontSize = 10.sp, color = colors.text2)
        }
    }
}

/** Where the limit label sits, measured down from the top of the plot. */
private fun labelOffset(limitMajor: Double, top: Double): Dp {
    val fraction = (1.0 - limitMajor / top).coerceIn(0.0, 1.0)
    return (PlotHeight * fraction.toFloat() - 13.dp).coerceAtLeast(0.dp)
}

/** The point nearest a touch, so a tap between two days picks the closer one. */
private fun nearestIndex(x: Float, width: Float, count: Int): Int {
    if (count <= 1 || width <= 0f) return 0
    val step = width / (count - 1)
    val lower = (x / step).toInt().coerceIn(0, count - 1)
    // `toInt()` truncates, so check the next point too rather than always
    // snapping backwards.
    val upper = (lower + 1).coerceAtMost(count - 1)
    return if (abs(x - upper * step) < abs(x - lower * step)) upper else lower
}

/**
 * A smooth path through the points -- recharts' `type="monotone"`.
 *
 * Fritsch-Carlson monotone cubic interpolation: control points are damped so a
 * segment can never overshoot its endpoints. That matters here more than it
 * looks. The series is a CUMULATIVE total and so is non-decreasing, and a plain
 * Catmull-Rom spline dips below a flat stretch -- drawing a day on which the
 * user appears to have un-spent money.
 */
private fun monotonePath(count: Int, xOf: (Int) -> Float, yOf: (Int) -> Float): Path {
    val path = Path()
    if (count == 0) return path
    path.moveTo(xOf(0), yOf(0))
    if (count == 1) return path

    // Secant slopes between consecutive points.
    val slopes = FloatArray(count - 1) { i ->
        val dx = xOf(i + 1) - xOf(i)
        if (dx == 0f) 0f else (yOf(i + 1) - yOf(i)) / dx
    }
    // Tangents: the average of the neighbouring secants, flattened wherever the
    // curve changes direction.
    val tangents = FloatArray(count)
    tangents[0] = slopes[0]
    tangents[count - 1] = slopes[count - 2]
    for (i in 1 until count - 1) {
        tangents[i] = if (slopes[i - 1] * slopes[i] <= 0f) 0f else (slopes[i - 1] + slopes[i]) / 2f
    }
    // Fritsch-Carlson damping: keep each tangent inside three times its secant.
    for (i in 0 until count - 1) {
        if (slopes[i] == 0f) {
            tangents[i] = 0f
            tangents[i + 1] = 0f
        } else {
            val a = tangents[i] / slopes[i]
            val b = tangents[i + 1] / slopes[i]
            val h = a * a + b * b
            if (h > 9f) {
                val t = 3f / sqrt(h)
                tangents[i] = t * a * slopes[i]
                tangents[i + 1] = t * b * slopes[i]
            }
        }
    }
    for (i in 0 until count - 1) {
        val x0 = xOf(i)
        val x1 = xOf(i + 1)
        val dx = (x1 - x0) / 3f
        path.cubicTo(
            x0 + dx, yOf(i) + tangents[i] * dx,
            x1 - dx, yOf(i + 1) - tangents[i + 1] * dx,
            x1, yOf(i + 1),
        )
    }
    return path
}
