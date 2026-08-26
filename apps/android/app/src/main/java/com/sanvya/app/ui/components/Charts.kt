package com.sanvya.app.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sanvya.app.domain.insights.SeriesPoint
import com.sanvya.app.domain.insights.VisualSpec
import com.sanvya.app.theme.SanvyaColors
import com.sanvya.app.ui.CHART_COLORS

/**
 * The chart primitives — bars, area, donut, gauge, progress.
 *
 * All five lived `private` inside `InsightsScreen.kt`, which is why this audit
 * kept finding things blocked on them: the Recurring direction screen's
 * category donut has been recorded as absent since 2026-08-24 for exactly this
 * reason, and six of the dashboard's fourteen tiles need bars or an area.
 * Nothing was wrong with the charts. They were simply unreachable.
 *
 * They take `SeriesPoint` and `VisualSpec` from `:domain`, which both already
 * lived there, so moving the drawing here creates no new coupling — it only
 * removes the accident that the drawing lived inside one screen.
 *
 * Mirrors `apps/ios/App/Components/SanvyaCharts.swift`.
 */

@Composable
fun SanvyaVisualChart(visual: VisualSpec, accent: Color, colors: SanvyaColors) {
    when (visual) {
        is VisualSpec.Bars -> SanvyaBarsChart(visual.series, visual.horizontal, accent, colors)
        is VisualSpec.Area -> SanvyaAreaChart(visual.series, accent)
        is VisualSpec.Donut -> SanvyaDonutChart(visual.series, visual.centerLabel, visual.centerSub, accent, colors)
        is VisualSpec.Gauge -> SanvyaGaugeChart(visual.value, visual.max, visual.warnAt, visual.dangerAt, visual.centerLabel, accent, colors)
        is VisualSpec.Progress -> SanvyaProgressChart(visual.value, visual.target, visual.centerLabel, accent, colors)
    }
}

fun resolveChartColor(token: String?, index: Int, fallbackAccent: Color, colors: SanvyaColors): Color = when (token) {
    "positive" -> colors.positive
    "warning" -> colors.warning
    "negative" -> colors.negative
    "forest" -> colors.forest
    "accent" -> colors.accent
    "border" -> colors.border
    null -> INSIGHT_PALETTE_COMPOSE[index % INSIGHT_PALETTE_COMPOSE.size]
    else -> fallbackAccent
}

// Was eight hand-typed Color(0xFF…) literals, private to this file. It is
// web's INSIGHT_PALETTE, so it is generated into FormOptions now and parsed
// once in AccountColors.kt -- see CHART_COLORS' comment for why that mattered.
private val INSIGHT_PALETTE_COMPOSE = CHART_COLORS

@Composable
fun SanvyaBarsChart(series: List<SeriesPoint>, horizontal: Boolean, accent: Color, colors: SanvyaColors) {
    if (series.isEmpty()) return
    val maxVal = series.maxOf { it.value }.let { if (it <= 0) 1.0 else it }
    if (horizontal) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            series.forEachIndexed { i, s ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.weight(1f)) {
                    Text(s.label, fontSize = 11.sp, color = colors.text2, modifier = Modifier.width(76.dp))
                    Box(Modifier.weight(1f).fillMaxHeight(0.6f)) {
                        Box(
                            Modifier.fillMaxWidth(fraction = (s.value / maxVal).toFloat().coerceIn(0.02f, 1f)).fillMaxHeight()
                                .clip(RoundedCornerShape(topEnd = 8.dp, bottomEnd = 8.dp))
                                .background(resolveChartColor(s.color, i, accent, colors)),
                        )
                    }
                }
            }
        }
    } else {
        Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Bottom) {
            series.forEachIndexed { i, s ->
                Column(Modifier.weight(1f).fillMaxHeight(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Bottom) {
                    Text(if (s.value != 0.0) fmtCompact(s.value) else "", fontSize = 9.sp, color = colors.text2)
                    Box(
                        Modifier.fillMaxWidth(0.6f).fillMaxHeight(fraction = (s.value / maxVal).toFloat().coerceIn(0.02f, 1f))
                            .clip(RoundedCornerShape(topStart = 8.dp, topEnd = 8.dp))
                            .background(resolveChartColor(s.color, i, accent, colors)),
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(s.label, fontSize = 10.sp, color = colors.text2)
                }
            }
        }
    }
}

