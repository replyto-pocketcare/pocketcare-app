package com.sanvya.app.ui.creditcards

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaColors
import com.sanvya.app.theme.SanvyaRadius
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import com.sanvya.app.ui.formatMoney
import com.sanvya.app.ui.baseCurrencyNow
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.ui.components.SanvyaModal
import com.sanvya.app.ui.components.SanvyaPage

/**
 * Real port of apps/web/app/cards/page.tsx + src/cards/CreditCard.tsx
 * (task #29), replacing a fake predecessor with no consuming screen at
 * all (dead-code CreditCardsViewModel.kt, no CreditCardsScreen.kt in the
 * repo). See docs/mobile/screen-specs/credit-cards.md.
 *
 * Note: docs/features/cards.md describes a three.js/react-three-fiber 3D
 * wallet -- that's stale, the real page.tsx is a plain CSS card list.
 * This screen matches the real source.
 */
private val FALLBACK_PALETTE = listOf("#3e4a38", "#b06a4f", "#5f6647", "#7c4a3a", "#2b2723")
private val DATE_FMT = DateTimeFormatter.ofPattern("d MMM yyyy", Locale.ENGLISH)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreditCardsScreen(
    onBack: () -> Unit = {},
    onAddAccount: () -> Unit = {},
    viewModel: CreditCardsViewModel = viewModel(),
) {
    val cards by viewModel.cards.collectAsState()
    val sources by viewModel.sources.collectAsState()
    val loaded by viewModel.loaded.collectAsState()
    val coveredEmis by viewModel.coveredEmis.collectAsState()
    val charges by viewModel.charges.collectAsState()
    val holderName by viewModel.holderName.collectAsState()
    val colors = LocalSanvyaColors.current
    val scope = rememberCoroutineScope()

    SanvyaPage(
        title = S.Cards.title(sRes()),
        action = {
 IconButton(onClick = onAddAccount) { Icon(Icons.Default.Add, contentDescription = S.Cards.addCard(sRes()), tint = colors.accent) }
        },
    ) {
        Box(Modifier.fillMaxSize()) {
            when {
                !loaded -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                cards.isEmpty() -> EmptyCardsState(colors, onAddAccount)
                else -> Column(
                    modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                ) {
                    cards.forEachIndexed { i, card ->
                        CreditCardPanel(card = card, index = i, holderName = holderName, sources = sources, viewModel = viewModel, colors = colors, scope = scope)
                    }
                    Spacer(Modifier.height(8.dp))
                }
            }

            // The charges behind the balance, newest first, with the same
            // running total web prints in the header. Rendered once at screen
            // level rather than inside each panel: the list is view-model
            // state, so it survives the panel recomposing behind the scrim.
            charges?.let {
                CardChargesModal(charges = it, onClose = { viewModel.closeCharges() }, colors = colors)
            }

            if (coveredEmis.isNotEmpty()) {
                CoveredEmisDialog(
                    covered = coveredEmis,
                    onConfirm = { viewModel.confirmMarkEmisPaid() },
                    onSkip = { viewModel.skipMarkEmisPaid() },
                    colors = colors,
                )
            }
        }
    }
}

@Composable
private fun EmptyCardsState(colors: SanvyaColors, onAddAccount: () -> Unit) {
    Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(Icons.Default.CreditCard, contentDescription = null, tint = colors.text2, modifier = Modifier.size(30.dp))
            // Web's empty state is `emptyBody` under the page title and a
            // `＋ newAccount` link -- no second heading, and no bespoke copy.
            Text(
                S.Cards.emptyBody(sRes()),
                fontSize = 13.sp, color = colors.text2, textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(4.dp))
            Button(onClick = onAddAccount) { Text("＋ " + S.Cards.newAccount(sRes())) }
        }
    }
}

