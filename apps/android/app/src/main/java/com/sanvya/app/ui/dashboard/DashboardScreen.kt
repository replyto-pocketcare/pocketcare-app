package com.sanvya.app.ui.dashboard

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.data.repository.AccountWithBalance
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaRadius
import java.text.NumberFormat
import java.util.Locale
import kotlin.math.abs

/**
 * Dashboard — ported from apps/web/app/page.tsx per
 * docs/mobile/screen-specs/dashboard.md. Covers the hero + accounts strip +
 * empty/populated states (that spec's documented scope for this pass); the
 * 12-tile customizable grid (apps/web/src/dashboard/tiles.tsx) is explicitly
 * deferred, tracked separately in docs/mobile/TODO.md — NOT silently dropped,
 * NOT faked with a placeholder grid.
 */
@Composable
fun DashboardScreen(
    onOpenSettings: () -> Unit = {},
    viewModel: DashboardViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val amountsHidden by Prefs.amountsHidden.collectAsState()
    val colors = LocalSanvyaColors.current

    Scaffold(
        containerColor = colors.bg,
        topBar = {
            TopAppBar(
                title = { Text("Dashboard", fontWeight = FontWeight.Bold, color = colors.text) },
                actions = {
                    IconButton(onClick = { Prefs.setAmountsHidden(!amountsHidden) }) {
                        Icon(
                            imageVector = if (amountsHidden) Icons.Default.Visibility else Icons.Default.VisibilityOff,
                            contentDescription = if (amountsHidden) "Show amounts" else "Hide amounts",
                            tint = colors.text2,
                        )
                    }
                    IconButton(onClick = onOpenSettings) {
                        Icon(Icons.Default.Settings, contentDescription = "Settings", tint = colors.text2)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.bg),
            )
        },
    ) { padding ->
        if (uiState.accounts.isEmpty()) {
            EmptyDashboard(modifier = Modifier.padding(padding))
        } else {
            Column(
                modifier = Modifier
                    .padding(padding)
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(top = 4.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                NetWorthHero(
                    state = uiState.hero,
                    hidden = amountsHidden,
                    onToggle = { viewModel.toggleShowAvailable() },
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
                AccountsCard(
                    accounts = uiState.accounts,
                    hidden = amountsHidden,
                    colors = colors,
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
                // Tile catalog (recent/spending/trends/budgets/goals/etc.) is
                // explicitly deferred -- see docs/mobile/screen-specs/dashboard.md
                // "Explicitly deferred". This card says so instead of silently
                // omitting the section or faking a grid.
                Card(
                    modifier = Modifier.padding(horizontal = 16.dp).fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = colors.surface),
                    shape = RoundedCornerShape(SanvyaRadius.radiusLg),
                ) {
                    Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("More widgets coming soon", fontWeight = FontWeight.SemiBold, color = colors.text)
                        Text(
                            "Spending, budgets, goals, and trend tiles are on the way.",
                            fontSize = 13.sp,
                            color = colors.text2,
                        )
                    }
                }
                Spacer(Modifier.height(8.dp))
            }
        }
    }
}

@Composable
private fun EmptyDashboard(modifier: Modifier = Modifier) {
    val colors = LocalSanvyaColors.current
    Box(modifier = modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
        Card(
            colors = CardDefaults.cardColors(containerColor = colors.surface),
            shape = RoundedCornerShape(SanvyaRadius.radiusLg),
        ) {
            Column(
                modifier = Modifier.padding(36.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Text("Welcome to Sanvya", fontSize = 26.sp, fontWeight = FontWeight.Bold, color = colors.text)
                Text(
                    "Start by adding your first account — just your own note of somewhere your money sits. " +
                        "Nothing here connects to your bank; you type the amounts in yourself.",
                    fontSize = 14.sp,
                    color = colors.text2,
                )
                // Disabled, not wired to a fake destination: /accounts/new's
                // equivalent screen isn't built yet (tracked separately) --
                // showing an enabled button that does nothing on tap would be
                // the same false-affordance problem this whole audit exists
                // to fix, just at the button level instead of the file level.
                Button(onClick = {}, enabled = false) {
                    Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Add your first account (screen ships next)")
                }
            }
        }
    }
}

@Composable
private fun NetWorthHero(
    state: NetWorthHeroState,
    hidden: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val numberFormat = remember {
        NumberFormat.getCurrencyInstance(Locale("en", "IN")).apply {
            currency = java.util.Currency.getInstance("INR")
            maximumFractionDigits = 2
        }
    }
    val netFormatted = if (hidden) "••••••" else numberFormat.format(state.net.amount / 100.0)
    val deltaFormatted = if (hidden) "••••" else numberFormat.format(abs(state.deltaMinor) / 100.0)
    val up = state.deltaMinor >= 0

    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(SanvyaRadius.radiusLg))
            .background(
                Brush.linearGradient(
                    colors = listOf(Color(0xFF5F6647), Color(0xFF3E4A38)),
                )
            )
            .padding(26.dp, 26.dp, 26.dp, 22.dp)
    ) {
        Column {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(
                    text = if (state.showAvailable) "AVAILABLE NET WORTH" else "NET WORTH",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    letterSpacing = 1.sp,
                    color = Color(0xFFC6CDB3),
                )
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .background(Color.White.copy(alpha = 0.14f))
                        .clickable(onClick = onToggle)
                        .padding(horizontal = 12.dp, vertical = 5.dp)
                ) {
                    Text(
                        text = if (state.showAvailable) "Excluding blocked" else "Including blocked",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color(0xFFEAF0DA),
                    )
                }
            }
            Text(
                text = netFormatted,
                fontSize = 38.sp,
                fontWeight = FontWeight.Black,
                color = Color(0xFFF1EDE3),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(top = 6.dp),
            )
            if (state.hasTrend) {
                Box(
                    modifier = Modifier
                        .padding(top = 10.dp)
                        .clip(RoundedCornerShape(50))
                        .background(Color.White.copy(alpha = 0.14f))
                        .padding(horizontal = 11.dp, vertical = 4.dp)
                ) {
                    Text(
                        text = "${if (up) "+" else "−"}$deltaFormatted this month",
                        fontSize = 12.5.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = if (up) Color(0xFFDDE7C9) else Color(0xFFF0D8C9),
                    )
                }
            }
            if (state.sparkline.size >= 2) {
                Sparkline(
                    values = state.sparkline,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(56.dp)
                        .padding(top = 14.dp),
                )
            }
            Text(
                text = "Base currency ${state.base}",
                fontSize = 12.5.sp,
                color = Color(0xFFC6CDB3),
                modifier = Modifier.padding(top = 8.dp),
            )
        }
    }
}

