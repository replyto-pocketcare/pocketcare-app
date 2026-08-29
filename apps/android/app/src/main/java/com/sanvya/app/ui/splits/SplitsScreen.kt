package com.sanvya.app.ui.splits

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaRadius
import com.sanvya.app.ui.FormOptions
import com.sanvya.app.ui.baseCurrencyNow
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.ui.components.DateField
import com.sanvya.app.ui.components.SanvyaPage
import com.sanvya.app.ui.components.SanvyaModal
import com.sanvya.app.ui.dayMonthLabel
import com.sanvya.app.ui.formatMoney
import com.sanvya.app.domain.js.jsRound
import com.sanvya.app.domain.splitsinsights.FriendInsight

/**
 * Real port of apps/web/app/friends/page.tsx's hub (task #30) -- replaces
 * the previous no-op drawer entry (`comingSoonRoute("Splits & groups")`).
 * See docs/mobile/screen-specs/splits.md.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SplitsScreen(
    onOpenGroup: (String) -> Unit,
    viewModel: SplitsViewModel = viewModel(),
) {
    val colors = LocalSanvyaColors.current
    val groups by viewModel.groups.collectAsState()
    val friends by viewModel.friends.collectAsState()
    val overview by viewModel.overview.collectAsState()
    val loaded by viewModel.loaded.collectAsState()
    var tab by remember { mutableStateOf(0) }
    var showCreate by remember { mutableStateOf(false) }
    var person by remember { mutableStateOf<FriendEdgeUiModel?>(null) }

    SanvyaPage(
        title = S.Splits.eyebrow(sRes()),
        action = {
 IconButton(onClick = { showCreate = true }) { Icon(Icons.Default.Add, contentDescription = S.Splits.newGroupCta(sRes()), tint = colors.accent) }
        },
    ) {
        Column(Modifier.fillMaxSize()) {
            overview?.let { ov ->
                Column(
                    modifier = Modifier.fillMaxWidth().padding(16.dp)
                        .background(colors.accent.copy(alpha = 0.08f), RoundedCornerShape(SanvyaRadius.radiusLg)).padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Text(S.Splits.netPosition(sRes()), fontSize = 12.sp, color = colors.text2)
                        Text(ov.netPositionFormatted, fontSize = 24.sp, fontWeight = FontWeight.Bold, color = if (ov.netPositive) colors.positive else colors.negative)
                    }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(S.Splits.owedToYouAmt(sRes(), ov.owedFormatted), fontSize = 11.sp, color = colors.text2)
                        Text(S.Splits.youOweAmt(sRes(), ov.oweFormatted), fontSize = 11.sp, color = colors.text2)
                    }
                }
            }

            // Web renders this ABOVE the tabs on /friends: a payment waiting on
            // your confirmation is not a groups-or-friends question, it is a
            // thing to answer before anything else on the screen means what it
            // says. It draws nothing when there is nothing pending.
            PendingSettlementsCard(viewModel)

            TabRow(selectedTabIndex = tab, containerColor = colors.bg, contentColor = colors.accent) {
                Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text(S.Splits.groupsAndTrips(sRes())) })
                Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text(S.Splits.sectionsFriends(sRes())) })
            }

            when {
                !loaded -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                tab == 0 && groups.isEmpty() -> EmptyState(colors.text2, "No groups yet", "Create a group to start splitting expenses with friends or on a trip.")
                tab == 1 && friends.isEmpty() -> EmptyState(colors.text2, "No balances yet", "Once you split an expense with someone, they'll show up here.")
                tab == 0 -> LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(groups, key = { it.id }) { g ->
                        GroupTile(g, colors) { onOpenGroup(g.id) }
                    }
                }
                else -> LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    item { FriendInsightsSection(viewModel) }
                    items(friends, key = { it.id }) { f ->
                        // Web opens a PERSON sheet here, not the direct group.
                        // The balance is a cross-group figure, so the group is
                        // the wrong container for it -- and jumping straight
                        // into one group hid every other group's share of the
                        // same debt, which is the bug this replaces.
                        FriendRow(f, colors) { person = f }
                    }
                }
            }
        }
    }

    if (showCreate) {
        CreateGroupSheet(viewModel = viewModel, onDismiss = { showCreate = false }, onCreated = { id -> showCreate = false; onOpenGroup(id) })
    }

    person?.let { p ->
        PersonSheet(
            person = p,
            viewModel = viewModel,
            onSettleUp = {
                person = null
                viewModel.openOrCreateDirectGroup(p.id, baseCurrencyNow()) { id -> id?.let(onOpenGroup) }
            },
            onDismiss = { person = null; viewModel.clearPersonLedger() },
        )
    }
}

@Composable
private fun GroupTile(g: SplitGroupUiModel, colors: com.sanvya.app.theme.SanvyaColors, onClick: () -> Unit) {
    Card(
        onClick = onClick,
        colors = CardDefaults.cardColors(containerColor = colors.surface),
        shape = RoundedCornerShape(SanvyaRadius.radiusLg),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(g.name, fontWeight = FontWeight.Bold, fontSize = 16.sp, color = colors.text)
                    Text(
                        g.kind.replaceFirstChar { it.uppercase() },
                        fontSize = 10.sp, fontWeight = FontWeight.Medium, color = colors.text2,
                        modifier = Modifier.background(colors.surface2, RoundedCornerShape(6.dp)).padding(horizontal = 6.dp, vertical = 2.dp),
                    )
                }
                Text("${g.memberCount} members", fontSize = 11.sp, color = colors.text2)
            }
            Text(g.netBalanceFormatted, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = if (g.net == 0L) colors.text2 else if (g.isOwed) colors.positive else colors.negative)
        }
    }
}

@Composable
private fun FriendRow(f: FriendEdgeUiModel, colors: com.sanvya.app.theme.SanvyaColors, onClick: () -> Unit) {
    val name = f.name ?: S.Payments.someone(sRes())
    Row(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(SanvyaRadius.radiusLg))
            .background(colors.surface).clickable(onClick = onClick).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            Modifier.size(38.dp).clip(RoundedCornerShape(50)).background(colors.forest),
            contentAlignment = Alignment.Center,
        ) { Text(initials(name), color = colors.surface, fontWeight = FontWeight.Bold, fontSize = 14.sp) }
        Column(Modifier.weight(1f)) {
            Text(name, fontWeight = FontWeight.Bold, fontSize = 15.sp, color = colors.text)
            Text(if (f.isOwed) S.Splits.sectionsOwesYou(sRes()) else S.Splits.sectionsYouOwe(sRes()), fontSize = 12.sp, color = if (f.isOwed) colors.positive else colors.negative)
        }
        Text(f.balanceFormatted, fontWeight = FontWeight.Bold, fontSize = 15.sp, color = if (f.isOwed) colors.positive else colors.negative)
    }
}

@Composable
private fun EmptyState(mutedColor: androidx.compose.ui.graphics.Color, title: String, body: String) {
    Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title, fontWeight = FontWeight.Bold, fontSize = 17.sp)
            Text(body, fontSize = 13.sp, color = mutedColor, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        }
    }
}

private fun initials(name: String): String {
    val parts = name.trim().split(Regex("\\s+")).filter { it.isNotBlank() }
    return if (parts.size >= 2) "${parts[0].first()}${parts[1].first()}".uppercase()
    else name.trim().take(2).uppercase().ifEmpty { "?" }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CreateGroupSheet(viewModel: SplitsViewModel, onDismiss: () -> Unit, onCreated: (String) -> Unit) {
    val colors = LocalSanvyaColors.current
    val connections by viewModel.connections.collectAsState()
    var name by remember { mutableStateOf("") }
    var kind by remember { mutableStateOf("group") }
    var currency by remember { mutableStateOf(FormOptions.DEFAULT_CURRENCY) }
    var selected by remember { mutableStateOf(setOf<String>()) }
    var start by remember { mutableStateOf("") }
    var end by remember { mutableStateOf("") }
    var auto by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    val canAuto = start.isNotBlank() && end.isNotBlank()

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = colors.surface) {
        Column(Modifier.padding(20.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(S.Splits.newGroupCta(sRes()), fontWeight = FontWeight.Bold, fontSize = 18.sp, color = colors.text)
            OutlinedTextField(name, { name = it }, label = { Text(S.Cashflow.name(sRes())) }, singleLine = true, modifier = Modifier.fillMaxWidth())

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("group" to S.Splits.kindGroup(sRes()), "trip" to S.Splits.kindTrip(sRes())).forEach { (value, label) ->
                    FilterChip(selected = kind == value, onClick = { kind = value }, label = { Text(label) })
                }
            }

            Text(S.Accounts.currency(sRes()), fontSize = 12.sp, color = colors.text2)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FormOptions.currencies.forEach { c ->
                    FilterChip(selected = currency == c, onClick = { currency = c }, label = { Text(c) })
                }
            }

            Text("Add members", fontSize = 12.sp, color = colors.text2)
            if (connections.isEmpty()) {
                Text("No connections yet -- you can add members later.", fontSize = 12.sp, color = colors.text2)
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    connections.forEach { c ->
                        Row(
                            Modifier.fillMaxWidth().clickable { selected = if (c.id in selected) selected - c.id else selected + c.id }.padding(vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Checkbox(checked = c.id in selected, onCheckedChange = { checked -> selected = if (checked) selected + c.id else selected - c.id })
                            Text(c.name, color = colors.text)
                        }
                    }
                }
            }

            // Web's date range and its auto-split checkbox. Without them a trip
            // created on mobile could never auto-split -- the flag is only
            // settable against a range, and the range was only settable from
            // the edit sheet, which most users never open.
            Text(S.Groups.datesOptional(sRes()), fontSize = 12.sp, color = colors.text2)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                // Web clamps the end date up when a later start is picked;
                // an inverted range matches no transaction at all.
                DateField(value = start, onValueChange = { start = it; if (end.isNotBlank() && it > end) end = it }, modifier = Modifier.weight(1f))
                DateField(value = end, onValueChange = { end = it }, modifier = Modifier.weight(1f))
            }
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Checkbox(checked = canAuto && auto, onCheckedChange = { auto = it }, enabled = canAuto)
                Text(
                    S.Groups.autoSplitCreate(sRes(), if (kind == "trip") S.Splits.kindTrip(sRes()) else S.Splits.kindGroup(sRes())),
                    fontSize = 14.sp,
                    color = if (canAuto) colors.text else colors.text2,
                    modifier = Modifier.padding(start = 8.dp),
                )
            }

            error?.let { Text(it, fontSize = 12.sp, color = colors.negative) }

            Button(
                onClick = {
                    saving = true
                    viewModel.createGroup(name.trim(), kind, currency, selected.toList(), start, end, auto) { id ->
                        saving = false
                        if (id != null) onCreated(id) else error = "Couldn't create the group."
                    }
                },
                enabled = name.isNotBlank() && !saving,
                modifier = Modifier.fillMaxWidth(),
            ) { Text(if (saving) S.Groups.creating(sRes()) else "Create group") }
        }
    }
}

/**
 * One person's balance with you, and the transactions behind it.
 *
 * Ported from the person Modal in `apps/web/app/friends/page.tsx`. Two things
 * about its shape are deliberate and were copied rather than improved on:
 *
 * The total is at the TOP and large. The sheet's job is "how much, and settle
 * it" -- everything else is supporting evidence.
 *
 * The itemised lines are BEHIND A BUTTON, not shown by default. Web's own
 * comment says why: a wall of line items pushed the two actions below the fold
 * and made the sheet read as a statement. They are one tap away when you want
 * to check, which is exactly how often you want them.
 *
 * The lines come from `personLedger()`, which existed on both repositories with
 * no caller -- so until now the app could tell you THAT you owed someone and
 * not one line of WHY.
 *
 * **Remind** is web's second button, and it is a nudge, not a notification: it
 * hands the sentence to the system share sheet and lets the user pick who
 * carries it. Deliberately TEXT ONLY -- there is no `FileProvider` in this
 * app's manifest, so an `ACTION_SEND` with a stream URI would be refused by the
 * receiving app, and the manifest is a shared file this screen has no business
 * editing (the same call `StatementsScreen`'s share makes).
 *
 * Mirrors iOS's PersonSheet in SplitsView.swift.
 */
