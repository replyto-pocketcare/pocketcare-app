package com.sanvya.app.ui.shell

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaIcons
import com.sanvya.app.theme.SanvyaMetrics
import com.sanvya.app.theme.SanvyaShape
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaIcon
import com.sanvya.app.ui.components.SanvyaText
import kotlinx.coroutines.delay

/** Matches web's `APP_VERSION` in AppShell.tsx. */
private const val APP_VERSION = "0.1.0"

/**
 * Routes that render with no app chrome at all — web's `bare` check.
 * Onboarding, login and join are decisions, not destinations.
 */
private val BARE_ROUTES = setOf("onboarding", "login", "join")

/**
 * Flow steps that get a Back affordance despite being a single path segment.
 * They are steps in a sequence with nowhere else to go back to.
 */
private val FLOW_ROOTS = setOf("receipts/new", "receipts/review", "receipts/split")

/**
 * The app shell: banners, the utility row, the floating bottom bar, and the
 * overlays that hang off it.
 *
 * Replaces the Material navigation drawer this app used to have. The drawer was
 * not a port of anything — web's phone layout has never had one — and it put
 * every destination two taps and a gesture away from a bar that web keeps
 * permanently on screen.
 *
 * Full spec, with every value traced back to `globals.css`:
 * `docs/mobile/screen-specs/app-shell.md`.
 */
@Composable
fun AppShell(
    currentRoute: String?,
    onNavigate: (String) -> Unit,
    onBack: () -> Unit,
    pageAction: AddAction?,
    onSetPageAction: (AddAction?) -> Unit,
    viewModel: ShellViewModel = viewModel(),
    content: @Composable () -> Unit,
) {
    val colors = LocalSanvyaColors.current
    val offline = rememberIsOffline()
    val unreadCount by viewModel.unreadCount.collectAsState()
    val failedWrites by viewModel.failedWriteCount.collectAsState()
    val isGuest by viewModel.isGuest.collectAsState()
    val guestDaysLeft by viewModel.guestDaysLeft.collectAsState()
    val canScan by viewModel.canScan.collectAsState()
    val navIds by NavPrefs.ids.collectAsState()

    var moreOpen by remember { mutableStateOf(false) }
    var customizeOpen by remember { mutableStateOf(false) }
    var addOpen by remember { mutableStateOf(false) }

    val bare = currentRoute != null && BARE_ROUTES.any { currentRoute.startsWith(it) }
    // The dashboard places its own greeting and bell as the very first thing on
    // the page, so the shared utility row is skipped there entirely.
    val isDashboard = currentRoute == "dashboard"
    val showBack = currentRoute != null &&
        (currentRoute.count { it == '/' } >= 1 || currentRoute in FLOW_ROOTS)

    // `failed_writes` is local-only, so there is no sync event to observe.
    // Web polls every 30s; so does this.
    LaunchedEffect(Unit) {
        while (true) {
            delay(30_000)
            viewModel.refreshFailedWrites()
        }
    }

    // Overlays never survive a navigation — web closes both on every route change.
    LaunchedEffect(currentRoute) {
        moreOpen = false
        addOpen = false
    }

    if (bare) {
        Column(modifier = Modifier.fillMaxSize().background(colors.bg)) {
            OfflineBanner(offline)
            content()
        }
        return
    }

    val action = pageAction ?: defaultAddAction(canScan)
    val runAdd: () -> Unit = {
        when (action) {
            is AddAction.Link -> onNavigate(action.route)
            is AddAction.Button -> action.onClick()
            is AddAction.Menu -> addOpen = !addOpen
        }
    }

    Box(modifier = Modifier.fillMaxSize().background(colors.bg)) {
        Column(modifier = Modifier.fillMaxSize()) {
            // Banners sit above everything, in web's z-order: problems first.
            Column(modifier = Modifier.padding(WindowInsets.statusBars.asPaddingValues())) {
                SyncProblemsBanner(failedWrites) { onNavigate("settings") }
                OfflineBanner(offline)
            }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .padding(
                        top = SanvyaMetrics.Page.paddingTop,
                        start = SanvyaMetrics.Page.paddingHorizontal,
                        end = SanvyaMetrics.Page.paddingHorizontal,
                    ),
            ) {
                if (!isDashboard) {
                    UtilRow(
                        showBack = showBack,
                        unreadCount = unreadCount,
                        onBack = onBack,
                        onNotifications = { onNavigate("notifications") },
                    )
                }
                CompositionLocalProviderForAddAction(onSetPageAction) { content() }
            }
        }

        BottomNav(
            currentRoute = currentRoute,
            navIds = navIds,
            unreadCount = unreadCount,
            addLabel = action.label,
            onNavigate = onNavigate,
            onAdd = runAdd,
            onMore = { moreOpen = true },
            moreOpen = moreOpen,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(WindowInsets.navigationBars.asPaddingValues())
                .padding(
                    start = SanvyaMetrics.BottomNav.sideInset,
                    end = SanvyaMetrics.BottomNav.sideInset,
                    bottom = SanvyaMetrics.BottomNav.bottomInset,
                )
                .widthIn(max = SanvyaMetrics.BottomNav.maxWidth),
        )

        if (addOpen && action is AddAction.Menu) {
            AddPopover(
                action = action,
                onDismiss = { addOpen = false },
                onNavigate = { route -> addOpen = false; onNavigate(route) },
                modifier = Modifier.align(Alignment.BottomCenter),
            )
        }
    }

    MoreSheet(
        open = moreOpen,
        currentRoute = currentRoute,
        unreadCount = unreadCount,
        isGuest = isGuest,
        guestDaysLeft = guestDaysLeft,
        onNavigate = { route -> moreOpen = false; onNavigate(route) },
        onCustomize = { moreOpen = false; customizeOpen = true },
        onFeedback = { moreOpen = false },
        onClose = { moreOpen = false },
        appVersion = APP_VERSION,
    )

    BottomNavCustomizer(
        open = customizeOpen,
        current = navIds,
        onSave = { ids -> NavPrefs.setIds(ids); customizeOpen = false },
        onClose = { customizeOpen = false },
    )
}

