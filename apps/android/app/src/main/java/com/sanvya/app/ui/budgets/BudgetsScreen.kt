package com.sanvya.app.ui.budgets

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaRadius
import com.sanvya.app.ui.components.SanvyaPage

/**
 * Ported from apps/web/app/budgets/page.tsx's list + docs/mobile/
 * screen-specs/budgets.md. Was completely unbuilt before this pass
 * (2026-08-06, task #24) -- BudgetsViewModel existed but no Screen
 * consumed it and no nav route reached it (drawer routed to a
 * "coming_soon/Budgets" placeholder).
 *
 * Web's edit affordance is an in-place expand within the same card, not a
 * separate screen -- this uses separate Create/EditBudgetScreen routes
 * instead, matching this app's own established Accounts/Transactions
 * pattern (translate the logic, not the exact widget shape).
 *
 * 2026-08-29: the two things a card could not do arrived together. Tapping
 * the spent figure opens the drill-down that produced it
 * (`SpentBreakdownDialog`), and the cumulative spend-vs-limit curve
 * (`BudgetSpendChart`) sits under the card the way it does on web. The
 * strings the ViewModel used to compose in English -- "Spent x", "Over by
 * x", "All spending", "Monthly" -- are composed here instead, because this
 * is the layer that has a `Resources`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BudgetsScreen(
    onBack: () -> Unit = {},
    onAddBudget: () -> Unit = {},
    onEditBudget: (String) -> Unit = {},
    onOpenTransaction: (String) -> Unit = {},
    viewModel: BudgetsViewModel = viewModel(),
) {
    val budgets by viewModel.budgets.collectAsState()
    val breakdown by viewModel.breakdown.collectAsState()
    val colors = LocalSanvyaColors.current

    SanvyaPage(
        title = S.Budgets.title(sRes()),
        action = {
            IconButton(onClick = onAddBudget) {
                Icon(Icons.Default.Add, contentDescription = S.Budgets.newBudget(sRes()), tint = colors.accent)
            }
        },
    ) {
        if (budgets.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("◔", fontSize = 26.sp)
                    Text(S.Budgets.noBudgetsTitle(sRes()), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.text)
                    Text(
                        S.Budgets.noBudgetsBody(sRes()),
                        fontSize = 14.sp,
                        color = colors.text2,
                        textAlign = TextAlign.Center,
                    )
                    Button(onClick = onAddBudget, modifier = Modifier.padding(top = 4.dp)) {
                        Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(S.Budgets.createFirst(sRes()))
                    }
                }
            }
        } else {
            Column(
                modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                budgets.forEach { budget ->
                    BudgetRowCard(
                        budget = budget,
                        onClick = { onEditBudget(budget.id) },
                        onShowSpent = { viewModel.openBreakdown(budget.id) },
                    )
                }
            }
        }
    }

    breakdown?.let { state ->
        SpentBreakdownDialog(
            state = state,
            onDismiss = { viewModel.closeBreakdown() },
            onOpenTransaction = { id ->
                // Close first, then navigate -- web's row is a `<Link>` with an
                // `onClick={onClose}` for the same reason: coming back from the
                // transaction to a dialog nobody asked to reopen is worse than
                // coming back to the list.
                viewModel.closeBreakdown()
                onOpenTransaction(id)
            },
        )
    }
}

@Composable
private fun BudgetRowCard(budget: BudgetUiModel, onClick: () -> Unit, onShowSpent: () -> Unit) {
    val colors = LocalSanvyaColors.current
    val tint = when (budget.progressColor) {
        ProgressColor.POSITIVE -> colors.positive
        ProgressColor.WARNING -> colors.warning
        ProgressColor.NEGATIVE -> colors.negative
    }
    // Web falls back to the scope when a budget has no name, and to "All
    // spending" when it has neither.
    val title = budget.title.ifBlank { S.Budgets.allSpending(sRes()) }
    val period = when (budget.period) {
        "daily" -> S.Budgets.periodDaily(sRes())
        "weekly" -> S.Budgets.periodWeekly(sRes())
        "yearly" -> S.Budgets.periodYearly(sRes())
        else -> S.Budgets.periodMonthly(sRes())
    }
    // A custom-dated budget has no period word -- the dates ARE the timeframe.
    val timeframe = if (budget.isCustomDated) budget.winLabel else "$period · ${budget.winLabel}"
    // Web appends the scope only when the budget also has a name of its own,
    // since otherwise the scope is already the title.
    val subtitle = if (budget.title.isNotBlank() && budget.scopeLabel.isNotBlank() && budget.title != budget.scopeLabel) {
        "$timeframe · ${budget.scopeLabel}"
    } else {
        timeframe
    }

    Card(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
        colors = CardDefaults.cardColors(containerColor = colors.surface),
        shape = RoundedCornerShape(SanvyaRadius.radiusLg),
    ) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Column(Modifier.weight(1f, fill = false)) {
                    Text(title, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = colors.text)
                    Text(subtitle, fontSize = 12.sp, color = colors.text2)
                }
                // An em dash, not "Infinity%": a limit of zero has no ratio to
                // report. Web prints the same character.
                Text(budget.pctRounded?.let { "$it%" } ?: "—", fontSize = 12.sp, color = colors.text2)
            }
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(6.dp)
                    .clip(RoundedCornerShape(50))
                    .background(colors.border),
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth(fraction = budget.progress.coerceIn(0.0, 1.0).toFloat())
                        .fillMaxHeight()
                        .clip(RoundedCornerShape(50))
                        .background(tint),
                )
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                // The spent figure is the drill-down: tapping the number you
                // are questioning is where people look for the answer. Web
                // underlines it with a dotted rule to say so; this is the same
                // affordance, and the inner clickable wins over the card's own.
                Text(
                    S.Budgets.spent(sRes(), budget.spentAmountFormatted),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = colors.text,
                    textDecoration = TextDecoration.Underline,
                    // `onClickLabel` is TalkBack's version of web's
                    // aria-label on the same control.
                    modifier = Modifier.clickable(
                        onClickLabel = S.Budgets.viewSpentAria(sRes()),
                        onClick = onShowSpent,
                    ),
                )
                Text(
                    if (budget.overLimit) {
                        S.Budgets.over(sRes(), budget.remainderAmountFormatted)
                    } else {
                        S.Budgets.left(sRes(), budget.remainderAmountFormatted)
                    },
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = tint,
                )
            }
            BudgetSpendChart(
                series = budget.spendSeries,
                limitMinor = budget.limitMinor,
                currency = budget.currency,
                tint = tint,
            )
        }
    }
}
