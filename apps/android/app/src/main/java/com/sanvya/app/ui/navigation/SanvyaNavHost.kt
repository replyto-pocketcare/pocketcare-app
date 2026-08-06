package com.sanvya.app.ui.navigation

import androidx.compose.material3.DrawerValue
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.rememberDrawerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.sanvya.app.ui.ComingSoonScreen
import com.sanvya.app.ui.SettingsScreen
import com.sanvya.app.ui.accounts.AccountsScreen
import com.sanvya.app.ui.accounts.CreateAccountScreen
import com.sanvya.app.ui.accounts.EditAccountScreen
import com.sanvya.app.ui.dashboard.DashboardScreen
import com.sanvya.app.ui.transactions.CreateTransactionScreen
import com.sanvya.app.ui.transactions.EditTransactionScreen
import com.sanvya.app.ui.transactions.TransactionsScreen
import kotlinx.coroutines.launch

/**
 * Root nav graph. `MainActivity.kt` referenced this (unqualified,
 * `com.sanvya.app.ui.navigation.SanvyaNavHost`) before this file existed —
 * verified 2026-08-05, another dangling reference (alongside SanvyaTheme,
 * the missing Application class, and Prefs — see docs/plans/
 * mobile-pixel-parity-plan.md and the 2026-08-05 AUDIT_HISTORY.md entry).
 *
 * Wrapped in a `ModalNavigationDrawer` added 2026-08-05 (see
 * docs/mobile/screen-specs/navigation-drawer.md) -- Akhilesh caught that
 * Dashboard had no hamburger menu at all, and iOS's equivalent
 * (MainTabView/DrawerMenuView) turned out to be the real, pre-existing
 * pattern this was missing. Android keeps its own push/pop back-stack
 * per top-level section (idiomatic here, already working for Accounts/
 * Transactions' CRUD sub-routes) rather than copying iOS's flat
 * tab-switch architecture -- the drawer is an added entry point on top of
 * it, matching standard Android convention: root destinations
 * (Dashboard) show the hamburger and open the drawer; non-root/detail
 * screens (Accounts, Transactions, their New/Edit sub-routes) keep their
 * existing back arrow, since "Up" from them always means "back to
 * Dashboard" regardless of whether you arrived via the drawer or via
 * Dashboard's own buttons.
 *
 * Routes to screens that are actually real: "dashboard", "settings",
 * "accounts", "accounts/new", "accounts/{accountId}/edit", "transactions",
 * "transactions/new", "transactions/{transactionId}/edit". Every drawer
 * item without a real screen yet routes to "coming_soon/{title}" (a
 * shared placeholder, matching iOS's own `PlaceholderView` for its
 * not-yet-built tabs) rather than a dead link or a silently-omitted menu
 * entry -- each one gets swapped for a real destination as its own screen
 * lands (docs/mobile/TODO.md Phase 3 tracks each one).
 */
@Composable
fun SanvyaNavHost() {
    val navController = rememberNavController()
    val drawerState = rememberDrawerState(initialValue = DrawerValue.Closed)
    val scope = rememberCoroutineScope()
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route

    ModalNavigationDrawer(
        drawerState = drawerState,
        drawerContent = {
            DrawerContent(
                // Known minor limitation: `currentRoute` here is the
                // resolved backstack route (works for the 4 real,
                // param-less destinations), but `entry.destination.route`
                // for "coming_soon/{title}" is the PATTERN, not the
                // resolved "coming_soon/<encoded title>" value -- so the
                // selected-highlight and the `route != currentRoute` guard
                // below never quite match for coming-soon items. Cosmetic
                // only (worst case: re-navigating to the same placeholder,
                // or it never highlighting as selected) -- not worth a
                // second route-comparison scheme for a screen that's a
                // stand-in itself.
                currentRoute = currentRoute,
                onNavigate = { route ->
                    scope.launch { drawerState.close() }
                    if (route != currentRoute) {
                        navController.navigate(route) {
                            popUpTo("dashboard") { inclusive = false }
                            launchSingleTop = true
                        }
                    }
                },
            )
        },
    ) {
    NavHost(navController = navController, startDestination = "dashboard") {
        composable("dashboard") {
            DashboardScreen(
                onOpenDrawer = { scope.launch { drawerState.open() } },
                onOpenSettings = { navController.navigate("settings") },
                onAddAccount = { navController.navigate("accounts/new") },
                onViewAccounts = { navController.navigate("accounts") },
                onViewTransactions = { navController.navigate("transactions") },
            )
        }
        composable("settings") {
            SettingsScreen(
                onNavigateBack = { navController.popBackStack() },
                onOpenDrawer = { scope.launch { drawerState.open() } },
            )
        }
        composable(
            "coming_soon/{title}",
            arguments = listOf(navArgument("title") { type = NavType.StringType }),
        ) { entry ->
            val encoded = entry.arguments?.getString("title") ?: ""
            ComingSoonScreen(
                title = java.net.URLDecoder.decode(encoded, "UTF-8"),
                onOpenDrawer = { scope.launch { drawerState.open() } },
            )
        }
        composable("accounts") {
            AccountsScreen(
                onBack = { navController.popBackStack() },
                onNewAccount = { navController.navigate("accounts/new") },
                onEditAccount = { id -> navController.navigate("accounts/$id/edit") },
            )
        }
        composable("accounts/new") {
            CreateAccountScreen(
                onBack = { navController.popBackStack() },
                onSaved = { navController.popBackStack() },
            )
        }
        composable(
            "accounts/{accountId}/edit",
            arguments = listOf(navArgument("accountId") { type = NavType.StringType }),
        ) {
            EditAccountScreen(
                onBack = { navController.popBackStack() },
                onSaved = { navController.popBackStack() },
                onDeleted = {
                    // Pop both the edit screen and the accounts list so a
                    // deleted account doesn't linger in the list the user
                    // lands back on.
                    navController.popBackStack("accounts", inclusive = true)
                },
            )
        }
        composable("transactions") {
            TransactionsScreen(
                onBack = { navController.popBackStack() },
                onAddTransaction = { navController.navigate("transactions/new") },
                onEditTransaction = { id -> navController.navigate("transactions/$id/edit") },
            )
        }
        composable("transactions/new") {
            CreateTransactionScreen(
                onBack = { navController.popBackStack() },
                onSaved = { navController.popBackStack() },
                onAddAccountFirst = { navController.navigate("accounts/new") },
            )
        }
        composable(
            "transactions/{transactionId}/edit",
            arguments = listOf(navArgument("transactionId") { type = NavType.StringType }),
        ) {
            EditTransactionScreen(
                onBack = { navController.popBackStack() },
                onSaved = { navController.popBackStack() },
                onDeleted = { navController.popBackStack("transactions", inclusive = true) },
            )
        }
    }
    }
}