@Composable
private fun PersonSheet(
    person: FriendEdgeUiModel,
    viewModel: SplitsViewModel,
    onSettleUp: () -> Unit,
    onDismiss: () -> Unit,
) {
    val res = sRes()
    val colors = LocalSanvyaColors.current
    val context = LocalContext.current
    val lines by viewModel.personLines.collectAsState()
    var showAllLines by remember { mutableStateOf(false) }

    LaunchedEffect(person.id) { viewModel.loadPersonLedger(person.id) }

    val personName = person.name ?: S.Payments.someone(sRes())
    SanvyaModal(open = true, onClose = onDismiss, label = personName) {
        Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(personName, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = colors.text)
                if (person.net != 0L) {
                    Text(
                        if (person.net > 0) S.Splits.owesYouInline(res) else S.Splits.youOweInline(res),
                        fontSize = 14.sp,
                        color = if (person.net > 0) colors.positive else colors.negative,
                    )
                }
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(colors.surface2)
                    .padding(horizontal = 16.dp, vertical = 14.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Bottom,
            ) {
                Text(
                    if (person.net > 0) S.Splits.totalOwedToYou(res) else S.Splits.totalYouOwe(res),
                    fontSize = 12.5.sp,
                    color = colors.text2,
                )
                Text(
                    person.balanceFormatted,
                    fontSize = 30.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (person.net > 0) colors.positive else colors.negative,
                )
            }

            if (lines.isNotEmpty() && !showAllLines) {
                OutlinedButton(
                    onClick = { showAllLines = true },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(S.Splits.viewLines(res, lines.size))
                }
            }

            if (lines.isNotEmpty() && showAllLines) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    lines.forEach { line ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text(line.description, fontSize = 14.sp, color = colors.text, maxLines = 1)
                                if (line.date.isNotEmpty()) {
                                    Text(
                                        dayMonthLabel(line.date) +
                                            if (line.kind == "settlement") " · " + S.Splits.settlementTag(res) else "",
                                        fontSize = 11.5.sp,
                                        color = colors.text2,
                                    )
                                }
                            }
                            Text(
                                (if (line.net > 0) "+" else "−") +
                                    formatMoney(kotlin.math.abs(line.net), baseCurrencyNow()),
                                fontSize = 14.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = if (line.net > 0) colors.positive else colors.negative,
                            )
                        }
                    }
                    TextButton(onClick = { showAllLines = false }) { Text(S.Splits.hideLines(res)) }
                }
            }

            // Every string the click handler needs is read HERE, not inside
            // it: `sRes()` is @Composable and an onClick lambda is not a
            // composable scope, so resolving them lazily would not compile.
            val remindLabel = S.Splits.remind(res)
            val remindLine = if (person.net > 0) {
                S.Splits.remindOwed(res, personName, person.balanceFormatted)
            } else {
                S.Splits.remindOwe(res, personName, person.balanceFormatted)
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Button(onClick = onSettleUp, modifier = Modifier.weight(1f)) {
                    Text(S.Splits.settleUp(res))
                }
                OutlinedButton(onClick = {
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, remindLine)
                    }
                    context.startActivity(Intent.createChooser(intent, remindLabel))
                }) {
                    Text(remindLabel)
                }
            }
        }
    }
}

