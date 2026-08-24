package com.sanvya.app.ui.recurring

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
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
import com.sanvya.app.ui.components.Eyebrow
import com.sanvya.app.ui.components.SanvyaButton
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaPage
import com.sanvya.app.ui.components.SanvyaText
import com.sanvya.app.ui.formatMoney
import com.sanvya.app.ui.baseCurrencyNow
import kotlin.math.absoluteValue

/**
 * Web paints the two halves with
 * `color-mix(in srgb, var(--negative) 18%, transparent)`. There is no
 * positive/negative "soft" design token, so the 18% is applied here as alpha —
 * the same number, arrived at the same way. If a soft token is ever generated,
 * this should use it instead.
 */
private const val BAR_TINT_ALPHA = 0.18f

/**
 * Recurring payments & income — ported from apps/web/app/recurring/page.tsx.
 *
 * **This route used to fall through to `coming_soon/{title}`** — `recurring` was
 * a nav-catalog id on both platforms with no screen behind it on either.
 *
 * Everything here is a MONTHLY equivalent so a weekly bill and a yearly
 * subscription are comparable; the normalising happens in the view model via the
 * vector-tested `monthlyEquivalent`.
 *
 * Scope, matching web minus what is genuinely elsewhere:
 * - **Net monthly cashflow**, the two sides drawn to scale, and a card per
 *   direction — all present.
 * - **"Due now"**, with Skip and Record wired to the real engine.
 * - **Savings/SIPs are excluded**, exactly as on web: a SIP is a transfer
 *   between your own accounts, so counting it as an outflow would understate
 *   what you have spare. They still post and still appear under "Due now".
 * - **Create/edit is not here yet.** Web opens `RecurringModal`; the native
 *   equivalent belongs to W2.1 (full page below 600dp, dialog above), and a
 *   button that opened nothing would be the dead control this audit keeps
 *   finding. The direction cards are likewise not yet tappable — `/recurring/
 *   [direction]` is a separate screen and does not exist on native.
 */
@Composable
fun RecurringScreen(
    viewModel: RecurringViewModel = viewModel(),
) {
    val colors = LocalSanvyaColors.current
    val state by viewModel.uiState.collectAsState()
    val base = baseCurrencyNow()

    SanvyaPage(
        title = S.Recurring.title(sRes()),
        modifier = Modifier.verticalScroll(rememberScrollState()),
    ) {
        SanvyaCard(padding = androidx.compose.foundation.layout.PaddingValues(18.dp)) {
            Eyebrow(S.Recurring.netMonthly(sRes()))
            SanvyaText(
                // The sign is rendered, not baked into the number: a minus glyph
                // (U+2212) rather than a hyphen, matching web, because a hyphen
                // in a tabular figure reads as a dash between two numbers.
                (if (state.netMonthlyMinor >= 0) "+" else "−") +
                    formatMoney(state.netMonthlyMinor.absoluteValue, base),
                style = SanvyaType.statValue,
                color = if (state.netMonthlyMinor >= 0) colors.positive else colors.negative,
                modifier = Modifier.padding(top = 2.dp),
            )

            Spacer(Modifier.height(14.dp))
            CashflowBar(
                expense = state.expenseMonthlyMinor,
                income = state.incomeMonthlyMinor,
                base = base,
            )

            Spacer(Modifier.height(10.dp))
            DirectionRow(
                label = S.Recurring.incomes(sRes()),
                amountFormatted = formatMoney(state.incomeMonthlyMinor, base),
                sign = "+",
                color = colors.positive,
                count = state.incomeCount,
                emptyText = S.Recurring.emptyIncome(sRes()),
            )
            Spacer(Modifier.height(10.dp))
            DirectionRow(
                label = S.Recurring.payments(sRes()),
                amountFormatted = formatMoney(state.expenseMonthlyMinor, base),
                sign = "−",
                color = colors.negative,
                count = state.expenseCount,
                emptyText = S.Recurring.emptyPayment(sRes()),
            )
        }

        if (state.due.isNotEmpty()) {
            SanvyaCard {
                SanvyaText(S.Recurring.dueNow(sRes()), style = SanvyaType.sectionTitle)
                state.due.forEach { item ->
                    Spacer(Modifier.height(10.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            SanvyaText(item.name, style = SanvyaType.body)
                            SanvyaText(
                                buildString {
                                    append(S.Recurring.dueOn(sRes(), item.nextDue))
                                    item.amountFormatted?.let { append(" · ").append(it) }
                                },
                                style = SanvyaType.statLabel,
                                color = colors.text2,
                            )
                        }
                        SanvyaButton(onClick = { viewModel.skip(item.id) }, ghost = true) {
                            SanvyaText(S.Recurring.skip(sRes()), style = SanvyaType.button)
                        }
                        Spacer(Modifier.width(8.dp))
                        SanvyaButton(onClick = { viewModel.record(item.id) }) {
                            SanvyaText(S.Recurring.record(sRes()), style = SanvyaType.button)
                        }
                    }
                }
            }
        }
    }
}

/**
 * Income vs expense drawn to scale against each other.
 *
 * Widths are shares of the COMBINED total, matching web: the point is the ratio
 * between the two bars, not either against some fixed maximum. Renders nothing
 * at all when both are zero — a bar with no data is decoration.
 */
@Composable
private fun CashflowBar(expense: Long, income: Long, base: String) {
    val colors = LocalSanvyaColors.current
    val total = expense + income
    if (total <= 0L) return
    val expenseWeight = expense.toFloat() / total.toFloat()

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(34.dp)
            .clip(SanvyaShape.row)
            .border(1.dp, colors.border, SanvyaShape.row),
    ) {
        if (expense > 0L) {
            Row(
                modifier = Modifier
                    .weight(expenseWeight)
                    .fillMaxWidth()
                    .background(colors.negative.copy(alpha = BAR_TINT_ALPHA)),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SanvyaText(
                    "−" + formatMoney(expense, base),
                    style = SanvyaType.chip,
                    color = colors.negative,
                    maxLines = 1,
                )
            }
        }
        if (income > 0L) {
            Row(
                modifier = Modifier
                    .weight(1f - expenseWeight)
                    .fillMaxWidth()
                    .background(colors.positive.copy(alpha = BAR_TINT_ALPHA)),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SanvyaText(
                    formatMoney(income, base),
                    style = SanvyaType.chip,
                    color = colors.positive,
                    maxLines = 1,
                )
            }
        }
    }
}

@Composable
private fun DirectionRow(
    label: String,
    amountFormatted: String,
    sign: String,
    color: androidx.compose.ui.graphics.Color,
    count: Int,
    emptyText: String,
) {
    val colors = LocalSanvyaColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(SanvyaShape.radiusSm)
            .background(colors.surface2)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            SanvyaText(label, style = SanvyaType.sectionTitle)
            SanvyaText(
                if (count == 0) {
                    emptyText
                } else {
                    S.Recurring.itemCount(sRes(), count) + " · " + S.Recurring.perMonthLabel(sRes())
                },
                style = SanvyaType.statLabel,
                color = colors.text2,
            )
        }
        SanvyaText(sign + amountFormatted, style = SanvyaType.statValue, color = color)
    }
}
