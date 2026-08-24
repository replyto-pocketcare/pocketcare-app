package com.sanvya.app.ui.splits

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
import com.sanvya.app.ui.components.SanvyaPage

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
                        Text("Your net position", fontSize = 12.sp, color = colors.text2)
                        Text(ov.netPositionFormatted, fontSize = 24.sp, fontWeight = FontWeight.Bold, color = if (ov.netPositive) colors.positive else colors.negative)
                    }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("Owed to you: ${ov.owedFormatted}", fontSize = 11.sp, color = colors.text2)
                        Text("You owe: ${ov.oweFormatted}", fontSize = 11.sp, color = colors.text2)
                    }
                }
            }

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
                    items(friends, key = { it.id }) { f ->
                        FriendRow(f, colors) {
                            viewModel.openOrCreateDirectGroup(f.id, baseCurrencyNow()) { id -> id?.let(onOpenGroup) }
                        }
                    }
                }
            }
        }
    }

    if (showCreate) {
        CreateGroupSheet(viewModel = viewModel, onDismiss = { showCreate = false }, onCreated = { id -> showCreate = false; onOpenGroup(id) })
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
    Row(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(SanvyaRadius.radiusLg))
            .background(colors.surface).clickable(onClick = onClick).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            Modifier.size(38.dp).clip(RoundedCornerShape(50)).background(colors.forest),
            contentAlignment = Alignment.Center,
        ) { Text(initials(f.name), color = colors.surface, fontWeight = FontWeight.Bold, fontSize = 14.sp) }
        Column(Modifier.weight(1f)) {
            Text(f.name, fontWeight = FontWeight.Bold, fontSize = 15.sp, color = colors.text)
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
    var error by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }

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

            error?.let { Text(it, fontSize = 12.sp, color = colors.negative) }

            Button(
                onClick = {
                    saving = true
                    viewModel.createGroup(name.trim(), kind, currency, selected.toList()) { id ->
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