/**
 * Behavioural patterns across the groups you share.
 *
 * Ported from `FriendInsights` in `apps/web/app/friends/page.tsx`. The ranking
 * and its evidence thresholds are Domain's `pickFriendInsights`; the repository
 * has returned them since P2.5 and nothing read them, so this is a render of
 * work that was already being done and thrown away.
 *
 * Renders nothing when there is nothing to say -- which is most of the time
 * early on, and deliberately so. The footnote explains why: a pattern asserted
 * from one dinner is not a pattern, and the thresholds enforce that.
 *
 * Mirrors iOS's FriendInsightsSection in SplitsView.swift.
 */
@Composable
private fun FriendInsightsSection(viewModel: SplitsViewModel) {
    val res = sRes()
    val colors = LocalSanvyaColors.current
    val insights by viewModel.insights.collectAsState()
    val friends by viewModel.friends.collectAsState()
    if (insights.isEmpty()) return

    Column(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            S.Splits.sectionsInsights(res),
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            color = colors.text2,
        )
        insights.forEach { insight ->
            val tone = insightTone(insight.key, colors)
            Card(colors = CardDefaults.cardColors(containerColor = colors.surface)) {
                Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        insightLabel(res, insight.key).uppercase(),
                        fontSize = 11.5.sp,
                        fontWeight = FontWeight.Bold,
                        color = colors.text2,
                    )
                    Text(
                        friends.find { it.id == insight.friendId }?.name ?: insight.friendId.take(8),
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = colors.text,
                        maxLines = 1,
                    )
                    Text(insightValue(res, insight), fontSize = 13.sp, color = tone)
                }
            }
        }
        Text(S.Splits.insightsFootnote(res), fontSize = 11.5.sp, color = colors.text2)
    }
}