@Composable
fun SanvyaAreaChart(series: List<SeriesPoint>, accent: Color) {
    if (series.size < 2) return
    Canvas(Modifier.fillMaxSize().padding(vertical = 16.dp, horizontal = 8.dp)) {
        val maxV = series.maxOf { it.value }; val minV = min(0.0, series.minOf { it.value })
        val range = (maxV - minV).let { if (it <= 0.0) 1.0 else it }
        val stepX = size.width / (series.size - 1)
        fun yOf(v: Double) = size.height - ((v - minV) / range * size.height).toFloat()
        val path = Path()
        val fillPath = Path()
        series.forEachIndexed { i, s ->
            val x = i * stepX; val y = yOf(s.value)
            if (i == 0) { path.moveTo(x, y); fillPath.moveTo(x, size.height); fillPath.lineTo(x, y) } else { path.lineTo(x, y); fillPath.lineTo(x, y) }
        }
        fillPath.lineTo((series.size - 1) * stepX, size.height); fillPath.close()
        drawPath(fillPath, color = accent.copy(alpha = 0.18f))
        drawPath(path, color = accent, style = Stroke(width = 6f, cap = StrokeCap.Round))
    }
}

@Composable
fun SanvyaDonutChart(series: List<SeriesPoint>, centerLabel: String?, centerSub: String?, accent: Color, colors: SanvyaColors) {
    if (series.isEmpty()) return
    val total = series.sumOf { it.value }.let { if (it <= 0.0) 1.0 else it }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize(0.9f)) {
            val stroke = size.minDimension * 0.16f
            var startAngle = -90f
            series.forEachIndexed { i, s ->
                val sweep = (s.value / total * 360.0).toFloat()
                drawArc(
                    color = resolveChartColor(s.color, i, accent, colors), startAngle = startAngle, sweepAngle = sweep * 0.96f, useCenter = false,
                    topLeft = Offset(stroke / 2, stroke / 2), size = Size(size.width - stroke, size.height - stroke),
                    style = Stroke(width = stroke, cap = StrokeCap.Round),
                )
                startAngle += sweep
            }
        }
        if (centerLabel != null || centerSub != null) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                centerLabel?.let { Text(it, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.text) }
                centerSub?.let { Text(it, fontSize = 11.sp, color = colors.text2) }
            }
        }
    }
}

@Composable
fun SanvyaGaugeChart(value: Double, max: Double, warnAt: Double?, dangerAt: Double?, centerLabel: String?, accent: Color, colors: SanvyaColors) {
    val ratio = if (max > 0) (value / max).coerceIn(0.0, 1.0) else 0.0
    val color = when {
        value >= (dangerAt ?: max) -> colors.negative
        value >= (warnAt ?: max * 0.8) -> colors.warning
        else -> accent
    }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize(0.85f)) {
            val stroke = size.minDimension * 0.14f
            val sweepTotal = 240f; val start = 150f
            val r = androidx.compose.ui.geometry.Rect(Offset(stroke / 2, stroke / 2), Size(size.width - stroke, size.height - stroke))
            drawArc(colors.border, start, sweepTotal, false, r.topLeft, r.size, style = Stroke(width = stroke, cap = StrokeCap.Round))
            drawArc(color, start, sweepTotal * ratio.toFloat(), false, r.topLeft, r.size, style = Stroke(width = stroke, cap = StrokeCap.Round))
        }
        Text(centerLabel ?: "${(ratio * 100).toInt()}%", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = colors.text)
    }
}

@Composable
fun SanvyaProgressChart(value: Double, target: Double?, centerLabel: String?, accent: Color, colors: SanvyaColors) {
    val ratio = if (target != null && target > 0) (value / target).coerceIn(0.0, 1.0) else 0.5
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize(0.85f)) {
            val stroke = size.minDimension * 0.13f
            val r = androidx.compose.ui.geometry.Rect(Offset(stroke / 2, stroke / 2), Size(size.width - stroke, size.height - stroke))
            drawArc(colors.border, -90f, 360f, false, r.topLeft, r.size, style = Stroke(width = stroke, cap = StrokeCap.Round))
            drawArc(accent, -90f, 360f * ratio.toFloat(), false, r.topLeft, r.size, style = Stroke(width = stroke, cap = StrokeCap.Round))
        }
        Text(centerLabel ?: "${(ratio * 100).toInt()}%", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = colors.text)
    }
}

private fun fmtCompact(v: Double): String = if (v == 0.0) "" else if (v >= 1000) "${(v / 1000).let { if (it == it.toInt().toDouble()) it.toInt().toString() else "%.1f".format(it) }}k" else if (v == v.toLong().toDouble()) v.toLong().toString() else "%.0f".format(v)

