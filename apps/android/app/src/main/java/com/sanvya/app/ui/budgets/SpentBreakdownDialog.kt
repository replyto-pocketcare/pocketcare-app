package com.sanvya.app.ui.budgets

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.ui.components.SanvyaModal
import com.sanvya.app.ui.components.Spinner

/**
 * The expenses behind a budget's "spent" figure -- web's
 * apps/web/src/budgets/SpentBreakdown.tsx.
 *
 * The rows come from `BudgetRepository.transactionsThisPeriod`, which shares
 * its scope clause with `spentThisPeriod` -- so this list is the same query
 * that produced the number, not a second interpretation of "what counts". A
 * drill-down that disagrees with the figure above it is worse than none,
 * because it makes the user distrust the budget rather than the screen.
 *
 * Web caps the list at `52vh` and scrolls it inside the dialog. Here the DIALOG
 * scrolls (`SanvyaModal` wraps its card in a scrolling scrim), so an inner
 * scroller would be a nested one -- two scroll containers in the same axis,
 * which Compose resolves by giving the gesture to the inner one and stranding
 * the total row below it.
 */
@Composable
fun SpentBreakdownDialog(
    state: SpentBreakdownState,
    onDismiss: () -> Unit,
    onOpenTransaction: (String) -> Unit,
) {
    val colors = LocalSanvyaColors.current
    val rows = state.rows

    SanvyaModal(
        open = true,
        onClose = onDismiss,
        label = S.Budgets.breakdownTitleAria(sRes(), state.title),
    ) {
        Text(state.title, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = colors.text)
        Text(
            // Loading and "nothing here" are DIFFERENT states, and web draws
            // them differently for a reason: a budget with no spend yet and a
            // budget still reading look identical if both are an empty list.
            if (rows == null) {
                S.Budgets.breakdownLoading(sRes())
            } else {
                S.Budgets.breakdownSummary(sRes(), state.count, state.spentAmountFormatted)
            },
            fontSize = 13.sp,
            color = colors.text2,
            modifier = Modifier.padding(top = 2.dp, bottom = 12.dp),
        )

        if (rows == null) {
            Box(Modifier.fillMaxWidth().height(96.dp), contentAlignment = Alignment.Center) {
                Spinner(size = 26.dp)
            }
        } else if (rows.isEmpty()) {
            Text(S.Budgets.breakdownEmpty(sRes()), fontSize = 13.sp, color = colors.text2)
        } else {
            rows.forEach { row -> BreakdownRow(row, onOpenTransaction) }
            Row(
                modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(S.Budgets.breakdownTotal(sRes()), fontSize = 13.sp, fontWeight = FontWeight.Bold, color = colors.text)
                Text(state.listedTotalFormatted, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = colors.text)
            }
            if (state.mismatch) {
                Text(
                    S.Budgets.breakdownMismatch(sRes(), state.spentAmountFormatted),
                    fontSize = 11.sp,
                    color = colors.text2,
                    modifier = Modifier.padding(top = 8.dp),
                )
            }
        }
    }
}

@Composable
private fun BreakdownRow(row: BudgetTxnUiModel, onOpenTransaction: (String) -> Unit) {
    val colors = LocalSanvyaColors.current
    // Web's own fallback chain, in order: what the user typed, then the note,
    // then the category, then a translated "Expense".
    val title = row.description?.takeIf { it.isNotBlank() }
        ?: row.note?.takeIf { it.isNotBlank() }
        ?: row.categoryName?.takeIf { it.isNotBlank() }
        ?: S.Budgets.breakdownFallback(sRes())
    val subtitle = listOfNotNull(
        row.dateLabel,
        row.categoryName?.takeIf { it.isNotBlank() },
        row.accountName?.takeIf { it.isNotBlank() },
    ).joinToString(" · ")

    Column(
        Modifier
            .fillMaxWidth()
            .clickable { onOpenTransaction(row.id) }
            .padding(vertical = 10.dp),
    ) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(
                title,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = colors.text,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false),
            )
            Text(row.amountFormatted, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = colors.text)
        }
        Text(subtitle, fontSize = 12.sp, color = colors.text2)
    }
    Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
}