private fun insightLabel(res: android.content.res.Resources, key: String): String = when (key) {
    "biggest_lender" -> S.Splits.insightsBiggestLender(res)
    "owes_you_most" -> S.Splits.insightsOwesYouMost(res)
    "you_owe_most" -> S.Splits.insightsYouOweMost(res)
    "always_owes" -> S.Splits.insightsAlwaysOwes(res)
    "always_owed" -> S.Splits.insightsAlwaysOwed(res)
    "fastest_settler" -> S.Splits.insightsFastestSettler(res)
    else -> S.Splits.insightsSlowestSettler(res)
}

/**
 * The value line, whose UNIT depends on the key.
 *
 * Three different things share this slot on web: a number of days, a number of
 * groups, and an amount of money. Formatting all three as money -- which is
 * what a naive port does, since every other number on this screen is money --
 * would read "Settles up quickest: ₹3.00".
 */
private fun insightValue(res: android.content.res.Resources, insight: FriendInsight): String = when (insight.key) {
    "fastest_settler", "slowest_settler" -> S.Splits.insightsDays(res, jsRound(insight.value).toInt())
    "always_owes", "always_owed" -> S.Splits.insightsGroups(res, insight.value.toInt())
    else -> formatMoney(insight.value.toLong(), baseCurrencyNow())
}

private fun insightTone(key: String, colors: com.sanvya.app.theme.SanvyaColors) = when (key) {
    "biggest_lender", "owes_you_most", "fastest_settler" -> colors.positive
    "you_owe_most" -> colors.negative
    "slowest_settler" -> colors.warning
    else -> colors.text
}
