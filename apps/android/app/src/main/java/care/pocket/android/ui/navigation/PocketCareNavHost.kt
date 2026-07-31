package care.pocket.android.ui.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import care.pocket.android.theme.*
import care.pocket.android.ui.AccountsScreen
import care.pocket.android.ui.BudgetsScreen
import care.pocket.android.ui.CreateAccountScreen
import care.pocket.android.ui.CreateBudgetScreen
import care.pocket.android.ui.CreateTransactionScreen
import care.pocket.android.ui.DashboardScreen
import care.pocket.android.ui.TransactionsScreen

enum class NavTab {
    DASHBOARD,
    ACCOUNTS,
    TRANSACTIONS,
    BUDGETS
}

@Composable
fun PocketCareNavHost() {
    var currentTab by remember { mutableStateOf(NavTab.DASHBOARD) }
    var showingCreateAccount by remember { mutableStateOf(false) }
    var showingCreateTxn by remember { mutableStateOf(false) }
    var showingCreateBudget by remember { mutableStateOf(false) }

    if (showingCreateAccount) {
        CreateAccountScreen(
            onDismiss = { showingCreateAccount = false },
            onSave = { _, _, _, _, _ -> showingCreateAccount = false }
        )
    } else if (showingCreateTxn) {
        CreateTransactionScreen(
            onDismiss = { showingCreateTxn = false },
            onSave = { _, _, _, _, _ -> showingCreateTxn = false }
        )
    } else if (showingCreateBudget) {
        CreateBudgetScreen(
            onDismiss = { showingCreateBudget = false },
            onSave = { _, _, _, _ -> showingCreateBudget = false }
        )
    } else {
        Scaffold(
            bottomBar = {
                NavigationBar(
                    containerColor = MaterialTheme.colorScheme.surface,
                    contentColor = Terracotta
                ) {
                    NavigationBarItem(
                        selected = (currentTab == NavTab.DASHBOARD),
                        onClick = { currentTab = NavTab.DASHBOARD },
                        icon = { Text("🏠") },
                        label = { Text("Dashboard") }
                    )
                    NavigationBarItem(
                        selected = (currentTab == NavTab.ACCOUNTS),
                        onClick = { currentTab = NavTab.ACCOUNTS },
                        icon = { Text("💳") },
                        label = { Text("Accounts") }
                    )
                    NavigationBarItem(
                        selected = (currentTab == NavTab.TRANSACTIONS),
                        onClick = { currentTab = NavTab.TRANSACTIONS },
                        icon = { Text("📋") },
                        label = { Text("Txns") }
                    )
                    NavigationBarItem(
                        selected = (currentTab == NavTab.BUDGETS),
                        onClick = { currentTab = NavTab.BUDGETS },
                        icon = { Text("📊") },
                        label = { Text("Budgets") }
                    )
                }
            }
        ) { padding ->
            Surface(modifier = Modifier.padding(padding)) {
                when (currentTab) {
                    NavTab.DASHBOARD -> DashboardScreen()
                    NavTab.ACCOUNTS -> AccountsScreen(
                        onAddAccountClick = { showingCreateAccount = true }
                    )
                    NavTab.TRANSACTIONS -> TransactionsScreen(
                        onAddTransactionClick = { showingCreateTxn = true }
                    )
                    NavTab.BUDGETS -> BudgetsScreen(
                        onAddBudgetClick = { showingCreateBudget = true }
                    )
                }
            }
        }
    }
}
