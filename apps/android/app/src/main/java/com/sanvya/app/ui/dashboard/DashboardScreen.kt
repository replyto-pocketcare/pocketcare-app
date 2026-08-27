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
import androidx.compose.material.icons.filled.Receipt
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
import androidx.compose.runtime.saveable.rememberSaveable
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.SanvyaButton
import com.sanvya.app.ui.components.SanvyaText
import com.sanvya.app.ui.onboarding.WalkthroughHost
import com.sanvya.app.data.repository.AccountWithBalance
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaRadius
import com.sanvya.app.ui.Prefs
import com.sanvya.app.ui.accountColor
import kotlin.math.abs
import com.sanvya.app.ui.formatMoney
import com.sanvya.app.ui.formatMoneyUnmasked
import com.sanvya.app.ui.colorForId
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes

/**
 * Dashboard — ported from apps/web/app/page.tsx per
 * docs/mobile/screen-specs/dashboard.md. Covers the hero + accounts strip +
 * empty/populated states (that spec's documented scope for this pass); the
 * 12-tile customizable grid (apps/web/src/dashboard/tiles.tsx) is explicitly
 * deferred, tracked separately in docs/mobile/TODO.md — NOT silently dropped,
 * NOT faked with a placeholder grid.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen(
    onOpenSettings: () -> Unit = {},
    /**
     * A guest choosing "Create a free account" from the walkthrough's last step.
     * The shell owns the same destination for its guest chips; the dashboard
     * only needs to be able to ask for it.
     */
    onSignIn: () -> Unit = {},
    onAddAccount: () -> Unit = {},
    onViewAccounts: () -> Unit = {},
    onViewTransactions: () -> Unit = {},
    onAddTransaction: () -> Unit = {},
    onScanReceipt: () -> Unit = {},
    onOpenTile: (String) -> Unit = {},
    viewModel: DashboardViewModel = viewModel(),
    shellViewModel: com.sanvya.app.ui.shell.ShellViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val amountsHidden by Prefs.amountsHidden.collectAsState()
    val colors = LocalSanvyaColors.current
    // Entitlement gates the five premium tiles. The shell already computes it
    // for the receipt-scan lock; asking it again here rather than re-deriving
    // isPaid() is the same reason the palettes moved into FormOptions.
    val isPaid by shellViewModel.canScan.collectAsState()
    var editing by rememberSaveable { mutableStateOf(false) }
    var addOpen by rememberSaveable { mutableStateOf(false) }

    Scaffold(
        containerColor = colors.bg,
        topBar = {
            TopAppBar(
                title = { Text(S.Translation.navHome(sRes()), fontWeight = FontWeight.Bold, color = colors.text) },
                actions = {
                    IconButton(onClick = { Prefs.setAmountsHidden(!amountsHidden) }) {
                        Icon(
                            imageVector = if (amountsHidden) Icons.Default.Visibility else Icons.Default.VisibilityOff,
                            contentDescription = if (amountsHidden) "Show amounts" else "Hide amounts",
                            tint = colors.text2,
                        )
                    }
                    // "Customize" — web's header chip. It had nothing to open
                    // until the tile grid existed; it does now.
                    TextButton(onClick = { editing = !editing }) {
                        Text(
                            if (editing) S.Translation.commonDone(sRes()) else S.Dashboard.customize(sRes()),
                            color = colors.accent,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                    IconButton(onClick = onViewTransactions) {
                        Icon(Icons.Default.Receipt, contentDescription = S.Translation.navTransactions(sRes()), tint = colors.text2)
                    }
                    IconButton(onClick = onOpenSettings) {
                        Icon(Icons.Default.Settings, contentDescription = S.Translation.commonSettings(sRes()), tint = colors.text2)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.bg),
            )
        },
        // No floatingActionButton: the shell's centre "+" is the app's one add
        // affordance, on every screen, exactly as on web. The speed dial that
        // used to live here was this app's only quick-add control before the
        // shell existed; keeping it would put two "+" buttons on the dashboard.
    ) { padding ->
        if (uiState.accounts.isEmpty()) {
            EmptyDashboard(onAddAccount = onAddAccount, modifier = Modifier.padding(padding))
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
                    onViewAll = onViewAccounts,
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
                DashboardTileGrid(
                    editing = editing,
                    isPaid = isPaid,
                    onOpen = onOpenTile,
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
                if (editing) {
                    SanvyaButton(
                        onClick = { addOpen = true },
                        modifier = Modifier.padding(horizontal = 16.dp).fillMaxWidth(),
                    ) {
                        SanvyaText(S.Dashboard.addWidget(sRes()), style = SanvyaType.button)
                    }
                }
                Spacer(Modifier.height(8.dp))
            }
        }
    }

    AddWidgetSheet(open = addOpen, isPaid = isPaid, onClose = { addOpen = false })

    // The first-run walkthrough, mounted here rather than in the shell because
    // that is where web mounts it (`apps/web/app/page.tsx` renders
    // `<Walkthrough />` in both of the dashboard's branches) -- and it is the
    // right place: the dashboard is where a new user actually lands and stalls.
    // It gates itself; `WalkthroughHost` renders nothing when it should not
    // show.
    WalkthroughHost(
        onNavigateToLogin = onSignIn,
        onNavigateToPlans = onOpenSettings,
    )
}

@Composable
private fun EmptyDashboard(onAddAccount: () -> Unit = {}, modifier: Modifier = Modifier) {
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
                Text(S.Onboarding.wtIntroTitle(sRes()), fontSize = 26.sp, fontWeight = FontWeight.Bold, color = colors.text)
                Text(
                    "Start by adding your first account — just your own note of somewhere your money sits. " +
                        "Nothing here connects to your bank; you type the amounts in yourself.",
                    fontSize = 14.sp,
                    color = colors.text2,
                )
                Button(onClick = onAddAccount) {
                    Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Add your first account")
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
    // `formatMoneyAware` already consults the setting, but this screen
// distinguishes a long mask for the hero from a short one for the delta,
// so the choice stays here and the formatter is asked for the unmasked form.
    val netFormatted = if (hidden) "••••••" else formatMoneyUnmasked(state.net)
    val deltaFormatted = if (hidden) "••••" else formatMoney(abs(state.deltaMinor), state.net.currency, mask = "••••")
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
                    text = if (state.showAvailable) S.Translation.netWorthAvailable(sRes()) else S.Translation.netWorthTitle(sRes()),
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
                        text = if (state.showAvailable) "Excluding blocked" else S.Translation.netWorthWithBlocked(sRes()),
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
    onViewAll: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
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
                Text(S.Translation.navAccounts(sRes()), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = colors.text)
                val suffix = if (accounts.size > 8) " (${accounts.size})" else ""
                Text(
                    "View all$suffix",
                    fontSize = 13.sp,
                    color = colors.accent,
                    modifier = Modifier.clickable(onClick = onViewAll),
                )
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
                            text = if (hidden) "••••••" else formatMoneyUnmasked(item.balance),
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

// accountColor()/colorForId() now shared -- see ui/AccountColors.kt
// (extracted 2026-08-05 when the Accounts screen needed the same palette;
// this file used to have its own private copy).
