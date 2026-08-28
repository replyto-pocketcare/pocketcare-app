package com.sanvya.app.ui.statements

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaShape
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.DateField
import com.sanvya.app.ui.components.SanvyaButton
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaPage
import com.sanvya.app.ui.components.SanvyaText

/**
 * Statements — ported from apps/web/app/statements/page.tsx.
 *
 * A date-ranged view of real transactions with an income/expense summary,
 * behind the paid gate. **Not** a list of statement documents: iOS shipped that
 * invention under this name and it is being deleted in the same change.
 *
 * Deliberately absent, because web's versions do not translate:
 * - **Print.** `window.print()` has no phone equivalent; a share/PDF export is
 *   a real feature to design, not a button to add.
 *
 * **Analyze** is no longer in that list: `/statements/analyze` landed
 * 2026-08-27 and the link below reaches it, as web's does.
 */
@Composable
fun StatementsScreen(
    viewModel: StatementsViewModel = viewModel(),
    onAnalyze: () -> Unit = {},
) {
    val colors = LocalSanvyaColors.current
    val state by viewModel.uiState.collectAsState()

    SanvyaPage(
        title = S.Statements.title(sRes()),
        modifier = Modifier.verticalScroll(rememberScrollState()),
    ) {
        // Nothing at all until the entitlement is known — see the note on
        // StatementsUiState.entitlementKnown for why this is not just caution.
        if (!state.entitlementKnown) return@SanvyaPage

        if (!state.isPaid) {
            SanvyaCard(padding = PaddingValues(28.dp)) {
                SanvyaText(
                    S.Statements.premiumTitle(sRes()),
                    style = SanvyaType.h2,
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(8.dp))
                SanvyaText(
                    S.Statements.premiumBody(sRes()),
                    style = SanvyaType.body,
                    color = colors.text2,
                    modifier = Modifier.fillMaxWidth(),
                )
                // No "Go Premium" button: web links to /settings, and wiring a
                // button here before the native upgrade flow exists would be a
                // control that goes nowhere.
            }
            return@SanvyaPage
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            DateField(
                label = S.Statements.fromDate(sRes()),
                value = state.start,
                onValueChange = viewModel::setStart,
                modifier = Modifier.weight(1f),
            )
            DateField(
                label = S.Statements.toDate(sRes()),
                value = state.end,
                onValueChange = viewModel::setEnd,
                modifier = Modifier.weight(1f),
            )
        }

        Spacer(Modifier.height(12.dp))
        // Web puts this link at the top of the same screen. It is a different
        // job -- read someone ELSE's statement -- so it is a link, not a tab.
        SanvyaButton(onClick = onAnalyze, modifier = Modifier.fillMaxWidth(), ghost = true) {
            SanvyaText(S.Statements.analyze(sRes()), style = SanvyaType.button, modifier = Modifier.weight(1f))
        }

        SanvyaCard(padding = PaddingValues(20.dp)) {
            SanvyaText(S.Statements.statementName(sRes()), style = SanvyaType.sectionTitle)
            Spacer(Modifier.height(14.dp))
            SummaryRow(S.Statements.income(sRes()), state.incomeFormatted, colors.positive)
            Spacer(Modifier.height(8.dp))
            SummaryRow(S.Statements.expenses(sRes()), state.expenseFormatted, colors.negative)
            Spacer(Modifier.height(8.dp))
            SummaryRow(
                S.Statements.netForPeriod(sRes()),
                (if (state.netIsPositive) "+" else "−") + state.netFormatted,
                if (state.netIsPositive) colors.positive else colors.negative,
            )
        }

        SanvyaCard {
            SanvyaText(S.Statements.transactions(sRes()), style = SanvyaType.sectionTitle)
            if (state.transactions.isEmpty()) {
                Spacer(Modifier.height(10.dp))
                SanvyaText(
                    S.Statements.noTransactions(sRes()),
                    style = SanvyaType.statLabel,
                    color = colors.text2,
                )
            } else {
                state.transactions.forEach { tx ->
                    Spacer(Modifier.height(10.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            SanvyaText(tx.title, style = SanvyaType.body, maxLines = 1)
                            SanvyaText(
                                tx.occurredOn,
                                style = SanvyaType.statLabel,
                                color = colors.text2,
                            )
                        }
                        SanvyaText(
                            (if (tx.isIncome) "+" else "−") + tx.amountFormatted,
                            style = SanvyaType.body,
                            color = if (tx.isIncome) colors.positive else colors.negative,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SummaryRow(label: String, amount: String, color: androidx.compose.ui.graphics.Color) {
    val colors = LocalSanvyaColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(SanvyaShape.radiusSm)
            .background(colors.surface2)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SanvyaText(label, style = SanvyaType.statLabel, color = colors.text2, modifier = Modifier.weight(1f))
        SanvyaText(amount, style = SanvyaType.body, color = color)
    }
}
