package com.sanvya.app.ui.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.sanvya.app.ui.SettingsScreen
import com.sanvya.app.ui.dashboard.DashboardScreen

/**
 * Root nav graph. `MainActivity.kt` referenced this (unqualified,
 * `com.sanvya.app.ui.navigation.SanvyaNavHost`) before this file existed —
 * verified 2026-08-05, another dangling reference (alongside SanvyaTheme,
 * the missing Application class, and Prefs — see docs/plans/
 * mobile-pixel-parity-plan.md and the 2026-08-05 AUDIT_HISTORY.md entry).
 *
 * Deliberately minimal: only routes to screens that are actually real
 * ("dashboard", "settings"). Every other web route (accounts, transactions,
 * budgets, goals, splits, receipts, statements, investments, credit cards,
 * assistant, loans, onboarding/login) has no Android screen yet — adding a
 * placeholder/stub destination for those would just be a smaller-scale
 * repeat of the false-DONE problem. They get added to this graph as their
 * own screens land (docs/mobile/TODO.md Phase 3 tracks each one).
 */
@Composable
fun SanvyaNavHost() {
    val navController = rememberNavController()
    NavHost(navController = navController, startDestination = "dashboard") {
        composable("dashboard") {
            DashboardScreen(onOpenSettings = { navController.navigate("settings") })
        }
        composable("settings") {
            // SettingsScreen's top bar only wires its hamburger icon
            // (onOpenDrawer), not onNavigateBack -- there's no drawer built
            // yet, so this maps that icon to "back to dashboard" for now
            // (a real, working action) rather than a no-op or a fake drawer.
            SettingsScreen(
                onNavigateBack = { navController.popBackStack() },
                onOpenDrawer = { navController.popBackStack() },
            )
        }
    }
}
