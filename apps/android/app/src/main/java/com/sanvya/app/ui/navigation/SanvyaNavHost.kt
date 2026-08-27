package com.sanvya.app.ui.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.dialog
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import androidx.compose.ui.window.DialogProperties
import androidx.navigation.NamedNavArgument
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavGraphBuilder
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.ui.shell.LocalWindowClass
import com.sanvya.app.ui.shell.SanvyaWindowClass
import com.sanvya.app.ui.ComingSoonScreen
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.ui.shell.AddAction
import com.sanvya.app.ui.shell.AppShell
import com.sanvya.app.ui.SettingsScreen
import com.sanvya.app.ui.accounts.AccountsScreen
import com.sanvya.app.ui.accounts.CreateAccountScreen
import com.sanvya.app.ui.accounts.EditAccountScreen
import com.sanvya.app.ui.budgets.BudgetsScreen
import com.sanvya.app.ui.budgets.CreateBudgetScreen
import com.sanvya.app.ui.budgets.EditBudgetScreen
import com.sanvya.app.ui.dashboard.DashboardScreen
import com.sanvya.app.ui.goals.CreateGoalScreen
import com.sanvya.app.ui.goals.EditGoalScreen
import com.sanvya.app.ui.goals.GoalsScreen
import com.sanvya.app.ui.investments.AddHoldingScreen
import com.sanvya.app.ui.investments.InvestmentsScreen
import com.sanvya.app.ui.insights.InsightsScreen
import com.sanvya.app.ui.creditcards.CreditCardsScreen
import com.sanvya.app.ui.loans.AddLoanScreen
import com.sanvya.app.ui.loans.LoanDetailScreen
import com.sanvya.app.ui.loans.LoansScreen
import com.sanvya.app.ui.splits.GroupDetailScreen
import com.sanvya.app.ui.splits.SplitsScreen
import com.sanvya.app.ui.transactions.CreateTransactionScreen
import com.sanvya.app.ui.transactions.EditTransactionScreen
import com.sanvya.app.ui.transactions.TransactionsScreen

/**
 * Root nav graph, wrapped in the app shell.
 *
 * `MainActivity.kt` referenced this before this file existed — one of several
 * dangling references found on 2026-08-05 (alongside `SanvyaTheme`, the missing
 * Application class and `Prefs`).
 *
 * **The Material navigation drawer that used to wrap this is gone** (2026-08-23).
 * It was added on 2026-08-05 to give the Dashboard a hamburger it was missing,
 * on the reasoning that iOS's `DrawerMenuView` was "the real, pre-existing
 * pattern". Both were wrong about the source: web's phone layout has never had
 * a drawer. It has a floating bottom bar with four user-customizable slots, a
 * raised centre "+", and a grouped More sheet — see
 * `docs/mobile/screen-specs/app-shell.md`. `AppShell` is that, and the two
 * drawers are deleted rather than kept alongside it.
 *
 * Routes remain as before; every destination without a real screen still lands
 * on `coming_soon/{title}` rather than a dead link, and each is tracked in
 * `docs/mobile/PARITY_AUDIT.md` §4.
 */
/**
 * A create/edit destination, placed by window width.
 *
 * The rule (screen-specs/app-shell.md §8a, Akhilesh 2026-08-24): below 600dp a
 * form is a full page; at 600dp and up it is a dialog. Android was full-page at
 * every width — correct on a phone, wrong on a tablet, where the list you came
 * from should stay visible behind the form.
 *
 * `dialog(...)` is Navigation Compose's own destination builder, not a hand-
 * rolled overlay: the destination keeps its place in the back stack, so
 * `popBackStack()` still closes it and every screen's existing `onBack`/`onSaved`
 * wiring works unchanged. That is the whole reason this is a ten-line helper
 * rather than the nested-NavHost rewrite the audit expected.
 *
 * `usePlatformDefaultWidth = false` for the same reason SanvyaModal sets it —
 * the platform default caps dialog width well below the form's own column.
 *
 * **Known edge:** the graph is built with the width class captured, so crossing
 * 600dp *while a form is open* rebuilds the graph and the open form is closed
 * rather than transformed. Rotating a tablet mid-form loses unsaved input. The
 * alternative — registering both shapes and swapping — changes destination
 * identity, which loses the same input in a less predictable way. Recorded in
 * ABSENT-BY-DECISION.md rather than hidden.
 */
private fun NavGraphBuilder.formDestination(
    route: String,
    windowClass: SanvyaWindowClass,
    arguments: List<NamedNavArgument> = emptyList(),
    content: @Composable (NavBackStackEntry) -> Unit,
) {
    if (windowClass == SanvyaWindowClass.COMPACT) {
        composable(route, arguments = arguments) { entry -> content(entry) }
    } else {
        dialog(
            route,
            arguments = arguments,
            dialogProperties = DialogProperties(usePlatformDefaultWidth = false),
        ) { entry -> content(entry) }
    }
}

