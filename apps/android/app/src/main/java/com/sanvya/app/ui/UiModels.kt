package com.sanvya.app.ui

import androidx.compose.ui.graphics.Color

/**
 * Row models for the pre-existing Budgets/CreditCards/Goals/Insights/
 * Investments/Loans ViewModels (`ui/{budgets,creditcards,goals,insights,
 * investments,loans}/*ViewModel.kt`).
 *
 * These types didn't exist anywhere in the tree -- the ViewModels imported
 * `com.sanvya.app.ui.<Name>UiModel` and constructed it, but no file defined
 * it, which is why `:app:compileDebugKotlin` failed with "Unresolved
 * reference" the first time this module got a real full build (2026-08-05).
 * None of these 6 ViewModels has a consuming Screen.kt or a SanvyaNavHost
 * route either, and all 6 use constructor injection (no Koin viewModel-DSL
 * module registers them) -- unlike this session's real screens (Dashboard/
 * Accounts/Transactions), these are unreachable dead code that happened to
 * still be compiled as part of the module, matching the exact "reported
 * DONE, actually never real" pattern AUDIT_HISTORY.md's Android Phase 3
 * audit found for other screens on 2026-08-01ish dates.
 *
 * This file is the MINIMAL fix to unblock the build: field shapes below
 * are reverse-engineered from each ViewModel's own construction call,
 * nothing more. It is explicitly NOT a source-verified port (no
 * docs/mobile/screen-specs/<name>.md exists for any of these 6 screens) --
 * treat Budgets/CreditCards/Goals/Insights/Investments/Loans as still fully
 * TODO for real UI work, tracked in docs/mobile/TODO.md.
 */

data class BudgetUiModel(
    val id: String,
    val name: String,
    val period: String,
    val spentFormatted: String,
    val limitFormatted: String,
    val progress: Float,
    val categories: List<String>,
)

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

data class GoalUiModel(
    val id: String,
    val name: String,
    val currentFormatted: String,
    val targetFormatted: String,
    val targetDate: String,
    val progress: Float,
)

data class InsightUiModel(
    val id: String,
    val title: String,
    val description: String,
    val highlightAmount: String?,
    val isPositive: Boolean,
)

data class HoldingUiModel(
    val id: String,
    val name: String,
    val symbolExchange: String,
    val assetClass: String,
    val quantity: String,
    val currentValueFormatted: String,
    val returnFormatted: String,
    val isPositiveReturn: Boolean,
)

data class LoanUiModel(
    val id: String,
    val name: String,
    val totalAmount: String,
    val emiAmount: String,
    val remainingEmis: Int,
    val totalEmis: Int,
    val status: String,
    val nextDueDate: String,
)
