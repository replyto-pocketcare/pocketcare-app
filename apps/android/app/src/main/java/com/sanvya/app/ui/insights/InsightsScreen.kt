package com.sanvya.app.ui.insights

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Insights
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.*
import androidx.compose.runtime.*
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.domain.insights.InsightCard
import com.sanvya.app.domain.insights.InsightTheme
import com.sanvya.app.domain.insights.SeriesPoint
import com.sanvya.app.domain.insights.VisualSpec
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaColors
import com.sanvya.app.theme.SanvyaRadius
import kotlinx.coroutines.launch
import kotlin.math.min

/**
 * Real port of apps/web/src/ui/feed/{InsightFeed,InsightCard,Charts2D,
 * ProgressRail}.tsx (task #28), replacing an entirely fake predecessor.
 * Mobile always renders the "mobile" layout (full-viewport card, one per
 * screen) -- web's desktop coverflow has no phone equivalent. Charts are
 * hand-drawn on Canvas (no charting library exists on mobile yet); see
 * docs/mobile/screen-specs/insights.md's "Chart rendering" section for the
 * geometry each visual kind must match.
 */
private val ROUTABLE_CTAS = setOf("/budgets", "/goals", "/transactions", "/investments")

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
@Composable
fun InsightsScreen(
    onNavigate: (String) -> Unit = {},
    onUpgrade: () -> Unit = {},
    viewModel: InsightsViewModel = viewModel(),
) {
    val colors = LocalSanvyaColors.current
    val cards by viewModel.cards.collectAsState()
    val isPaid by viewModel.isPaid.collectAsState()
    val loaded by viewModel.entitlementLoaded.collectAsState()
    val activeIndex by viewModel.activeIndex.collectAsState()

    Scaffold(containerColor = colors.bg) { padding ->
        Box(modifier = Modifier.padding(padding).fillMaxSize()) {
            when {
                !loaded -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                !isPaid -> LockedInsightsState(colors, onUpgrade)
                cards.isEmpty() -> EmptyInsightsState(colors)
                else -> InsightPagerFeed(cards, activeIndex, viewModel::setActiveIndex, colors, onNavigate)
            }
        }
    }
}

@Composable
private fun LockedInsightsState(colors: SanvyaColors, onUpgrade: () -> Unit) {
    Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
        Card(colors = CardDefaults.cardColors(containerColor = colors.surface), shape = RoundedCornerShape(SanvyaRadius.radiusLg)) {
            Column(Modifier.padding(28.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Default.Lock, contentDescription = null, tint = colors.text2, modifier = Modifier.size(30.dp))
                Text("Unlock insights", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.text)
                Text(
                    "See weekly recaps, budget alerts, spending patterns and more -- generated automatically from your own data.",
                    fontSize = 14.sp, color = colors.text2, textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                )
                Button(onClick = onUpgrade) { Text("Go premium") }
            }
        }
    }
}

@Composable
private fun EmptyInsightsState(colors: SanvyaColors) {
    Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
        Card(colors = CardDefaults.cardColors(containerColor = colors.surface), shape = RoundedCornerShape(SanvyaRadius.radiusLg)) {
            Column(Modifier.padding(28.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Default.Insights, contentDescription = null, tint = colors.text2, modifier = Modifier.size(30.dp))
                Text("Your stack is empty for now", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = colors.text)
                Text(
                    "Add a few transactions and Sanvya will start surfacing weekly recaps, budget alerts and savings wins here.",
                    fontSize = 13.sp, color = colors.text2, textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                )
            }
        }
    }
}

