package com.sanvya.app.ui.recurring

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
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
import com.sanvya.app.ui.colorForId
import com.sanvya.app.ui.components.Eyebrow
import com.sanvya.app.ui.components.SanvyaButton
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaPage
import com.sanvya.app.ui.components.SanvyaText

/**
 * One side of the recurring picture: Income or Expense.
 *
 * Ported from `apps/web/app/recurring/[direction]/page.tsx`. This is what made
 * the direction rows on the Recurring screen tappable — until now they were
 * deliberately inert because there was nowhere for them to go.
 *
 * **Absent, and recorded in ABSENT-BY-DECISION.md:**
 * - **The category donut.** Both platforms already have a `DonutChart`, but each
 *   is `private` inside its Insights screen; sharing one is a refactor of two
 *   working screens, not part of this port. The chips below carry the names and
 *   the percentages — the information — and web's own comment calls a
 *   single-slice donut "decoration, not information".
 * - ~~Add and Edit~~ — **built 2026-08-24** (`RecurringFormScreen`).
 */
@Composable
fun RecurringDirectionScreen(
    slug: RecurringDirectionSlug,
    onAdd: () -> Unit = {},
    onEdit: (String) -> Unit = {},
    viewModel: RecurringDirectionViewModel = viewModel(),
) {
    val colors = LocalSanvyaColors.current
    LaunchedEffect(slug) { viewModel.setDirection(slug) }
    val state by viewModel.uiState.collectAsState()

    val isIncome = slug == RecurringDirectionSlug.INCOME
    val tint = if (isIncome) colors.positive else colors.negative
    val sign = if (isIncome) "+" else "−"

    var confirmingRemoval by rememberSaveable { mutableStateOf<String?>(null) }
    val confirmingName = remember(confirmingRemoval, state.items) {
        state.items.firstOrNull { it.id == confirmingRemoval }?.name ?: ""
    }

    SanvyaPage(
        title = if (isIncome) S.Recurring.incomes(sRes()) else S.Recurring.payments(sRes()),
        modifier = Modifier.verticalScroll(rememberScrollState()),
        action = {
            SanvyaButton(onClick = onAdd) {
                SanvyaText(S.Recurring.add(sRes()), style = SanvyaType.button)
            }
        },
    ) {
        SanvyaCard(padding = PaddingValues(18.dp)) {
            Eyebrow(S.Recurring.perMonthLabel(sRes()))
            SanvyaText(
                sign + state.monthlyFormatted,
                style = SanvyaType.statValue,
                color = tint,
                modifier = Modifier.padding(top = 2.dp),
            )

            // Web only draws the mix once there is more than one slice; a single
            // full-width bar restating the total above it is noise.
            if (state.categories.size > 1) {
                Spacer(Modifier.height(14.dp))
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    state.categories.forEach { slice ->
                        Row(
                            modifier = Modifier
                                .clip(SanvyaShape.pill)
                                .background(colors.surface2)
                                .padding(horizontal = 10.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Spacer(
                                Modifier
                                    .size(9.dp)
                                    .clip(SanvyaShape.pill)
                                    .background(colorForId(slice.id)),
                            )
                            Spacer(Modifier.width(6.dp))
                            SanvyaText(
                                if (slice.isUncategorised) S.Cashflow.noCategory(sRes()) else slice.name,
                                style = SanvyaType.chip,
                            )
                            Spacer(Modifier.width(6.dp))
                            SanvyaText(
                                "${slice.sharePct}%",
                                style = SanvyaType.chip,
                                color = colors.text2,
                            )
                        }
                    }
                }
            }
        }

        if (state.items.isEmpty()) {
            SanvyaText(
                if (isIncome) S.Recurring.emptyIncome(sRes()) else S.Recurring.emptyPayment(sRes()),
                style = SanvyaType.body,
                color = colors.text2,
            )
        } else {
            state.items.forEach { item ->
                SanvyaCard(padding = PaddingValues(horizontal = 14.dp, vertical = 12.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            SanvyaText(item.name, style = SanvyaType.body, maxLines = 1)
                            SanvyaText(
                                item.subtitle,
                                style = SanvyaType.statLabel,
                                color = colors.text2,
                                maxLines = 1,
                            )
                        }
                        SanvyaText(sign + item.amountFormatted, style = SanvyaType.body, color = tint)
                    }
                    Spacer(Modifier.height(8.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        // Three plain buttons rather than web's kebab menu:
                        // hiding three actions behind a third tap is worse than
                        // showing them on a card that has room.
                        SanvyaButton(onClick = { onEdit(item.id) }, ghost = true) {
                            SanvyaText(S.Recurring.edit(sRes()), style = SanvyaType.button)
                        }
                        SanvyaButton(onClick = { viewModel.recordNow(item.id) }, ghost = true) {
                            SanvyaText(S.Recurring.postNow(sRes()), style = SanvyaType.button)
                        }
                        SanvyaButton(onClick = { confirmingRemoval = item.id }, ghost = true) {
                            SanvyaText(S.Recurring.remove(sRes()), style = SanvyaType.button)
                        }
                    }
                }
            }
        }
    }

    // Removal is confirmed, matching web. A Material3 AlertDialog, which is
    // what EditGoalScreen/LoanDetailScreen already use for the same job -- no
    // new ConfirmDialog component invented for one call site.
    //
    // It is a soft delete and therefore recoverable in the database, but not by
    // the user from this screen, which is why it asks first.
    if (confirmingRemoval != null) {
        AlertDialog(
            onDismissRequest = { confirmingRemoval = null },
            title = { Text(S.Recurring.removeTitle(sRes())) },
            text = { Text(S.Recurring.removeMsg(sRes(), confirmingName)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmingRemoval?.let(viewModel::remove)
                    confirmingRemoval = null
                }) { Text(S.Recurring.remove(sRes()), color = colors.negative) }
            },
            dismissButton = {
                TextButton(onClick = { confirmingRemoval = null }) {
                    Text(S.Recurring.cancel(sRes()))
                }
            },
        )
    }
}
