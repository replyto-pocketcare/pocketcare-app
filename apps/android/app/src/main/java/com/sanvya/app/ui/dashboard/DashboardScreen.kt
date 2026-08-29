package com.sanvya.app.ui.dashboard

import android.content.res.Resources
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.compose.runtime.saveable.rememberSaveable
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.Eyebrow
import com.sanvya.app.ui.components.H1
import com.sanvya.app.ui.components.SanvyaButton
import com.sanvya.app.ui.components.SanvyaChip
import com.sanvya.app.ui.components.SanvyaText
import com.sanvya.app.ui.components.Skeleton
import com.sanvya.app.ui.components.press
import com.sanvya.app.ui.onboarding.WalkthroughHost
import com.sanvya.app.ui.shell.LocalShellNavigate
import com.sanvya.app.ui.shell.LocalWindowClass
import com.sanvya.app.ui.shell.SanvyaWindowClass
import com.sanvya.app.ui.shell.NotifBell
import com.sanvya.app.data.repository.AccountWithBalance
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaColors
import com.sanvya.app.theme.SanvyaMetrics
import com.sanvya.app.theme.SanvyaRadius
import com.sanvya.app.theme.SanvyaShape
import com.sanvya.app.ui.Prefs
import com.sanvya.app.ui.accountColor
import kotlin.math.abs
import java.time.LocalTime
import com.sanvya.app.ui.formatMoney
import com.sanvya.app.ui.formatMoneyUnmasked
import com.sanvya.app.ui.colorForId
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes

/**
 * Dashboard — ported from apps/web/app/page.tsx per
 * docs/mobile/screen-specs/dashboard.md: the greeting header, the net-worth
 * hero, the accounts strip and the customizable tile grid.
 *
 * **Three states, not two.** Web's page has a loading branch above its empty
 * branch and the difference is the whole point of it: for the first seconds of a
 * returning user's first launch the local database is empty because the data is
 * still downloading, and the empty branch tells that person to add their first
 * account. Both ports had two states until 2026-08-28.
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
    /**
     * No longer read here. The top app bar this screen used to draw is gone:
     * web's dashboard has no app bar at all, it has the greeting header below,
     * whose controls are Customize / Hide / the bell and nothing else. The
     * Transactions and Settings shortcuts that used to sit in it were this
     * app's own additions and both destinations are on the bottom bar. Kept in
     * the signature because the nav graph still supplies them.
     */
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
    // The bell's badge. The shared utility row is skipped on this route (see
    // AppShell.kt) precisely because the dashboard carries its own bell, so the
    // count has to be read here too.
    val unreadCount by shellViewModel.unreadCount.collectAsState()
    val navigate = LocalShellNavigate.current
    val windowClass = LocalWindowClass.current
    var editing by rememberSaveable { mutableStateOf(false) }
    var addOpen by rememberSaveable { mutableStateOf(false) }

    Scaffold(
        containerColor = colors.bg,
        // No floatingActionButton: the shell's centre "+" is the app's one add
        // affordance, on every screen, exactly as on web. The speed dial that
        // used to live here was this app's only quick-add control before the
        // shell existed; keeping it would put two "+" buttons on the dashboard.
    ) { padding ->
        when {
            // While the local read has not returned OR the first sync from the
            // server has not landed, show widget-shaped placeholders -- never
            // the "add your first account" screen. page.tsx guards the same way
            // and says why: that screen flashed during the initial sync, which
            // tells a returning user their money is gone.
            uiState.accounts.isEmpty() && (!uiState.accountsLoaded || uiState.syncPending) ->
                DashboardSkeleton(modifier = Modifier.padding(padding))

            uiState.accounts.isEmpty() ->
                EmptyDashboard(onAddAccount = onAddAccount, modifier = Modifier.padding(padding))

            else -> Column(
                modifier = Modifier
                    .padding(padding)
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(top = 4.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                DashboardHeader(
                    displayName = uiState.displayName,
                    editing = editing,
                    hidden = amountsHidden,
                    unreadCount = unreadCount,
                    onToggleEditing = { editing = !editing },
                    onToggleHidden = { Prefs.setAmountsHidden(!amountsHidden) },
                    onNotifications = { navigate("notifications") },
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
                // The wide-window layout, and the two things that were missing
                // from it. Web gates both on `useIsDesktop()` (its own 1024px
                // media query); the port gates on the window class the shell
                // already publishes, because that is what every other Android
                // app on the device switches at and a CSS pixel width is not a
                // number a tablet is measured in.
                if (windowClass == SanvyaWindowClass.EXPANDED) {
                    StatRow(
                        stats = uiState.stats,
                        hidden = amountsHidden,
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                    // Web's `.dash-hero-row`: the headline card and the
                    // assistant share a row, which is the "headline + right
                    // rail" shape of a conventional dashboard.
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                        horizontalArrangement = Arrangement.spacedBy(20.dp),
                    ) {
                        NetWorthHero(
                            state = uiState.hero,
                            hidden = amountsHidden,
                            onToggle = { viewModel.toggleShowAvailable() },
                            modifier = Modifier.weight(1f),
                        )
                        AssistantWidget(modifier = Modifier.width(360.dp))
                    }
                } else {
                    NetWorthHero(
                        state = uiState.hero,
                        hidden = amountsHidden,
                        onToggle = { viewModel.toggleShowAvailable() },
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                }
                // "Worth a look". Renders nothing until there is enough history
                // for a suggestion to be an observation rather than a pitch, so
                // a brand-new user sees the walkthrough and nothing here.
                //
                // NOT padded horizontally: the rail bleeds to the screen edge on
                // purpose (its own contentPadding insets the cards), so a
                // half-visible card signals that it scrolls.
                SuggestionsStrip(
                    isPaid = isPaid,
                    onOpen = { route -> navigate(route) },
                )
                AccountsCard(
                    accounts = uiState.accounts,
                    hidden = amountsHidden,
                    colors = colors,
                    onViewAll = onViewAccounts,
                    onAddAccount = onAddAccount,
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

/**
 * Web's `.dash-header`: the time-of-day greeting as an eyebrow, the person's
 * name as the page's h1, and the control row beside it.
 *
 * This is the whole reason the shared utility row is skipped on this route --
 * the bell belongs to the header, and drawing both would put two of them on the
 * one screen that has its own.
 */
@Composable
private fun DashboardHeader(
    displayName: String,
    editing: Boolean,
    hidden: Boolean,
    unreadCount: Int,
    onToggleEditing: () -> Unit,
    onToggleHidden: () -> Unit,
    onNotifications: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val res = sRes()
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Eyebrow(timeGreeting(res))
            // `compact = false` -- web's is clamp(24px, 6.5vw, 30px), i.e. the
            // full h1, not the tightened one lists use.
            H1(
                text = displayName.ifBlank { S.Dashboard.greetingFallback(res) },
                compact = false,
            )
        }
        SanvyaChip(
            label = if (editing) S.Translation.commonDone(res) else S.Dashboard.customize(res),
            active = editing,
            onClick = onToggleEditing,
        )
        HideAmountsButton(hidden = hidden, onClick = onToggleHidden)
        NotifBell(unreadCount = unreadCount, onClick = onNotifications)
    }
}

/**
 * The eye toggle, icon-only.
 *
 * Web's is a chip with the word "Hide"/"Show" beside the icon. At phone width
 * three labelled chips plus the bell do not fit next to a name, so this one
 * keeps the icon and moves the words into the content description -- where a
 * screen reader still gets them, which is the half that was load-bearing.
 */
@Composable
private fun HideAmountsButton(hidden: Boolean, onClick: () -> Unit) {
    val colors = LocalSanvyaColors.current
    val util = SanvyaMetrics.UtilRow
    val interaction = remember { MutableInteractionSource() }
    // Hoisted: `semantics { }` is a plain lambda, not a composable one, so
    // `sRes()` cannot be called inside it.
    val description = if (hidden) {
        S.Dashboard.showAmountsA11y(sRes())
    } else {
        S.Dashboard.hideAmountsA11y(sRes())
    }
    Box(
        modifier = Modifier
            .size(util.buttonSize)
            .press(interaction)
            .clip(SanvyaShape.pill)
            .background(colors.surface)
            .border(1.dp, colors.border, SanvyaShape.pill)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = if (hidden) Icons.Default.Visibility else Icons.Default.VisibilityOff,
            contentDescription = null,
            tint = colors.text,
            modifier = Modifier.size(19.dp),
        )
    }
}

/**
 * Good morning / afternoon / evening / night, on page.tsx's own boundaries:
 * < 5 night, < 12 morning, < 17 afternoon, < 21 evening, else night.
 *
 * `remember`ed rather than read on every recomposition. The hour cannot change
 * while the dashboard is on screen, and reading a clock inside a composable
 * makes what a frame renders depend on when the frame happened to run.
 *
 * Web's `timeGreeting()` returns four hardcoded English strings -- the greeting
 * is the one line on its dashboard that never translates. Recorded in
 * docs/mobile/PARITY_AUDIT.md under "Web defects found while porting"; the
 * native ports use real keys.
 */
@Composable
private fun timeGreeting(res: Resources): String {
    val hour = remember { LocalTime.now().hour }
    return when {
        hour < 5 -> S.Dashboard.greetingNight(res)
        hour < 12 -> S.Dashboard.greetingMorning(res)
        hour < 17 -> S.Dashboard.greetingAfternoon(res)
        hour < 21 -> S.Dashboard.greetingEvening(res)
        else -> S.Dashboard.greetingNight(res)
    }
}

/**
 * Widget-shaped placeholders for the first seconds of a returning user's first
 * launch -- page.tsx's own skeleton block, block for block: a hero, the
 * accounts card with six chips, one full-width tile and a pair of half ones.
 */
@Composable
private fun DashboardSkeleton(modifier: Modifier = Modifier) {
    val colors = LocalSanvyaColors.current
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        Skeleton(height = 132.dp, modifier = Modifier.fillMaxWidth(), radius = SanvyaRadius.radiusLg)
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = colors.surface),
            shape = RoundedCornerShape(SanvyaRadius.radiusLg),
        ) {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Skeleton(height = 18.dp, modifier = Modifier.width(120.dp))
                repeat(2) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        repeat(3) {
                            Skeleton(
                                height = 58.dp,
                                modifier = Modifier.weight(1f),
                                radius = SanvyaRadius.radiusSm,
                            )
                        }
                    }
                }
            }
        }
        Skeleton(height = 190.dp, modifier = Modifier.fillMaxWidth(), radius = SanvyaRadius.radiusLg)
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            repeat(2) {
                Skeleton(height = 150.dp, modifier = Modifier.weight(1f), radius = SanvyaRadius.radiusLg)
            }
        }
    }
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
    colors: SanvyaColors,
    onViewAll: () -> Unit = {},
    onAddAccount: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val res = sRes()
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
                Text(S.Translation.navAccounts(res), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = colors.text)
                // Web appends the total only once the strip has stopped showing
                // all of them -- the number is there to say "there are more",
                // not to count what you can already see.
                Text(
                    text = if (accounts.size > 8) {
                        S.Dashboard.viewAllCount(res, accounts.size)
                    } else {
                        S.Dashboard.viewAll(res)
                    },
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
                // The add-account tile, last in the strip and the same footprint
                // as an account: outlined instead of filled, exactly as web
                // draws it. Without it the only way to add a second account was
                // to go to Accounts first, which is two screens for the action
                // the strip is about.
                item { AddAccountTile(colors = colors, onClick = onAddAccount) }
            }
        }
    }
}

@Composable
private fun AddAccountTile(colors: SanvyaColors, onClick: () -> Unit) {
    val res = sRes()
    // Hoisted: `semantics { }` is a plain lambda, not a composable one.
    val description = S.Dashboard.accountsAddA11y(res)
    Column(
        modifier = Modifier
            .width(112.dp)
            // Matches the height a three-line account chip settles at, so the
            // strip does not step down at its last tile.
            .defaultMinSize(minHeight = 58.dp)
            .clip(RoundedCornerShape(SanvyaRadius.radiusSm))
            .border(1.5.dp, colors.borderStrong, RoundedCornerShape(SanvyaRadius.radiusSm))
            .clickable(onClick = onClick)
            .semantics { contentDescription = description }
            .padding(horizontal = 11.dp, vertical = 9.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            imageVector = Icons.Default.Add,
            contentDescription = null,
            tint = colors.text2,
            modifier = Modifier.size(18.dp),
        )
        Spacer(Modifier.height(4.dp))
        Text(
            S.Dashboard.accountsAdd(res),
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = colors.text2,
        )
    }
}

// accountColor()/colorForId() now shared -- see ui/AccountColors.kt
// (extracted 2026-08-05 when the Accounts screen needed the same palette;
// this file used to have its own private copy).