@Composable
private fun InsightPagerFeed(cards: List<InsightCard>, activeIndex: Int, onIndexChange: (Int) -> Unit, colors: SanvyaColors, onNavigate: (String) -> Unit) {
    val pagerState = rememberPagerState(initialPage = activeIndex.coerceIn(0, cards.size - 1)) { cards.size }
    val scope = rememberCoroutineScope()

    LaunchedEffect(pagerState.currentPage) { onIndexChange(pagerState.currentPage) }

    Box(Modifier.fillMaxSize()) {
        VerticalPager(state = pagerState, modifier = Modifier.fillMaxSize()) { page ->
            InsightCardView(cards[page], colors) { target ->
                if (target in ROUTABLE_CTAS) onNavigate(target.removePrefix("/"))
            }
        }

        // Progress rail: vertical pill stack, right edge, centered.
        Column(
            modifier = Modifier.align(Alignment.CenterEnd).padding(end = 10.dp).height((min(320, cards.size * 26)).dp),
            verticalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            cards.indices.forEach { i ->
                Box(
                    modifier = Modifier.weight(1f).width(4.dp)
                        .clip(RoundedCornerShape(50))
                        .background(if (i <= pagerState.currentPage) colors.accent else colors.border)
                        .clickable { scope.launch { pagerState.animateScrollToPage(i) } },
                )
            }
        }

        val remaining = maxOf(0, cards.size - (pagerState.currentPage + 1))
        Box(
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 14.dp)
                .clip(RoundedCornerShape(50)).background(colors.surface)
                .padding(horizontal = 12.dp, vertical = 5.dp),
        ) {
            Text(
                "${pagerState.currentPage + 1} of ${cards.size}" + (if (remaining > 0) " · $remaining left" else " · all caught up"),
                fontSize = 12.sp, color = colors.text2,
            )
        }
    }
}

private fun themeAccent(theme: InsightTheme, colors: SanvyaColors): Color = when (theme) {
    InsightTheme.POSITIVE -> colors.positive
    InsightTheme.WARNING -> colors.warning
    InsightTheme.CELEBRATORY -> colors.accent
    InsightTheme.NEUTRAL -> colors.forest
}

private val TYPE_LABEL = mapOf(
    "weekly_summary" to "Weekly recap", "budget_warning" to "Budget alert", "savings_achievement" to "Achievement",
    "spending_trend" to "Spending trend", "category_breakdown" to "Breakdown", "streak" to "Streak",
    "biggest_expense" to "Biggest expense", "weekday_pattern" to "Spending pattern", "label_breakdown" to "By label",
    "subscriptions_load" to "Subscriptions", "month_pace" to "Month pace", "no_spend_days" to "No-spend days",
    "goal_progress" to "Goal progress", "category_spike" to "Category spike", "avg_daily_spend" to "Daily average",
    "dividend_income" to "Dividend income", "portfolio_projection" to "Projected wealth", "mindfulness" to "Mindful spending",
)

@Composable
private fun InsightCardView(card: InsightCard, colors: SanvyaColors, onCta: (String) -> Unit) {
    val accent = themeAccent(card.theme, colors)
    Column(Modifier.fillMaxSize().padding(start = 20.dp, end = 20.dp, top = 16.dp, bottom = 40.dp)) {
        // chart area
        Box(
            modifier = Modifier.weight(1f).fillMaxWidth()
                .clip(RoundedCornerShape(SanvyaRadius.radiusLg))
                .background(colors.surface2)
                .padding(10.dp),
            contentAlignment = Alignment.Center,
        ) {
            val visual = card.visual
            if (visual != null) VisualChart(visual, accent, colors) else {
                Text(card.headline, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = colors.text, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            }
        }
        Spacer(Modifier.height(14.dp))
        // content card
        Card(colors = CardDefaults.cardColors(containerColor = colors.surface), shape = RoundedCornerShape(SanvyaRadius.radiusLg)) {
            Column(Modifier.padding(20.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(
                    modifier = Modifier.clip(RoundedCornerShape(50)).background(colors.surface2)
                        .padding(horizontal = 10.dp, vertical = 4.dp),
                ) {
                    Text(TYPE_LABEL[card.type] ?: card.type, fontSize = 10.sp, fontWeight = FontWeight.Bold, color = accent)
                }
                Text(card.headline, fontSize = 24.sp, fontWeight = FontWeight.Bold, color = colors.text, lineHeight = 28.sp)
                card.subhead?.let { Text(it, fontSize = 13.sp, color = colors.text2) }
                card.metric?.let { m ->
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(m.display, fontSize = 28.sp, fontWeight = FontWeight.Bold, color = accent)
                        val deltaPct = m.deltaPct
                        if (deltaPct != null) {
                            val up = m.direction == "up"
                            Text(
                                "${if (up) "▲" else "▼"} ${kotlin.math.abs(deltaPct)}%",
                                fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                                color = if (up) colors.positive else colors.negative,
                            )
                        }
                    }
                }
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    card.bullets.forEach { b ->
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("•", color = accent, fontWeight = FontWeight.Bold)
                            Text(b, fontSize = 13.5.sp, color = colors.text)
                        }
                    }
                }
                card.cta?.let { cta ->
                    if (cta.target in ROUTABLE_CTAS) {
                        TextButton(onClick = { onCta(cta.target) }, modifier = Modifier.padding(top = 2.dp)) { Text(cta.label) }
                    }
                }
            }
        }
    }
}

