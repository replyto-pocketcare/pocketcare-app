package com.sanvya.app.ui.statements

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaShape
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.DateField
import com.sanvya.app.ui.components.Eyebrow
import com.sanvya.app.ui.components.SanvyaButton
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaPage
import com.sanvya.app.ui.components.SanvyaText
import com.sanvya.app.ui.isoLabel
import com.sanvya.app.ui.shortDateLabel
import com.sanvya.app.ui.transactions.TransactionRowCard

/**
 * Statements — ported from apps/web/app/statements/page.tsx.
 *
 * A date-ranged view of real transactions with an income/expense summary,
 * behind the paid gate. **Not** a list of statement documents: iOS shipped that
 * invention under this name and it is being deleted in the same change.
 *
 * The rows are grouped per day under a header carrying that day's net, they are
 * tappable through to the transaction's edit screen, and they carry the
 * category and label tags — all three are web's, and all three were missing
 * here until 2026-08-28.
 *
 * **Print** stays absent: `window.print()` has no phone equivalent. What
 * replaced it is **Share**, which is the same intent — get this statement out
 * of the app — expressed as the control Android actually has. It shares the
 * rendered statement as text through `ACTION_SEND`, deliberately not as a file:
 * a file attachment needs a `FileProvider` registered in the manifest, which is
 * a shared file this screen has no business editing, and plain text is what the
 * Diagnostics share on Settings already does.
 */
@Composable
fun StatementsScreen(
    viewModel: StatementsViewModel = viewModel(),
    onAnalyze: () -> Unit = {},
    onEditTransaction: (String) -> Unit = {},
) {
    val colors = LocalSanvyaColors.current
    val state by viewModel.uiState.collectAsState()
    val context = LocalContext.current

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
        // Web puts both of these at the top of the same screen, side by side.
        // Analyze is a different job -- read someone ELSE's statement -- so it
        // is a link, not a tab; Share stands where web's Print does.
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SanvyaButton(onClick = onAnalyze, modifier = Modifier.weight(1f), ghost = true) {
                SanvyaText(S.Statements.analyze(sRes()), style = SanvyaType.button)
            }
            // Every string the click handler needs is read HERE, not inside it:
            // `sRes()` is @Composable and an onClick lambda is not a composable
            // scope, so resolving them lazily would not compile.
            val shareLabel = S.Statements.share(sRes())
            val shareSubject = S.Statements.statementName(sRes())
            val shareText = statementShareText(state)
            SanvyaButton(
                onClick = {
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_SUBJECT, shareSubject)
                        putExtra(Intent.EXTRA_TEXT, shareText)
                    }
                    context.startActivity(Intent.createChooser(intent, shareLabel))
                },
                modifier = Modifier.weight(1f),
                // Nothing to share before the first row arrives, and an empty
                // share sheet is worse than a disabled button.
                enabled = state.days.isNotEmpty(),
            ) {
                SanvyaText(shareLabel, style = SanvyaType.button)
            }
        }

        SanvyaCard(padding = PaddingValues(20.dp)) {
            SanvyaText(S.Statements.statementName(sRes()), style = SanvyaType.sectionTitle)
            SanvyaText(
                // Web's subtitle under the statement name. It is also the line
                // that makes the SHARED text self-describing — a statement with
                // no period on it is just a list of numbers.
                "${shortDateLabel(state.start)} – ${shortDateLabel(state.end)}",
                style = SanvyaType.statLabel,
                color = colors.text2,
            )
            Spacer(Modifier.height(14.dp))
            SummaryRow(S.Statements.income(sRes()), state.incomeFormatted, colors.positive)
            Spacer(Modifier.height(8.dp))
            SummaryRow(S.Statements.expenses(sRes()), state.expenseFormatted, colors.negative)
            Spacer(Modifier.height(8.dp))
            SummaryRow(S.Statements.transactions(sRes()), state.transactionCount.toString(), colors.text)
            Spacer(Modifier.height(8.dp))
            SummaryRow(
                S.Statements.netForPeriod(sRes()),
                (if (state.netIsPositive) "+" else "−") + state.netFormatted,
                if (state.netIsPositive) colors.positive else colors.negative,
            )
        }

        if (state.days.isEmpty()) {
            SanvyaCard {
                SanvyaText(
                    S.Statements.noTransactions(sRes()),
                    style = SanvyaType.statLabel,
                    color = colors.text2,
                )
            }
        } else {
            state.days.forEach { day ->
                Spacer(Modifier.height(4.dp))
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Eyebrow(dayLabel(day), modifier = Modifier.weight(1f))
                    SanvyaText(
                        (if (day.netIsPositive) "+" else "−") + day.netFormatted,
                        style = SanvyaType.statLabel,
                        color = colors.text2,
                    )
                }
                day.items.forEach { item ->
                    Spacer(Modifier.height(8.dp))
                    TransactionRowCard(
                        item = item,
                        colors = colors,
                        // Web's tile is a `<Link href={/transactions/[id]/edit}>`.
                        // A statement row that could not be opened was the only
                        // list in the app where tapping a transaction did
                        // nothing.
                        onClick = { onEditTransaction(item.id) },
                    )
                }
            }
        }
    }
}

/** Today / Yesterday / "23 Aug 26" — web's `groupTxnsByDay` labels. */
@Composable
private fun dayLabel(day: StatementDayGroup): String = when (day.kind) {
    StatementDayKind.TODAY -> S.Statements.today(sRes())
    StatementDayKind.YESTERDAY -> S.Statements.yesterday(sRes())
    // Web's `{ day: "numeric", month: "short", year: "2-digit" }`.
    StatementDayKind.OTHER -> isoLabel(day.dayIso, "d MMM yy")
}

/**
 * The statement, as plain text, for the share sheet.
 *
 * Assembled here rather than in the view model on purpose: every label in it is
 * a translated string, and `S.Statements.*` needs a `Resources` — which
 * I18n.kt's rule says a view model must not hold. The view model hands over
 * numbers already formatted through `formatMoney`; this only names them.
 */
@Composable
private fun statementShareText(state: StatementsUiState): String = buildString {
    appendLine(S.Statements.statementName(sRes()))
    appendLine("${shortDateLabel(state.start)} – ${shortDateLabel(state.end)}")
    appendLine()
    appendLine("${S.Statements.income(sRes())}: ${state.incomeFormatted}")
    appendLine("${S.Statements.expenses(sRes())}: ${state.expenseFormatted}")
    appendLine("${S.Statements.transactions(sRes())}: ${state.transactionCount}")
    appendLine(
        "${S.Statements.netForPeriod(sRes())}: " +
            (if (state.netIsPositive) "+" else "−") + state.netFormatted,
    )
    state.days.forEach { day ->
        appendLine()
        appendLine(
            "${dayLabel(day)}  " +
                (if (day.netIsPositive) "+" else "−") + day.netFormatted,
        )
        day.items.forEach { item ->
            appendLine("  ${item.title}  ${item.dateFormatted}  ${item.amountFormatted}")
        }
    }
}

@Composable
private fun SummaryRow(label: String, amount: String, color: Color) {
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
