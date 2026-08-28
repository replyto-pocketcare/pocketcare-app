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
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.domain.insights.InsightCard
import com.sanvya.app.domain.insights.InsightTheme
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaColors
import com.sanvya.app.ui.components.SanvyaVisualChart
import com.sanvya.app.theme.SanvyaRadius
import kotlinx.coroutines.launch
import kotlin.math.min
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes

/**
 * Real port of apps/web/src/ui/feed/{InsightFeed,InsightCard,Charts2D,
 * ProgressRail}.tsx (task #28), replacing an entirely fake predecessor.
 * Mobile always renders the "mobile" layout (full-viewport card, one per
 * screen) -- web's desktop coverflow has no phone equivalent. Charts are
 * hand-drawn on Canvas (no charting library exists on mobile yet); see
 * docs/mobile/screen-specs/insights.md's "Chart rendering" section for the
 * geometry each visual kind must match.
 */
/**
 * The CTA targets this screen can follow, and the route each one means.
 *
 * `/subscriptions` is a MAPPING, not a rename. Web's `/subscriptions` page is a
 * redirect to `/recurring` -- its own comment says it is "kept so old links --
 * dashboard tiles, insights CTAs, bookmarks -- still land" -- and the
 * subscriptions-load insight (`Insights.kt`, cadenceKey `subscriptions_load`)
 * is one of those links. It was absent from this list, so that card drew a
 * "Manage subscriptions" button that did nothing at all; adding the raw path
 * without the mapping would have been worse, because `subscriptions` is not a
 * destination in the nav graph and navigating to it throws.
 */
private val ROUTABLE_CTAS = mapOf(
    "/budgets" to "budgets",
    "/goals" to "goals",
    "/transactions" to "transactions",
    "/investments" to "investments",
    "/subscriptions" to "recurring",
)

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
                Button(onClick = onUpgrade) { Text(S.Insights.goPremium(sRes())) }
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
                ROUTABLE_CTAS[target]?.let(onNavigate)
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
            if (visual != null) SanvyaVisualChart(visual, accent, colors) else {
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