// ---- charts ----

@Composable
private fun VisualChart(visual: VisualSpec, accent: Color, colors: SanvyaColors) {
    when (visual) {
        is VisualSpec.Bars -> BarsChart(visual.series, visual.horizontal, accent, colors)
        is VisualSpec.Area -> AreaChart(visual.series, accent)
        is VisualSpec.Donut -> DonutChart(visual.series, visual.centerLabel, visual.centerSub, accent, colors)
        is VisualSpec.Gauge -> GaugeChart(visual.value, visual.max, visual.warnAt, visual.dangerAt, visual.centerLabel, accent, colors)
        is VisualSpec.Progress -> ProgressChart(visual.value, visual.target, visual.centerLabel, accent, colors)
    }
}

private fun resolveColor(token: String?, index: Int, fallbackAccent: Color, colors: SanvyaColors): Color = when (token) {
    "positive" -> colors.positive
    "warning" -> colors.warning
    "negative" -> colors.negative
    "forest" -> colors.forest
    "accent" -> colors.accent
    "border" -> colors.border
    null -> INSIGHT_PALETTE_COMPOSE[index % INSIGHT_PALETTE_COMPOSE.size]
    else -> fallbackAccent
}

private val INSIGHT_PALETTE_COMPOSE = listOf(
    Color(0xFFB06A4F), Color(0xFF5F7A52), Color(0xFFC08A3E), Color(0xFF9CAE8E),
    Color(0xFF3E4A38), Color(0xFFC98A72), Color(0xFF7C7264), Color(0xFF5F6647),
)

@Composable
private fun BarsChart(series: List<SeriesPoint>, horizontal: Boolean, accent: Color, colors: SanvyaColors) {
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
                                .background(resolveColor(s.color, i, accent, colors)),
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
                            .background(resolveColor(s.color, i, accent, colors)),
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(s.label, fontSize = 10.sp, color = colors.text2)
                }
            }
        }
    }
}

@Composable
private fun AreaChart(series: List<SeriesPoint>, accent: Color) {
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
private fun DonutChart(series: List<SeriesPoint>, centerLabel: String?, centerSub: String?, accent: Color, colors: SanvyaColors) {
    if (series.isEmpty()) return
    val total = series.sumOf { it.value }.let { if (it <= 0.0) 1.0 else it }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize(0.9f)) {
            val stroke = size.minDimension * 0.16f
            var startAngle = -90f
            series.forEachIndexed { i, s ->
                val sweep = (s.value / total * 360.0).toFloat()
                drawArc(
                    color = resolveColor(s.color, i, accent, colors), startAngle = startAngle, sweepAngle = sweep * 0.96f, useCenter = false,
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
private fun GaugeChart(value: Double, max: Double, warnAt: Double?, dangerAt: Double?, centerLabel: String?, accent: Color, colors: SanvyaColors) {
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
private fun ProgressChart(value: Double, target: Double?, centerLabel: String?, accent: Color, colors: SanvyaColors) {
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
