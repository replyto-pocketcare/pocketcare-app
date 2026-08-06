package com.sanvya.app.ui.navigation

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.Bookmarks
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Dashboard
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.DonutSmall
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Help
import androidx.compose.material.icons.filled.Insights
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.RequestQuote
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.SelfImprovement
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.TrendingUp
import androidx.compose.material.icons.filled.WaterfallChart
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.NavigationDrawerItemDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sanvya.app.theme.LocalSanvyaColors
import java.net.URLEncoder

/**
 * App navigation drawer — ported from `apps/web/app/AppShell.tsx`'s
 * `NAV_GROUPS` array (lines 135-167) + the `<aside>` sidebar block per
 * docs/mobile/screen-specs/navigation-drawer.md. NOT ported from iOS's
 * DrawerMenuView/NavModels.swift, which turned out to be missing 2 of
 * these items itself (Notifications, Reflect) when checked against the
 * real web source 2026-08-05 -- both platforms are corrected against web
 * in this same pass, not against each other.
 *
 * [route] is either a real SanvyaNavHost route (for the 4 screens that
 * exist today: dashboard/accounts/transactions/settings) or
 * "coming_soon/<title>" for everything else -- swapped to a real route as
 * each screen gets built (docs/mobile/TODO.md tracks each one). This
 * mirrors iOS's own PlaceholderView pattern for its own not-yet-built
 * tabs, not an Android-only shortcut.
 */
data class DrawerNavItem(
    val title: String,
    val icon: ImageVector,
    val route: String,
)

data class DrawerNavGroup(
    val title: String,
    val items: List<DrawerNavItem>,
)

/** Builds a "coming_soon/{title}" route with the title URL-encoded --
 * several titles below contain spaces ("Ask Sanvya") or "&" ("Splits &
 * groups"), neither of which is safe to inline raw into a Navigation
 * Compose path segment. */
fun comingSoonRoute(title: String): String = "coming_soon/" + URLEncoder.encode(title, "UTF-8")

/** [Notifications] renders above the groups on web (AppShell.tsx:303), not
 * inside one -- kept separate here for the same reason. */
val notificationsDrawerItem = DrawerNavItem("Notifications", Icons.Default.Notifications, comingSoonRoute("Notifications"))

val drawerNavGroups: List<DrawerNavGroup> = listOf(
    DrawerNavGroup("", listOf(
        DrawerNavItem("Dashboard", Icons.Default.Dashboard, "dashboard"),
        DrawerNavItem("Ask Sanvya", Icons.Default.AutoAwesome, comingSoonRoute("Ask Sanvya")),
    )),
    DrawerNavGroup("Money", listOf(
        DrawerNavItem("Accounts", Icons.Default.AccountBalance, "accounts"),
        DrawerNavItem("Transactions", Icons.Default.SwapHoriz, "transactions"),
        DrawerNavItem("Templates", Icons.Default.Bookmarks, comingSoonRoute("Templates")),
        DrawerNavItem("Cards", Icons.Default.CreditCard, comingSoonRoute("Cards")),
        DrawerNavItem("Splits & groups", Icons.Default.Groups, comingSoonRoute("Splits & groups")),
        DrawerNavItem("Search", Icons.Default.Search, comingSoonRoute("Search")),
    )),
    DrawerNavGroup("Planning", listOf(
        DrawerNavItem("Budgets", Icons.Default.DonutSmall, "budgets"),
        DrawerNavItem("Goals", Icons.Default.Flag, "goals"),
        DrawerNavItem("Planned Cashflow", Icons.Default.WaterfallChart, comingSoonRoute("Planned Cashflow")),
        DrawerNavItem("Recurring", Icons.Default.Autorenew, comingSoonRoute("Recurring")),
        DrawerNavItem("Loans", Icons.Default.RequestQuote, "loans"),
    )),
    DrawerNavGroup("Growth", listOf(
        DrawerNavItem("Investments", Icons.Default.TrendingUp, "investments"),
        DrawerNavItem("Reflect", Icons.Default.SelfImprovement, comingSoonRoute("Reflect")),
        DrawerNavItem("Insights", Icons.Default.Insights, "insights"),
        DrawerNavItem("Statements", Icons.Default.Description, comingSoonRoute("Statements")),
    )),
    DrawerNavGroup("", listOf(
        DrawerNavItem("Settings", Icons.Default.Settings, "settings"),
        DrawerNavItem("Help & FAQ", Icons.Default.Help, comingSoonRoute("Help & FAQ")),
    )),
)

@Composable
fun DrawerContent(
    currentRoute: String?,
    onNavigate: (String) -> Unit,
) {
    val colors = LocalSanvyaColors.current
    ModalDrawerSheet(drawerContainerColor = colors.bg) {
        Column(modifier = Modifier.padding(top = 8.dp)) {
            Text(
                "Sanvya",
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = colors.text,
                modifier = Modifier.padding(horizontal = 24.dp, vertical = 12.dp),
            )
            LazyColumn(modifier = Modifier.fillMaxHeight()) {
                item {
                    DrawerRow(notificationsDrawerItem, selected = currentRoute == notificationsDrawerItem.route, onNavigate = onNavigate)
                }
                items(drawerNavGroups) { group ->
                    Column {
                        if (group.title.isNotEmpty()) {
                            Text(
                                group.title.uppercase(),
                                fontSize = 10.5.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = colors.text2,
                                modifier = Modifier.padding(start = 24.dp, top = 16.dp, bottom = 2.dp),
                            )
                        } else {
                            Spacer(Modifier.height(8.dp))
                        }
                        group.items.forEach { item ->
                            DrawerRow(item, selected = currentRoute == item.route, onNavigate = onNavigate)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DrawerRow(item: DrawerNavItem, selected: Boolean, onNavigate: (String) -> Unit) {
    NavigationDrawerItem(
        icon = { Icon(item.icon, contentDescription = null) },
        label = { Text(item.title) },
        selected = selected,
        onClick = { onNavigate(item.route) },
        colors = NavigationDrawerItemDefaults.colors(),
        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 2.dp),
    )
}