/**
 * A destination that exists only so the nav entry pointing at it is not a
 * crash.
 *
 * `ComingSoonScreen`'s own doc comment has said since the drawer was built that
 * it exists "so a tap on an unbuilt drawer item behaves identically on both
 * platforms instead of doing nothing or **crashing**". Nothing was ever routed
 * to it. `search`, `reflect`, `assistant`, `help` and `notifications` are in
 * `NAV_GROUPS`, in the side nav, and two of them in the bottom-bar catalog --
 * and none of them was a destination, so every tap called
 * `navController.navigate("search")` on a route the graph does not contain and
 * threw `IllegalArgumentException`. iOS shows a `PlaceholderView` for the same
 * five; this is the equivalent.
 */
private fun NavGraphBuilder.comingSoon(route: String, label: (android.content.res.Resources) -> String) {
    composable(route) { ComingSoonScreen(title = label(sRes())) }
}

@Composable
fun SanvyaNavHost() {
    val navController = rememberNavController()
    // Captured once per graph build; see formDestination's "known edge".
    val windowClass = LocalWindowClass.current
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route

    // The screen currently on top registers its own "+" action here; the shell
    // falls back to the default (add transaction / scan receipt) for the rest.
    var pageAction by remember { mutableStateOf<AddAction?>(null) }

    AppShell(
        currentRoute = currentRoute,
        onNavigate = { route ->
            if (route != currentRoute) {
                navController.navigate(route) {
                    popUpTo("dashboard") { inclusive = false }
                    launchSingleTop = true
                }
            }
        },
        onBack = { navController.popBackStack() },
        pageAction = pageAction,
        onSetPageAction = { pageAction = it },
    ) {
    NavHost(navController = navController, startDestination = "dashboard") {
        composable("dashboard") {
            DashboardScreen(
                onOpenSettings = { navController.navigate("settings") },
                onSignIn = { navController.navigate("login") },
                onAddAccount = { navController.navigate("accounts/new") },
                onViewAccounts = { navController.navigate("accounts") },
                onViewTransactions = { navController.navigate("transactions") },
                onAddTransaction = { navController.navigate("transactions/new") },
                onScanReceipt = { navController.navigate("receipts/new") },
                // A tile's "more details" tap. The route comes from the
                // generated catalog, which the generator has already checked
                // against the NavTab enum on the iOS side -- and every value it
                // can produce is registered above.
                onOpenTile = { route -> navController.navigate(route) },
            )
        }
        composable("receipts/new") {
            com.sanvya.app.ui.receipts.ReceiptCaptureScreen(
                onBack = { navController.popBackStack() },
                onScanned = { scanId -> navController.navigate("receipts/review/$scanId") { popUpTo("receipts/new") { inclusive = true } } },
            )
        }
        composable(
            "receipts/review/{scanId}",
            arguments = listOf(navArgument("scanId") { type = NavType.StringType }),
        ) { entry ->
            val scanId = entry.arguments?.getString("scanId") ?: ""
            com.sanvya.app.ui.receipts.ReceiptReviewScreen(
                scanId = scanId,
                onBack = { navController.popBackStack() },
                onSaved = { transactionId -> navController.navigate("transactions/$transactionId/edit") { popUpTo("dashboard") } },
            )
        }
        composable("settings") {
            SettingsScreen(
                onNavigateBack = { navController.popBackStack() },
                onManageCategories = { navController.navigate("settings/categories") },
                onManageLabels = { navController.navigate("settings/labels") },
                onImportExport = { navController.navigate("settings/data") },
            )
        }
        composable("settings/data") { com.sanvya.app.ui.data.DataScreen() }
        composable("settings/categories") { com.sanvya.app.ui.taxonomy.CategoriesScreen() }
        composable("settings/labels") { com.sanvya.app.ui.taxonomy.LabelsScreen() }
        composable(
            "coming_soon/{title}",
            arguments = listOf(navArgument("title") { type = NavType.StringType }),
        ) { entry ->
            val encoded = entry.arguments?.getString("title") ?: ""
            ComingSoonScreen(
                title = java.net.URLDecoder.decode(encoded, "UTF-8"),
            )
        }
        composable("search") {
            com.sanvya.app.ui.search.SearchScreen(
                onEditTransaction = { id -> navController.navigate("transactions/$id/edit") },
            )
        }
        composable("notifications") {
            com.sanvya.app.ui.notifications.NotificationsScreen(
                onOpenSettings = { navController.navigate("settings") },
            )
        }
        composable("help") { com.sanvya.app.ui.help.HelpScreen() }
        composable("reflect") { com.sanvya.app.ui.reflect.ReflectScreen() }
        // The assistant is the one NAV_GROUPS entry still unbuilt on both
        // platforms. A placeholder, not a crash -- see comingSoon() above.
        comingSoon("assistant", S.Translation::navAssistant)
        // The guest banner in the More sheet and the side nav both link here,
        // matching web's `<Link href="/login">`. LoginScreen is normally the
        // auth gate ABOVE this graph (MainActivity), so a guest -- who is
        // signed in -- could never reach it: the tap navigated to a route that
        // did not exist. Signing in from here upgrades the guest in place and
        // pops back to whatever they were looking at.
        composable("login") {
            // Two exits, because the four in-screen methods and Google leave by
            // different doors. OTP / password / set-password / guest call
            // `onSignedIn` directly; Google returns through the browser and
            // only flips the session, so without the second one a successful
            // Google upgrade would leave the user staring at the login form
            // they had just completed.
            val shellViewModel: com.sanvya.app.ui.shell.ShellViewModel = viewModel()
            val stillGuest by shellViewModel.isGuest.collectAsState()
            LaunchedEffect(stillGuest) { if (!stillGuest) navController.popBackStack() }
            com.sanvya.app.ui.auth.LoginScreen(onSignedIn = { navController.popBackStack() })
        }

        // `recurring` was a nav-catalog id with no screen behind it, so tapping
        // it landed on coming_soon/{title}. It has a real screen now.
        composable("recurring") {
            com.sanvya.app.ui.recurring.RecurringScreen(
                onOpenDirection = { slug -> navController.navigate("recurring/${slug.slug}") },
            )
        }
        // Create / edit. formDestination, so W2.1's rule applies for free: a
        // full page below 600dp, a dialog at 600dp and up.
        formDestination(
            "recurring/new/{direction}",
            windowClass,
            arguments = listOf(navArgument("direction") { type = NavType.StringType }),
        ) { entry ->
            com.sanvya.app.ui.recurring.RecurringFormScreen(
                slug = com.sanvya.app.ui.recurring.RecurringDirectionSlug
                    .from(entry.arguments?.getString("direction"))
                    ?: com.sanvya.app.ui.recurring.RecurringDirectionSlug.EXPENSE,
                onDone = { navController.popBackStack() },
            )
        }
        formDestination(
            "recurring/{direction}/{itemId}/edit",
            windowClass,
            arguments = listOf(
                navArgument("direction") { type = NavType.StringType },
                navArgument("itemId") { type = NavType.StringType },
            ),
        ) { entry ->
            com.sanvya.app.ui.recurring.RecurringFormScreen(
                slug = com.sanvya.app.ui.recurring.RecurringDirectionSlug
                    .from(entry.arguments?.getString("direction"))
                    ?: com.sanvya.app.ui.recurring.RecurringDirectionSlug.EXPENSE,
                editingId = entry.arguments?.getString("itemId"),
                onDone = { navController.popBackStack() },
            )
        }
        composable(
            "recurring/{direction}",
            arguments = listOf(navArgument("direction") { type = NavType.StringType }),
        ) { entry ->
            // An unknown slug is not an error page: web calls notFound(), which
            // this app has no equivalent of. Falling back to Expense keeps a
            // mistyped deep link on a real screen.
            val slug = com.sanvya.app.ui.recurring.RecurringDirectionSlug
                .from(entry.arguments?.getString("direction"))
                ?: com.sanvya.app.ui.recurring.RecurringDirectionSlug.EXPENSE
            com.sanvya.app.ui.recurring.RecurringDirectionScreen(
                slug = slug,
                onAdd = { navController.navigate("recurring/new/${slug.slug}") },
                onEdit = { id -> navController.navigate("recurring/${slug.slug}/$id/edit") },
            )
        }

        // Also had no screen and fell through to coming_soon.
        composable("statements") {
            com.sanvya.app.ui.statements.StatementsScreen()
        }

        composable("accounts") {
            AccountsScreen(
                onBack = { navController.popBackStack() },
                onNewAccount = { navController.navigate("accounts/new") },
                onEditAccount = { id -> navController.navigate("accounts/$id/edit") },
            )
        }
        formDestination("accounts/new", windowClass) {
            CreateAccountScreen(
                onBack = { navController.popBackStack() },
                onSaved = { navController.popBackStack() },
            )
        }
        formDestination(
            "accounts/{accountId}/edit",
            windowClass,
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
        formDestination("transactions/new", windowClass) {
            CreateTransactionScreen(
                onBack = { navController.popBackStack() },
                onSaved = { navController.popBackStack() },
                onAddAccountFirst = { navController.navigate("accounts/new") },
            )
        }
        formDestination(
            "transactions/{transactionId}/edit",
            windowClass,
            arguments = listOf(navArgument("transactionId") { type = NavType.StringType }),
        ) {
            EditTransactionScreen(
                onBack = { navController.popBackStack() },
                onSaved = { navController.popBackStack() },
                onDeleted = { navController.popBackStack("transactions", inclusive = true) },
            )
        }
        composable("budgets") {
            BudgetsScreen(
                onBack = { navController.popBackStack() },
                onAddBudget = { navController.navigate("budgets/new") },
                onEditBudget = { id -> navController.navigate("budgets/$id/edit") },
            )
        }
        formDestination("budgets/new", windowClass) {
            CreateBudgetScreen(
                onBack = { navController.popBackStack() },
                onSaved = { navController.popBackStack() },
            )
        }
        formDestination(
            "budgets/{budgetId}/edit",
            windowClass,
            arguments = listOf(navArgument("budgetId") { type = NavType.StringType }),
        ) { entry ->
            val budgetId = entry.arguments?.getString("budgetId") ?: ""
            EditBudgetScreen(
                budgetId = budgetId,
                onBack = { navController.popBackStack() },
                onSaved = { navController.popBackStack() },
                onDeleted = { navController.popBackStack("budgets", inclusive = true) },
            )
        }
        composable("goals") {
            GoalsScreen(
                onBack = { navController.popBackStack() },
                onAddGoal = { navController.navigate("goals/new") },
                onEditGoal = { id -> navController.navigate("goals/$id/edit") },
            )
        }
        formDestination("goals/new", windowClass) {
            CreateGoalScreen(
                onBack = { navController.popBackStack() },
                onSaved = { navController.popBackStack() },
            )
        }
        formDestination(
            "goals/{goalId}/edit",
            windowClass,
            arguments = listOf(navArgument("goalId") { type = NavType.StringType }),
        ) { entry ->
            val goalId = entry.arguments?.getString("goalId") ?: ""
            EditGoalScreen(
                goalId = goalId,
                onBack = { navController.popBackStack() },
                onSaved = { navController.popBackStack() },
                onDeleted = { navController.popBackStack("goals", inclusive = true) },
            )
        }
        composable("investments") {
            InvestmentsScreen(
                onBack = { navController.popBackStack() },
                onAddInvestment = { groupKey ->
                    navController.navigate(if (groupKey != null) "investments/new?groupKey=$groupKey" else "investments/new")
                },
                onNoInvestmentAccount = { navController.navigate("accounts/new") },
            )
        }
        composable(
            "investments/new?groupKey={groupKey}",
            arguments = listOf(navArgument("groupKey") { type = NavType.StringType; nullable = true; defaultValue = null }),
        ) { entry ->
            AddHoldingScreen(
                initialGroupKey = entry.arguments?.getString("groupKey"),
                onBack = { navController.popBackStack() },
                onSaved = { navController.popBackStack() },
            )
        }
        composable("loans") {
            LoansScreen(
                onBack = { navController.popBackStack() },
                onAddLoan = { navController.navigate("loans/new") },
                onOpenLoan = { id -> navController.navigate("loans/$id") },
            )
        }
        formDestination("loans/new", windowClass) {
            AddLoanScreen(
                onBack = { navController.popBackStack() },
                onSaved = { navController.popBackStack() },
            )
        }
        composable(
            "loans/{loanId}",
            arguments = listOf(navArgument("loanId") { type = NavType.StringType }),
        ) { entry ->
            val loanId = entry.arguments?.getString("loanId") ?: ""
            LoanDetailScreen(
                loanId = loanId,
                onBack = { navController.popBackStack() },
                onDeleted = { navController.popBackStack("loans", inclusive = true) },
            )
        }
        composable("insights") {
            InsightsScreen(
                onNavigate = { route -> navController.navigate(route) },
                onUpgrade = { navController.navigate("settings") },
            )
        }
        composable("cards") {
            CreditCardsScreen(
                onBack = { navController.popBackStack() },
                onAddAccount = { navController.navigate("accounts/new") },
            )
        }
        composable("splits") {
            SplitsScreen(
                onOpenGroup = { id -> navController.navigate("splits/$id") },
            )
        }
        composable(
            "splits/{groupId}",
            arguments = listOf(navArgument("groupId") { type = NavType.StringType }),
        ) { entry ->
            val groupId = entry.arguments?.getString("groupId") ?: ""
            GroupDetailScreen(
                groupId = groupId,
                onBack = { navController.popBackStack() },
            )
        }
    }
    }
}
