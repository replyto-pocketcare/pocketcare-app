package com.sanvya.app.ui.statements

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Scaffold
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.domain.insights.SeriesPoint
import com.sanvya.app.domain.statements.CategoryTotal
import com.sanvya.app.domain.statements.DayTotal
import com.sanvya.app.domain.statements.ParsedStatement
import com.sanvya.app.domain.statements.RecurringCandidate
import com.sanvya.app.domain.statements.StatementOutlier
import com.sanvya.app.domain.statements.StatementSummary
import com.sanvya.app.domain.statements.byCategory
import com.sanvya.app.domain.statements.byDay
import com.sanvya.app.domain.statements.outliers
import com.sanvya.app.domain.statements.recurringCandidates
import com.sanvya.app.domain.statements.summarize
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaShape
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.FormOptions
import com.sanvya.app.ui.components.SanvyaBarsChart
import com.sanvya.app.ui.components.SanvyaButton
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaChip
import com.sanvya.app.ui.components.SanvyaDonutChart
import com.sanvya.app.ui.components.SanvyaInput
import com.sanvya.app.ui.components.SanvyaText
import com.sanvya.app.ui.formatMoney
import kotlin.math.abs

/**
 * Statement parser and analyzer, on the device.
 *
 * Ported from `apps/web/app/statements/analyze/page.tsx`. Pick a bank or
 * credit-card export, parse it locally, categorise the spends, analyse them,
 * reconcile against what is already recorded, and import what is missing.
 * **Nothing leaves the device** — the claim web's header makes, and the reason
 * every step here is Domain plus a repository rather than an endpoint.
 *
 * **CSV and PDF.** Web reads PDFs with pdf.js; Android has no built-in PDF text
 * extraction, so it goes through `PdfTextExtractor` (PDFBox-Android). That
 * library is optional by design: when it is absent the picker offers CSV only
 * and says so, rather than accepting a file it will then refuse.
 *
 * Mirrors iOS's StatementAnalyzeView.swift.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun StatementAnalyzeScreen(viewModel: StatementAnalyzeViewModel = viewModel()) {
    val res = sRes()
    val colors = LocalSanvyaColors.current
    val context = LocalContext.current

    LaunchedEffect(Unit) { viewModel.start() }

    val kind by viewModel.kind.collectAsState()
    val accountId by viewModel.accountId.collectAsState()
    val accounts by viewModel.accounts.collectAsState()
    val busy by viewModel.busy.collectAsState()
    val error by viewModel.error.collectAsState()
    val parsed by viewModel.parsed.collectAsState()

    // Hoisted: parse() runs in a coroutine and cannot call sRes(), which is
    // @Composable. Same rule the rest of this codebase follows.
    val parsingLabel = S.StatementsAnalyze.parsing(res)
    val categorisingLabel = S.StatementsAnalyze.categorising(res)
    val readFail = S.StatementsAnalyze.readFail(res)

    val readingPdf = S.StatementsAnalyze.readingPdf(res)
    val pdfUnavailable = S.StatementsAnalyze.pdfUnavailable(res)
    val pdfNeedsPassword by viewModel.pdfNeedsPassword.collectAsState()
    val pdfSupported = viewModel.pdfSupported

    // The picked PDF's bytes, kept so the password prompt can retry the same
    // file without sending the user back through the picker -- web re-reads the
    // File object it already has for exactly this.
    var pendingPdf by remember { mutableStateOf<ByteArray?>(null) }
    var password by remember { mutableStateOf("") }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        // Type, not file extension: SAF gives a MIME type it has already
        // resolved, and web's own `/\.pdf$/i` test on the name is the weaker
        // check of the two -- a PDF saved as "statement" has no extension.
        val isPdf = context.contentResolver.getType(uri) == "application/pdf" ||
            uri.lastPathSegment.orEmpty().endsWith(".pdf", ignoreCase = true)
        runCatching {
            if (isPdf) {
                val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                pendingPdf = bytes
                password = ""
                if (bytes == null) viewModel.setError(readFail)
                else viewModel.parsePdf(bytes, null, readingPdf, categorisingLabel, readFail, pdfUnavailable)
            } else {
                val text = context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
                pendingPdf = null
                if (text == null) viewModel.setError(readFail)
                else viewModel.parse(text, parsingLabel, categorisingLabel, readFail)
            }
        }.onFailure { viewModel.setError(it.message ?: readFail) }
    }

    if (pdfNeedsPassword) {
        val bytes = pendingPdf
        AlertDialog(
            onDismissRequest = { viewModel.dismissPasswordPrompt() },
            title = { SanvyaText(S.StatementsAnalyze.pdfPassword(res), SanvyaType.body) },
            text = {
                SanvyaInput(
                    value = password,
                    onValueChange = { password = it },
                    // A statement password is a date of birth or a PAN on most
                    // Indian banks, so the alphanumeric keyboard, not numeric.
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    visualTransformation = PasswordVisualTransformation(),
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.dismissPasswordPrompt()
                        if (bytes != null && password.isNotEmpty()) {
                            viewModel.parsePdf(bytes, password, readingPdf, categorisingLabel, readFail, pdfUnavailable)
                        }
                    },
                    enabled = bytes != null && password.isNotEmpty(),
                ) { SanvyaText(S.StatementsAnalyze.pdfUnlock(res), SanvyaType.button, color = colors.accent) }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.dismissPasswordPrompt() }) {
                    SanvyaText(S.StatementsAnalyze.pdfCancel(res), SanvyaType.button, color = colors.text2)
                }
            },
        )
    }

    Scaffold(containerColor = colors.bg) { padding ->
        val statement = parsed
        if (statement == null) {
            Column(
                modifier = Modifier.padding(padding).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                SanvyaText(
                    S.StatementsAnalyze.introPre(res) + S.StatementsAnalyze.introBold(res) + S.StatementsAnalyze.introMid(res),
                    SanvyaType.body.copy(fontSize = 13.sp),
                    color = colors.text2,
                )
                SanvyaCard(padding = PaddingValues(20.dp)) {
                    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        Field(S.StatementsAnalyze.statementType(res)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                SanvyaChip(S.StatementsAnalyze.bank(res), kind == "bank", onClick = { viewModel.setKind("bank") })
                                SanvyaChip(S.StatementsAnalyze.card(res), kind == "card", onClick = { viewModel.setKind("card") })
                            }
                        }
                        Field(S.StatementsAnalyze.accountToReconcile(res)) {
                            FlowRow(
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                verticalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                SanvyaChip(
                                    S.StatementsAnalyze.chooseLater(res),
                                    accountId.isEmpty(),
                                    onClick = { viewModel.setAccountId("") },
                                )
                                accounts.forEach { a ->
                                    SanvyaChip(a.name, accountId == a.id, onClick = { viewModel.setAccountId(a.id) })
                                }
                            }
                        }
                        SanvyaButton(
                            onClick = {
                                // Not just "text/csv": plenty of banks hand out
                                // a .csv the system types as octet-stream or
                                // plain text, and a picker that greys out the
                                // file the user came to import is a dead end.
                                val types = arrayOf("text/csv", "text/comma-separated-values", "text/plain", "application/octet-stream")
                                picker.launch(if (pdfSupported) types + "application/pdf" else types)
                            },
                            modifier = Modifier.fillMaxWidth(),
                            enabled = busy == null,
                        ) {
                            // The catalogue string says "Choose file (CSV or
                            // PDF)". Without an extractor that is a promise the
                            // picker cannot keep, so it degrades to CSV.
                            val chooseLabel =
                                if (pdfSupported) S.StatementsAnalyze.chooseFile(res)
                                else S.StatementsAnalyze.chooseFileCsvOnly(res)
                            SanvyaText(busy ?: chooseLabel, SanvyaType.button, modifier = Modifier.weight(1f))
                        }
                        error?.let { SanvyaText(it, SanvyaType.body.copy(fontSize = 13.sp), color = colors.negative) }
                        SanvyaText(
                            S.StatementsAnalyze.tipPre(res) + S.StatementsAnalyze.tipBold(res) + S.StatementsAnalyze.tipPost(res),
                            SanvyaType.body.copy(fontSize = 11.5.sp),
                            color = colors.text2,
                        )
                    }
                }
            }
            return@Scaffold
        }

        Results(statement, viewModel, Modifier.padding(padding))
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Results(
    parsed: ParsedStatement,
    viewModel: StatementAnalyzeViewModel,
    modifier: Modifier = Modifier,
) {
    val res = sRes()
    val colors = LocalSanvyaColors.current
    val cur = viewModel.currency
    val reconciliation by viewModel.reconciliation.collectAsState()
    val imported by viewModel.imported.collectAsState()
    val addedRecurring by viewModel.addedRecurring.collectAsState()
    val showAll by viewModel.showAllTransactions.collectAsState()
    val accountId by viewModel.accountId.collectAsState()

    // remember(parsed): the analysis is pure and a statement can be hundreds of
    // rows, so it must not re-run on every recomposition of an unrelated chip.
    val summary = remember(parsed) { summarize(parsed.txns) }
    val cats = remember(parsed) { byCategory(parsed.txns) }
    val days = remember(parsed) { byDay(parsed.txns) }
    val flagged = remember(parsed) { outliers(parsed.txns) }
    // Irregular patterns are dropped and the list is capped at six: a
    // "recurring" suggestion the user has to think about is worse than none,
    // and web caps it identically.
    val recurring = remember(parsed) {
        recurringCandidates(parsed.txns).filter { it.cadence != "irregular" }.take(6)
    }
    val shown = if (showAll) parsed.txns else parsed.txns.take(12)

    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        item {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    SanvyaText(parsed.label, SanvyaType.h2.copy(fontSize = 21.sp, fontWeight = FontWeight.SemiBold))
                    SanvyaText(
                        buildList {
                            if (parsed.period.from != null && parsed.period.to != null) {
                                add("${parsed.period.from} → ${parsed.period.to}")
                            }
                            add(S.StatementsAnalyze.transactions(res, parsed.txns.size))
                            if (viewModel.accountName.isNotEmpty()) add(viewModel.accountName)
                        }.joinToString(" · "),
                        SanvyaType.body.copy(fontSize = 13.sp),
                        color = colors.text2,
                    )
                }
                SanvyaButton(onClick = { viewModel.reset() }, ghost = true) {
                    SanvyaText(S.StatementsAnalyze.newStatement(res), SanvyaType.button, color = colors.text)
                }
            }
        }

        if (parsed.warnings.isNotEmpty()) {
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(colors.accentGhost, SanvyaShape.radiusSm)
                        .padding(horizontal = 12.dp, vertical = 9.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    parsed.warnings.forEach {
                        SanvyaText("⚠ $it", SanvyaType.body.copy(fontSize = 12.5.sp), color = colors.text2)
                    }
                }
            }
        }

        item { Stats(parsed, summary, cur, res) }

        item { Charts(cats, days, cur, res) }

        if (flagged.isNotEmpty()) item { Outliers(flagged, cur, res) }

        if (recurring.isNotEmpty()) {
            item { Recurring(recurring, cur, res, addedRecurring, viewModel::addRecurring) }
        }

        item {
            SanvyaCard(padding = PaddingValues(16.dp)) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Eyebrow(S.StatementsAnalyze.reconcileTitle(res))
                    val rec = reconciliation
                    if (accountId.isEmpty() || rec == null) {
                        SanvyaText(
                            S.StatementsAnalyze.pickAccountReconcile(res),
                            SanvyaType.body.copy(fontSize = 13.sp),
                            color = colors.text2,
                        )
                    } else {
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(16.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Tally("${rec.matched.size}", S.StatementsAnalyze.matchedLabel(res), colors.positive)
                            Tally("${rec.missingOnPlatform.size}", S.StatementsAnalyze.missingLabel(res), colors.accent)
                            Tally("${rec.onlyOnPlatform.size}", S.StatementsAnalyze.onlyPlatformLabel(res), colors.text2)
                        }
                        if (rec.missingOnPlatform.isNotEmpty() && !imported) {
                            SanvyaButton(onClick = { viewModel.importMissing() }, modifier = Modifier.fillMaxWidth()) {
                                SanvyaText(
                                    S.StatementsAnalyze.importMissing(res, rec.missingOnPlatform.size, viewModel.accountName),
                                    SanvyaType.button,
                                    modifier = Modifier.weight(1f),
                                )
                            }
                        }
                        if (imported) {
                            SanvyaText(
                                S.StatementsAnalyze.importedDone(res),
                                SanvyaType.body.copy(fontSize = 13.sp),
                                color = colors.positive,
                            )
                        }
                    }
                }
            }
        }

        item { Eyebrow(S.StatementsAnalyze.transactionsTitle(res, parsed.txns.size)) }

        item {
            SanvyaCard(padding = PaddingValues(0.dp)) {
                Column {
                    shown.forEachIndexed { i, t ->
                        if (i > 0) HorizontalDivider(color = colors.border)
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                                SanvyaText(t.description, SanvyaType.body.copy(fontSize = 13.5.sp))
                                SanvyaText(
                                    t.category?.let { "${t.date} · $it" } ?: t.date,
                                    SanvyaType.body.copy(fontSize = 11.5.sp),
                                    color = colors.text2,
                                )
                            }
                            SanvyaText(
                                (if (t.amount >= 0) "+" else "−") + formatMoney(abs(t.amount), cur),
                                SanvyaType.body.copy(fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold),
                                color = if (t.amount >= 0) colors.positive else colors.text,
                            )
                        }
                    }
                }
            }
        }

        if (parsed.txns.size > 12) {
            item {
                SanvyaChip(
                    if (showAll) S.StatementsAnalyze.showLess(res) else S.StatementsAnalyze.showAll(res, parsed.txns.size),
                    false,
                    onClick = { viewModel.toggleShowAll() },
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Stats(
    parsed: ParsedStatement,
    s: StatementSummary,
    cur: String,
    res: android.content.res.Resources,
) {
    val colors = LocalSanvyaColors.current
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Stat(S.StatementsAnalyze.moneyIn(res), formatMoney(s.credits, cur), colors.positive)
        Stat(S.StatementsAnalyze.moneyOut(res), formatMoney(s.debits, cur), colors.negative)
        Stat(
            S.StatementsAnalyze.net(res),
            (if (s.net >= 0) "+" else "−") + formatMoney(abs(s.net), cur),
            if (s.net >= 0) colors.positive else colors.negative,
        )
        parsed.closingBalance?.let {
            Stat(S.StatementsAnalyze.closingBalance(res), formatMoney(it, cur), colors.text)
        }
        // `card` is never filled by the CSV parser -- web only reads it off a
        // PDF header. These light up the day PDF lands and stay invisible until
        // then, rather than showing three empty stats.
        parsed.card?.totalDue?.let { Stat(S.StatementsAnalyze.totalDue(res), formatMoney(it, cur), colors.text) }
        parsed.card?.minDue?.let { Stat(S.StatementsAnalyze.minimumDue(res), formatMoney(it, cur), colors.text) }
        parsed.card?.dueDate?.let { Stat(S.StatementsAnalyze.payBy(res), it, colors.negative) }
    }
}

@Composable
private fun Charts(
    cats: List<CategoryTotal>,
    days: List<DayTotal>,
    cur: String,
    res: android.content.res.Resources,
) {
    val colors = LocalSanvyaColors.current
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SanvyaCard(padding = PaddingValues(16.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Eyebrow(S.StatementsAnalyze.whereItWent(res))
                if (cats.isEmpty()) {
                    ChartEmpty(res)
                } else {
                    Box(Modifier.fillMaxWidth().height(220.dp)) {
                        // Top seven, matching web. An eighth slice on a
                        // phone-width donut is a sliver with an unreadable label.
                        SanvyaDonutChart(
                            series = cats.take(7).mapIndexed { i, c ->
                                SeriesPoint(c.name, c.total.toDouble(), FormOptions.chartColors[i % FormOptions.chartColors.size])
                            },
                            centerLabel = formatMoney(cats.sumOf { it.total }, cur),
                            centerSub = null,
                            accent = colors.accent,
                            colors = colors,
                        )
                    }
                }
            }
        }
        SanvyaCard(padding = PaddingValues(16.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Eyebrow(S.StatementsAnalyze.dailySpend(res))
                if (days.isEmpty()) {
                    ChartEmpty(res)
                } else {
                    Box(Modifier.fillMaxWidth().height(220.dp)) {
                        SanvyaBarsChart(
                            // Month-day only: a full ISO date under every bar on
                            // a 30-day statement is unreadable. Web slices the
                            // same five characters off.
                            series = days.map { SeriesPoint(it.date.drop(5), it.debit.toDouble()) },
                            horizontal = false,
                            accent = colors.accent,
                            colors = colors,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun Outliers(items: List<StatementOutlier>, cur: String, res: android.content.res.Resources) {
    val colors = LocalSanvyaColors.current
    SanvyaCard(padding = PaddingValues(16.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Eyebrow(S.StatementsAnalyze.outliersTitle(res))
            items.take(5).forEach { o ->
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    SanvyaText(
                        "${o.txn.description} · ${o.txn.date}",
                        SanvyaType.body.copy(fontSize = 13.sp),
                        modifier = Modifier.weight(1f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    SanvyaText(
                        formatMoney(o.amount, cur),
                        SanvyaType.body.copy(fontSize = 13.sp, fontWeight = FontWeight.SemiBold),
                        color = colors.negative,
                    )
                }
            }
        }
    }
}

@Composable
private fun Recurring(
    items: List<RecurringCandidate>,
    cur: String,
    res: android.content.res.Resources,
    added: Set<String>,
    onAdd: (RecurringCandidate) -> Unit,
) {
    val colors = LocalSanvyaColors.current
    SanvyaCard(padding = PaddingValues(16.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Eyebrow(S.StatementsAnalyze.looksRecurring(res))
            items.forEach { r ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        SanvyaText(
                            r.label,
                            SanvyaType.body.copy(fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        SanvyaText(
                            S.StatementsAnalyze.recurringMeta(
                                res,
                                formatMoney(r.amount, cur),
                                cadenceLabel(r.cadence, res),
                                r.count,
                            ),
                            SanvyaType.body.copy(fontSize = 11.5.sp),
                            color = colors.text2,
                        )
                    }
                    if (added.contains(r.key)) {
                        SanvyaText(
                            S.StatementsAnalyze.added(res),
                            SanvyaType.body.copy(fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold),
                            color = colors.positive,
                        )
                    } else {
                        SanvyaChip(S.StatementsAnalyze.addAsRecurring(res), false, onClick = { onAdd(r) })
                    }
                }
            }
        }
    }
}

private fun cadenceLabel(cadence: String, res: android.content.res.Resources): String = when (cadence) {
    "weekly" -> S.StatementsAnalyze.cadenceWeekly(res)
    "yearly" -> S.StatementsAnalyze.cadenceYearly(res)
    else -> S.StatementsAnalyze.cadenceMonthly(res)
}

@Composable
private fun Field(label: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        SanvyaText(label, SanvyaType.body.copy(fontSize = 12.sp), color = LocalSanvyaColors.current.text2)
        content()
    }
}

@Composable
private fun Eyebrow(text: String) {
    SanvyaText(
        text.uppercase(),
        SanvyaType.statLabel.copy(fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.6.sp),
        color = LocalSanvyaColors.current.text2,
    )
}

@Composable
private fun Stat(label: String, value: String, color: androidx.compose.ui.graphics.Color) {
    SanvyaCard(modifier = Modifier.widthIn(min = 150.dp), padding = PaddingValues(16.dp)) {
        Eyebrow(label)
        SanvyaText(value, SanvyaType.body.copy(fontSize = 20.sp, fontWeight = FontWeight.Bold), color = color)
    }
}

@Composable
private fun Tally(value: String, label: String, color: androidx.compose.ui.graphics.Color) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        SanvyaText(value, SanvyaType.body.copy(fontSize = 13.sp, fontWeight = FontWeight.Bold), color = color)
        SanvyaText(label, SanvyaType.body.copy(fontSize = 13.sp), color = LocalSanvyaColors.current.text2)
    }
}

@Composable
private fun ChartEmpty(res: android.content.res.Resources) {
    val colors = LocalSanvyaColors.current
    Box(Modifier.fillMaxWidth().height(220.dp), contentAlignment = Alignment.Center) {
        SanvyaText(S.StatementsAnalyze.noSpends(res), SanvyaType.body.copy(fontSize = 13.sp), color = colors.text3)
    }
}
