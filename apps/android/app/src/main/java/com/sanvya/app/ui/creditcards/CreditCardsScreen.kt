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
    val colors = LocalSanvyaColors.current
    val scope = rememberCoroutineScope()

    Scaffold(
        containerColor = colors.bg,
        topBar = {
            TopAppBar(
                title = { Text("Credit Cards", fontWeight = FontWeight.Bold, color = colors.text) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = colors.text2) } },
                actions = { IconButton(onClick = onAddAccount) { Icon(Icons.Default.Add, contentDescription = "Add card", tint = colors.accent) } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.bg),
            )
        },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            when {
                !loaded -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                cards.isEmpty() -> EmptyCardsState(colors, onAddAccount)
                else -> Column(
                    modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                ) {
                    cards.forEachIndexed { i, card ->
                        CreditCardPanel(card = card, index = i, sources = sources, viewModel = viewModel, colors = colors, scope = scope)
                    }
                    Spacer(Modifier.height(8.dp))
                }
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
            Text("No credit cards yet", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.text)
            Text(
                "Add a credit-card account to track its billing cycle, dues, and settle-ups here.",
                fontSize = 13.sp, color = colors.text2, textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(4.dp))
            Button(onClick = onAddAccount) { Text("＋ Add account") }
        }
    }
}

@Composable
private fun CreditCardPanel(
    card: CreditCardUiModel,
    index: Int,
    sources: List<SettleSourceOption>,
    viewModel: CreditCardsViewModel,
    colors: SanvyaColors,
    scope: CoroutineScope,
) {
    var expanded by rememberSaveable(card.accountId) { mutableStateOf(false) }
    var editing by rememberSaveable(card.accountId) { mutableStateOf(!card.hasCycle) }
    var stmt by rememberSaveable(card.accountId) { mutableStateOf(card.statementDay.toString()) }
    var due by rememberSaveable(card.accountId) { mutableStateOf(card.dueDay.toString()) }
    var limit by rememberSaveable(card.accountId) { mutableStateOf("") }
    var dueAmt by rememberSaveable(card.accountId) { mutableStateOf("") }
    var last4 by rememberSaveable(card.accountId) { mutableStateOf(card.last4 ?: "") }
    var fromId by rememberSaveable(card.accountId) { mutableStateOf<String?>(null) }
    var amountText by rememberSaveable(card.accountId) { mutableStateOf("") }
    var error by rememberSaveable(card.accountId) { mutableStateOf<String?>(null) }

    val baseColor = card.accountColorHex?.let { runCatching { Color(android.graphics.Color.parseColor(it)) }.getOrNull() }
        ?: runCatching { Color(android.graphics.Color.parseColor(FALLBACK_PALETTE[index % FALLBACK_PALETTE.size])) }.getOrElse { colors.forest }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        // Card face -- mirrors CreditCard.tsx: gradient from the account's own
        // color, network = account name (no real "network" concept exists),
        // masked digits, "Card holder" placeholder (no session-username plumbing
        // wired up for this label yet), currency in the bottom corner.
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
                        Text("CARD HOLDER", color = Color.White.copy(alpha = 0.7f), fontSize = 9.sp, fontWeight = FontWeight.Bold)
                        Text("Card holder", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                    }
                    Column(horizontalAlignment = Alignment.End) {
                        Text("CURRENCY", color = Color.White.copy(alpha = 0.7f), fontSize = 9.sp, fontWeight = FontWeight.Bold)
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
                        Text("Spent this cycle", fontSize = 12.sp, color = colors.text2)
                        Text(card.owedFormatted, fontSize = 26.sp, fontWeight = FontWeight.Bold, color = colors.negative)
                        card.creditLimitFormatted?.let { Text("of $it limit", fontSize = 12.sp, color = colors.text2) }
                    }
                    if (!expanded && card.hasCycle) {
                        Column(horizontalAlignment = Alignment.End) {
                            card.dueThisCycleFormatted?.let {
                                Text("Due this cycle", fontSize = 12.sp, color = colors.text2)
                                Text(it, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = if (card.dueThisCycle != 0L) colors.negative else colors.positive)
                            }
                            card.payByIso?.let { Text("Pay by ${it.toDisplayDate()}", fontSize = 11.sp, color = colors.text2) }
                        }
                    }
                }
            }

            if (expanded) {
                Column(Modifier.padding(start = 20.dp, end = 20.dp, bottom = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (card.hasCycle) {
                        card.availableCreditFormatted?.let { Text("Available credit: $it", fontSize = 12.sp, color = colors.positive) }
                        card.newSpendFormatted?.let { Text("+$it new spend since the last statement", fontSize = 11.sp, color = colors.text2) }
                        card.statementDateIso?.let { Text("Statement: ${it.toDisplayDate()}", fontSize = 11.sp, color = colors.text2) }
                        if (!editing) {
                            TextButton(onClick = { editing = true; limit = ""; dueAmt = "" }) { Text("Edit details") }
                        }
                    }

                    if (editing) {
                        OutlinedTextField(stmt, { stmt = it.filter(Char::isDigit) }, label = { Text("Statement day") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                        OutlinedTextField(due, { due = it.filter(Char::isDigit) }, label = { Text("Due day") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                        OutlinedTextField(limit, { limit = it }, label = { Text("Credit limit") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                        OutlinedTextField(dueAmt, { dueAmt = it }, label = { Text("Amount due") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                        OutlinedTextField(last4, { last4 = it.filter(Char::isDigit).takeLast(4) }, label = { Text("Card number (last 4)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(onClick = {
                                scope.launch {
                                    error = viewModel.saveCycle(card.accountId, card.currency, stmt, due, limit, dueAmt, last4, card.creditLimit)
                                    if (error == null) editing = false
                                }
                            }) { Text("Save") }
                            if (card.hasCycle) TextButton(onClick = { editing = false }) { Text("Cancel") }
                        }
                    }

                    HorizontalDivider(color = colors.border)

                    Text("Settle from", fontSize = 12.sp, color = colors.text2)
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
                        OutlinedTextField(amountText, { amountText = it }, label = { Text("Amount") }, singleLine = true, modifier = Modifier.weight(1f))
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
                        ) { Text("Settle") }
                    }
                    error?.let { Text(it, fontSize = 12.sp, color = colors.negative) }
                }
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
        title = { Text("Mark EMIs paid?") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    "This payment covers ${covered.size} instalment(s) charged to this card. Mark them paid?",
                    fontSize = 13.5.sp, color = colors.text2,
                )
                covered.forEach { c ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Column {
                            Text("EMI #${c.emiNo}" + (c.lender?.let { " · $it" } ?: ""), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = colors.text)
                            Text(c.dueDate.toDisplayDate(), fontSize = 11.5.sp, color = colors.text2)
                        }
                        Text(formatMoney(c.amount, baseCurrencyNow()), fontWeight = FontWeight.Bold, color = colors.text)
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onConfirm) { Text("Mark paid") } },
        dismissButton = { TextButton(onClick = onSkip) { Text("Not now") } },
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
