package com.sanvya.app.ui

import androidx.compose.ui.graphics.Color

/**
 * Row models for the pre-existing CreditCards/Insights ViewModels (the
 * "XViewModel.kt" file in each of ui/creditcards, ui/insights).
 *
 * These types didn't exist anywhere in the tree -- the ViewModels imported
 * `com.sanvya.app.ui.<Name>UiModel` and constructed it, but no file defined
 * it, which is why `:app:compileDebugKotlin` failed with "Unresolved
 * reference" the first time this module got a real full build (2026-08-05).
 * Neither of these ViewModels has a consuming Screen.kt or a SanvyaNavHost
 * route either, and both use constructor injection (no Koin viewModel-DSL
 * module registers them) -- unlike this session's real screens (Dashboard/
 * Accounts/Transactions/Budgets), these are unreachable dead code that
 * happened to still be compiled as part of the module, matching the exact
 * "reported DONE, actually never real" pattern AUDIT_HISTORY.md's Android
 * Phase 3 audit found for other screens on 2026-08-01ish dates.
 *
 * This file is the MINIMAL fix to unblock the build: field shapes below
 * are reverse-engineered from each ViewModel's own construction call,
 * nothing more. It is explicitly NOT a source-verified port (no
 * docs/mobile/screen-specs/<name>.md exists for either of these screens) --
 * treat CreditCards/Insights as still fully TODO for real UI work, tracked
 * in docs/mobile/TODO.md.
 *
 * BudgetUiModel/GoalUiModel/HoldingUiModel/LoanUiModel used to live here
 * too -- each moved into its own real ViewModel file once it got its real
 * create/update/delete port (ui/budgets/BudgetsViewModel.kt 2026-08-06,
 * ui/goals/GoalsViewModel.kt 2026-08-06, ui/investments/
 * InvestmentsViewModel.kt 2026-08-06 task #26, ui/loans/LoansViewModel.kt
 * 2026-08-06 task #27), replacing these placeholder shapes entirely.
 * GoalUiModel's old `targetDate` field read a real-but-unused DB column --
 * confirmed nowhere in the real Goals UI, see that screen's spec.
 */

data class CreditCardUiModel(
    val id: String,
    val cardName: String,
    val bankNetwork: String,
    val last4: String,
    val outstandingFormatted: String,
    val availableLimitFormatted: String,
    val dueDate: String,
    val gradientColors: List<Color>,
)

data class InsightUiModel(
    val id: String,
    val title: String,
    val description: String,
    val highlightAmount: String?,
    val isPositive: Boolean,
)