@Composable
private fun CreditCardPanel(
    card: CreditCardUiModel,
    index: Int,
    holderName: String,
    sources: List<SettleSourceOption>,
    viewModel: CreditCardsViewModel,
    colors: SanvyaColors,
    scope: CoroutineScope,
) {
    var expanded by rememberSaveable(card.accountId) { mutableStateOf(false) }
    var editing by rememberSaveable(card.accountId) { mutableStateOf(!card.hasCycle) }
    var stmt by rememberSaveable(card.accountId) { mutableStateOf(card.statementDay.toString()) }
    var due by rememberSaveable(card.accountId) { mutableStateOf(card.dueDay.toString()) }
    var limit by rememberSaveable(card.accountId) { mutableStateOf(card.creditLimitMajorText) }
    var dueAmt by rememberSaveable(card.accountId) { mutableStateOf(card.pendingDueMajorText) }
    var last4 by rememberSaveable(card.accountId) { mutableStateOf(card.last4 ?: "") }
    var fromId by rememberSaveable(card.accountId) { mutableStateOf<String?>(null) }
    var amountText by rememberSaveable(card.accountId) { mutableStateOf("") }
    var error by rememberSaveable(card.accountId) { mutableStateOf<String?>(null) }

    /**
     * Keep the form seeded from what is actually stored, for as long as the
     * user is not typing into it.
     *
     * This is the fix for a live data-loss bug: the form used to open BLANK and
     * `saveCycle` writes whatever the fields hold, so changing only the
     * statement day and pressing Save erased the user's `pending_due` (and
     * would have erased the credit limit, but for a fallback in the view
     * model). Web seeds its inputs from the loaded detail, so an unchanged save
     * is a no-op -- this restores that, and additionally re-seeds if the detail
     * row lands AFTER the panel first composed, which web's `useState`
     * initialiser cannot do.
     *
     * Guarded on `!editing` so it can never overwrite what the user is typing.
     */
    LaunchedEffect(
        card.accountId, card.statementDay, card.dueDay, card.last4,
        card.creditLimitMajorText, card.pendingDueMajorText, editing,
    ) {
        if (!editing) {
            stmt = card.statementDay.toString()
            due = card.dueDay.toString()
            limit = card.creditLimitMajorText
            dueAmt = card.pendingDueMajorText
            last4 = card.last4 ?: ""
        }
    }

    val baseColor = card.accountColorHex?.let { runCatching { Color(android.graphics.Color.parseColor(it)) }.getOrNull() }
        ?: runCatching { Color(android.graphics.Color.parseColor(FALLBACK_PALETTE[index % FALLBACK_PALETTE.size])) }.getOrElse { colors.forest }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        // Card face -- mirrors CreditCard.tsx: gradient from the account's own
        // color, network = account name (no real "network" concept exists),
        // masked digits, the signed-in user's name under the "Card Holder"
        // label, currency in the bottom corner.
        Box(
            modifier = Modifier.fillMaxWidth().aspectRatio(1.586f)
                .clip(RoundedCornerShape(18.dp))
                .background(Brush.linearGradient(listOf(baseColor, shade(baseColor, -0.30f))))
                .padding(20.dp),
        ) {
            Column(Modifier.fillMaxSize()) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(card.accountName, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                    Text(")))", color = Color.White.copy(alpha = 0.85f), fontSize = 16.sp, fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.weight(1f))
                Box(Modifier.size(width = 40.dp, height = 30.dp).clip(RoundedCornerShape(6.dp)).background(Color(0xFFE8D4A8)))
                Spacer(Modifier.weight(1f))
                Text(
                    if (card.last4 != null) "••••  ••••  ••••  ${card.last4}" else "••••  ••••  ••••  ••••",
                    color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold, letterSpacing = 2.sp,
                )
                Spacer(Modifier.weight(1f))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.Bottom) {
                    Column {
                        Text(S.Cards.cardHolder(sRes()), color = Color.White.copy(alpha = 0.7f), fontSize = 9.sp, fontWeight = FontWeight.Bold)
                        // Web: `(session?.username || "").trim() || t("cardHolder")` --
                        // an unnamed user still gets a plausible-looking card
                        // rather than a blank line.
                        Text(
                            holderName.ifBlank { S.Cards.cardHolder(sRes()) },
                            color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold,
                        )
                    }
                    Column(horizontalAlignment = Alignment.End) {
                        Text(S.Accounts.currency(sRes()), color = Color.White.copy(alpha = 0.7f), fontSize = 9.sp, fontWeight = FontWeight.Bold)
                        Text(card.currency, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }

        // Panel -- expand/collapse mirrors web's <details>/<summary>.
        Card(colors = CardDefaults.cardColors(containerColor = colors.surface), shape = RoundedCornerShape(SanvyaRadius.radiusLg)) {
            Column(Modifier.padding(20.dp).clickable { expanded = !expanded }) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.Top) {
                    Column {
                        Text(S.Cards.spentThisCycle(sRes()), fontSize = 12.sp, color = colors.text2)
                        Text(card.owedFormatted, fontSize = 26.sp, fontWeight = FontWeight.Bold, color = colors.negative)
                        card.creditLimitFormatted?.let { Text(S.Cards.ofLimit(sRes(), it), fontSize = 12.sp, color = colors.text2) }
                    }
                    if (!expanded && card.hasCycle) {
                        Column(horizontalAlignment = Alignment.End) {
                            card.dueThisCycleFormatted?.let {
                                Text(S.Cards.dueThisCycle(sRes()), fontSize = 12.sp, color = colors.text2)
                                Text(it, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = if (card.dueThisCycle != 0L) colors.negative else colors.positive)
                            }
                            card.payByIso?.let {
                                // Web stacks the label above its value; two
                                // Texts, not one concatenated string.
                                Text(S.Cards.payBy(sRes()), fontSize = 11.sp, color = colors.text2)
                                Text(it.toDisplayDate(), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = colors.text)
                            }
                            // A closed statement whose due date has moved past
                            // this cycle shows "Due this cycle 0"; without this
                            // line nothing says where the balance went. Web
                            // renders the same pair together (cards/page.tsx).
                            if (card.rolledToNext) {
                                card.pendingDueFormatted?.let {
                                    Text(S.Cards.dueNextCycle(sRes(), it), fontSize = 11.sp, color = colors.text2)
                                }
                            }
                        }
                    }
                }
            }

            if (expanded) {
                Column(Modifier.padding(start = 20.dp, end = 20.dp, bottom = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (card.hasCycle) {
                        card.availableCreditFormatted?.let { Text(S.Cards.availableCredit(sRes(), it), fontSize = 12.sp, color = colors.positive) }
                        card.newSpendFormatted?.let { Text(S.Cards.newSpendThisCycle(sRes(), it), fontSize = 11.sp, color = colors.text2) }
                        card.statementDateIso?.let { Text(S.Cards.statement(sRes(), it.toDisplayDate()), fontSize = 11.sp, color = colors.text2) }
                        if (!editing) {
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                // Web hides this control when the card has no
                                // charges yet, which is why the count travels
                                // with the model.
                                if (card.chargeCount > 0) {
                                    TextButton(onClick = { viewModel.openCharges(card.accountId, card.currency) }) {
                                        Text(S.Cards.viewTransactions(sRes()))
                                    }
                                }
                                // Seeds explicitly as well as via the effect
                                // above: the effect is what keeps the fields
                                // current, this is what guarantees the state
                                // the user sees is the state that will be
                                // saved, in one place a reader can find.
                                TextButton(onClick = {
                                    stmt = card.statementDay.toString()
                                    due = card.dueDay.toString()
                                    limit = card.creditLimitMajorText
                                    dueAmt = card.pendingDueMajorText
                                    last4 = card.last4 ?: ""
                                    editing = true
                                }) { Text(S.Cards.editDetails(sRes())) }
                            }
                        }
                    }

                    if (editing) {
                        OutlinedTextField(stmt, { stmt = it.filter(Char::isDigit) }, label = { Text(S.Cards.statementDay(sRes())) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                        OutlinedTextField(due, { due = it.filter(Char::isDigit) }, label = { Text(S.Cards.dueDay(sRes())) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                        OutlinedTextField(limit, { limit = it }, label = { Text(S.Cards.creditLimit(sRes())) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                        OutlinedTextField(dueAmt, { dueAmt = it }, label = { Text(S.Cards.amountDue(sRes())) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                        OutlinedTextField(last4, { last4 = it.filter(Char::isDigit).takeLast(4) }, label = { Text(S.Cards.cardNumber(sRes())) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(onClick = {
                                scope.launch {
                                    error = viewModel.saveCycle(card.accountId, card.currency, stmt, due, limit, dueAmt, last4, card.creditLimit)
                                    if (error == null) editing = false
                                }
                            }) { Text(S.Cards.save(sRes())) }
                            if (card.hasCycle) TextButton(onClick = { editing = false }) { Text(S.Cards.cancel(sRes())) }
                        }
                    }

                    HorizontalDivider(color = colors.border)

                    Text(S.Cards.settleFrom(sRes()), fontSize = 12.sp, color = colors.text2)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        sources.forEach { s ->
                            val active = (fromId ?: sources.firstOrNull()?.id) == s.id
                            AssistChip(
                                onClick = { fromId = s.id },
                                label = { Text(s.name) },
                                colors = AssistChipDefaults.assistChipColors(
                                    containerColor = if (active) colors.accent.copy(alpha = 0.18f) else colors.surface2,
                                    labelColor = if (active) colors.accent else colors.text2,
                                ),
                            )
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        OutlinedTextField(amountText, { amountText = it }, label = { Text(S.Cards.amountPlaceholder(sRes())) }, singleLine = true, modifier = Modifier.weight(1f))
                        Button(
                            onClick = {
                                scope.launch {
                                    val from = fromId ?: sources.firstOrNull()?.id
                                    if (from != null) {
                                        error = viewModel.settle(card.accountId, card.currency, from, amountText)
                                        if (error == null) amountText = ""
                                    }
                                }
                            },
                            enabled = amountText.isNotBlank() && sources.isNotEmpty(),
                        ) { Text(S.Cards.settle(sRes())) }
                    }
                    error?.let { Text(it, fontSize = 12.sp, color = colors.negative) }
                }
            }
        }
    }
}

/**
 * The charges that add up to the amount due -- newest first, with the running
 * total in the header. Web's `Modal` in cards/page.tsx.
 *
 * A plain [Column], not a LazyColumn: [SanvyaModal] already puts its content
 * inside a vertically scrolling container, and a lazy list nested in one has
 * unbounded height (a Compose runtime crash, not a layout glitch).
 */
@Composable
private fun CardChargesModal(
    charges: CardChargesUiModel,
    onClose: () -> Unit,
    colors: SanvyaColors,
) {
    SanvyaModal(open = true, onClose = onClose, label = S.Cards.cardTxnsTitle(sRes())) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Bottom,
            ) {
                Text(S.Cards.cardTxnsTitle(sRes()), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = colors.text)
                Text(S.Cards.cardTxnsTotal(sRes(), charges.totalFormatted), fontSize = 13.sp, color = colors.text2)
            }
            if (charges.rows.isEmpty()) {
                Text(S.Cards.noCardTxns(sRes()), fontSize = 13.sp, color = colors.text2)
            } else {
                Column {
                    charges.rows.forEachIndexed { i, row ->
                        if (i > 0) HorizontalDivider(color = colors.border)
                        Row(
                            Modifier.fillMaxWidth().padding(vertical = 10.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(Modifier.weight(1f)) {
                                // Web falls back to the `uncategorised` label
                                // for a charge with no description.
                                Text(
                                    row.description?.takeIf { it.isNotBlank() } ?: S.Cards.uncategorised(sRes()),
                                    fontSize = 14.sp, color = colors.text,
                                )
                                Text(row.occurredAtIso.toDisplayDate(), fontSize = 11.5.sp, color = colors.text2)
                            }
                            Text(row.amountFormatted, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = colors.text)
                        }
                    }
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = onClose) { Text(S.Cards.cancel(sRes())) }
            }
        }
    }
}

@Composable
private fun CoveredEmisDialog(
    covered: List<com.sanvya.app.data.repository.CoveredEmi>,
    onConfirm: () -> Unit,
    onSkip: () -> Unit,
    colors: SanvyaColors,
) {
    AlertDialog(
        onDismissRequest = onSkip,
        title = { Text(S.Cards.emiCoveredTitle(sRes())) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    S.Cards.emiCoveredBody(sRes(), covered.size),
                    fontSize = 13.5.sp, color = colors.text2,
                )
                covered.forEach { c ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Column {
                            Text(S.Cards.emiNo(sRes(), c.emiNo) + (c.lender?.let { " · $it" } ?: ""), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = colors.text)
                            Text(c.dueDate.toDisplayDate(), fontSize = 11.5.sp, color = colors.text2)
                        }
                        Text(formatMoney(c.amount, baseCurrencyNow()), fontWeight = FontWeight.Bold, color = colors.text)
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onConfirm) { Text(S.Cards.emiCoveredConfirm(sRes())) } },
        dismissButton = { TextButton(onClick = onSkip) { Text(S.Cards.emiCoveredSkip(sRes())) } },
        containerColor = colors.surface,
    )
}

private fun String.toDisplayDate(): String = try {
    LocalDate.parse(this.take(10)).format(DATE_FMT)
} catch (e: Exception) {
    this
}

/** Lighten/darken [color] by [percent] (-1f..1f) -- mirrors CreditCard.tsx's
 * `shade()`. */
private fun shade(color: Color, percent: Float): Color {
    fun ch(c: Float): Float = (c + percent).coerceIn(0f, 1f)
    return Color(ch(color.red), ch(color.green), ch(color.blue), color.alpha)
}
