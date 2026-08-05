package com.sanvya.app.ui.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.sanvya.app.ui.SettingsScreen
import com.sanvya.app.ui.accounts.AccountsScreen
import com.sanvya.app.ui.accounts.CreateAccountScreen
import com.sanvya.app.ui.accounts.EditAccountScreen
import com.sanvya.app.ui.dashboard.DashboardScreen
import com.sanvya.app.ui.transactions.CreateTransactionScreen
import com.sanvya.app.ui.transactions.EditTransactionScreen
import com.sanvya.app.ui.transactions.TransactionsScreen

/**
 * Root nav graph. `MainActivity.kt` referenced this (unqualified,
 * `com.sanvya.app.ui.navigation.SanvyaNavHost`) before this file existed —
 * verified 2026-08-05, another dangling reference (alongside SanvyaTheme,
 * the missing Application class, and Prefs — see docs/plans/
 * mobile-pixel-parity-plan.md and the 2026-08-05 AUDIT_HISTORY.md entry).
 *
 * Routes to screens that are actually real: "dashboard", "settings",
 * "accounts", "accounts/new", "accounts/{accountId}/edit", "transactions",
 * "transactions/new", "transactions/{transactionId}/edit". Every other web
 * route (budgets, goals, splits, receipts, statements, investments, credit
 * cards, assistant, loans, onboarding/login) has no Android screen yet —
 * adding a placeholder/stub destination for those would just be a
 * smaller-scale repeat of the false-DONE problem. They get added to this
 * graph as their own screens land (docs/mobile/TODO.md Phase 3 tracks each
 * one).
 */
@Composable
fun SanvyaNavHost() {
    val navController = rememberNavController()
    NavHost(navController = navController, startDestination = "dashboard") {
        composable("dashboard") {
            DashboardScreen(
                onOpenSettings = { navController.navigate("settings") },
                onAddAccount = { navController.navigate("accounts/new") },
                onViewAccounts = { navController.navigate("accounts") },
                onViewTransactions = { navController.navigate("transactions") },
            )
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