@Composable
private fun CompositionLocalProviderForAddAction(
    setter: (AddAction?) -> Unit,
    content: @Composable () -> Unit,
) {
    CompositionLocalProvider(
        LocalAddActionSetter provides setter,
        content = content,
    )
}

/**
 * Live connectivity, for the offline banner.
 *
 * A `NetworkCallback` rather than a poll: connectivity genuinely is an event
 * stream here, unlike `failed_writes`, and the banner has to appear the moment
 * signal drops rather than up to 30 seconds later.
 */
@Composable
private fun rememberIsOffline(): Boolean {
    val context = LocalContext.current
    var offline by remember { mutableStateOf(false) }

    DisposableEffect(context) {
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        if (manager == null) {
            onDispose { }
        } else {
            fun hasInternet(): Boolean {
                val caps = manager.getNetworkCapabilities(manager.activeNetwork)
                return caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
            }
            offline = !hasInternet()

            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) { offline = false }
                override fun onLost(network: Network) { offline = !hasInternet() }
            }
            manager.registerDefaultNetworkCallback(callback)
            onDispose { manager.unregisterNetworkCallback(callback) }
        }
    }
    return offline
}

/**
 * The contextual add menu — a small floating panel above the bar, not a bottom
 * sheet. Web's is a popover and a sheet would read as a much heavier gesture
 * for a two-item choice.
 */
@Composable
private fun AddPopover(
    action: AddAction.Menu,
    onDismiss: () -> Unit,
    onNavigate: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalSanvyaColors.current
    val metrics = SanvyaMetrics.AddPopover

    // A transparent full-screen scrim: it dims nothing (the popover already
    // floats above an undimmed page on web) and exists purely as a big
    // dismiss target.
    Box(
        modifier = Modifier
            .fillMaxSize()
            .clickableNoIndication(onDismiss),
    )

    SanvyaCard(
        modifier = modifier
            .padding(bottom = metrics.bottomOffset, start = 16.dp, end = 16.dp)
            .widthIn(min = metrics.minWidth),
        shape = SanvyaShape.popover,
        padding = PaddingValues(metrics.padding),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(metrics.gap)) {
            action.items.forEach { item ->
                AddPopoverItem(
                    item = item,
                    onClick = {
                        item.route?.let(onNavigate)
                        item.onClick?.invoke()
                        onDismiss()
                    },
                )
            }
        }
    }
}

@Composable
private fun AddPopoverItem(item: AddAction.Menu.Item, onClick: () -> Unit) {
    val colors = LocalSanvyaColors.current
    val metrics = SanvyaMetrics.AddPopover
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickableNoIndication(onClick)
            .padding(horizontal = metrics.itemPaddingH, vertical = metrics.itemPaddingV),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SanvyaIcon(item.glyph, size = 17.dp, tint = colors.text)
        SanvyaText(
            text = item.label,
            style = SanvyaType.button,
            color = colors.text,
            modifier = Modifier.weight(1f),
        )
        if (item.locked) {
            // A lock, not a tier name: the plans are Lite and Pro, so naming
            // one would be either wrong or only half the answer.
            SanvyaIcon(
                glyph = SanvyaIcons.lock,
                size = 13.dp,
                tint = colors.text3,
                description = "Paid plan required",
            )
        }
    }
}

/**
 * A tap target with no ripple.
 *
 * The design system's feedback is `.press` (a scale), not Material's ripple —
 * mixing the two would put two different feedback languages on one screen.
 */
private fun Modifier.clickableNoIndication(onClick: () -> Unit): Modifier = composed {
    val interaction = remember { MutableInteractionSource() }
    clickable(interactionSource = interaction, indication = null, onClick = onClick)
}