@Composable
private fun Sparkline(values: List<Float>, modifier: Modifier = Modifier) {
    val min = values.min()
    val max = values.max()
    val range = (max - min).let { if (it == 0f) 1f else it }
    Canvas(modifier = modifier) {
        val w = size.width
        val h = size.height
        val pad = 3f
        val points = values.mapIndexed { i, v ->
            val x = if (values.size == 1) 0f else (i / (values.size - 1).toFloat()) * w
            val y = h - pad - ((v - min) / range) * (h - pad * 2)
            Offset(x, y)
        }
        val linePath = Path().apply {
            points.forEachIndexed { i, p -> if (i == 0) moveTo(p.x, p.y) else lineTo(p.x, p.y) }
        }
        val areaPath = Path().apply {
            addPath(linePath)
            lineTo(w, h)
            lineTo(0f, h)
            close()
        }
        drawPath(
            path = areaPath,
            brush = Brush.verticalGradient(
                colors = listOf(Color(0xFFC6CDB3).copy(alpha = 0.5f), Color(0xFFC6CDB3).copy(alpha = 0f)),
            ),
        )
        drawPath(
            path = linePath,
            color = Color(0xFFEAF0DA),
            style = Stroke(width = 2.2f),
        )
    }
}

@Composable
private fun AccountsCard(
    accounts: List<AccountWithBalance>,
    hidden: Boolean,
    colors: com.sanvya.app.theme.SanvyaColors,
    modifier: Modifier = Modifier,
) {
    val numberFormat = remember {
        NumberFormat.getCurrencyInstance(Locale("en", "IN")).apply {
            currency = java.util.Currency.getInstance("INR")
            maximumFractionDigits = 2
        }
    }
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = colors.surface),
        shape = RoundedCornerShape(SanvyaRadius.radiusLg),
    ) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Accounts", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = colors.text)
                val suffix = if (accounts.size > 8) " (${accounts.size})" else ""
                Text("View all$suffix", fontSize = 13.sp, color = colors.accent)
            }
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(accounts.take(8)) { item ->
                    val color = accountColor(item.account.color, item.account.id)
                    Column(
                        modifier = Modifier
                            .width(112.dp)
                            .clip(RoundedCornerShape(SanvyaRadius.radiusSm))
                            .background(color)
                            .padding(horizontal = 11.dp, vertical = 9.dp),
                    ) {
                        Text(
                            item.account.type.replace("_", " "),
                            fontSize = 10.sp,
                            color = Color.White.copy(alpha = 0.85f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            item.account.name,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = Color.White,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            text = if (hidden) "••••••" else numberFormat.format(item.balance.amount / 100.0),
                            fontSize = 14.5.sp,
                            fontWeight = FontWeight.Black,
                            color = Color.White,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }
        }
    }
}

/** ACCOUNT_COLORS + colorForId, ported byte-for-byte from apps/web/src/colors.ts
 * per docs/mobile/screen-specs/dashboard.md -- do not substitute the earthy
 * SanvyaColors palette here, this is a deliberately distinct 18-color set
 * (includes jewel tones) used only for per-account chip coloring. */
private val ACCOUNT_COLORS = listOf(
    0xFF3E4A38, 0xFF5F6647, 0xFF6B7A4F, 0xFF9CAE8E, 0xFFB06A4F, 0xFFC98A72,
    0xFFA8503A, 0xFF7C4A3A, 0xFF5F4636, 0xFFC9B79C, 0xFFC08A3E, 0xFF4F46E5,
    0xFF6D5ACF, 0xFF3F5A8A, 0xFF2F6F6A, 0xFF7A4A6B, 0xFF4B5563, 0xFF2B2723,
).map { Color(it or 0xFF000000) }

private fun accountColor(explicit: String?, id: String): Color {
    if (!explicit.isNullOrBlank()) {
        return try {
            Color(android.graphics.Color.parseColor(explicit))
        } catch (e: IllegalArgumentException) {
            colorForId(id)
        }
    }
    return colorForId(id)
}

private fun colorForId(id: String?): Color {
    if (id.isNullOrEmpty()) return Color(0xFF7C7264)
    var h = 0L
    for (c in id) {
        h = (h * 31 + c.code) and 0xFFFFFFFFL
    }
    return ACCOUNT_COLORS[(h % ACCOUNT_COLORS.size).toInt()]
}
