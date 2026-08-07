package com.sanvya.app.ui

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.ClipboardManager
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.data.repository.FailedWriteItem
import com.sanvya.app.data.repository.StrandedRow
import com.sanvya.app.theme.*

private val CURRENCIES = listOf("INR", "USD", "EUR", "GBP", "JPY", "AUD", "CAD", "SGD", "AED")
private val GENDERS = listOf("" to "Not specified", "female" to "Female", "male" to "Male", "non-binary" to "Non-binary", "prefer not to say" to "Prefer not to say")
private val COUNTRIES = listOf("", "IN", "US", "GB", "CA", "AU", "SG", "AE", "DE", "FR", "NL", "JP", "BR", "ZA", "NG", "KE", "Other")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onOpenDrawer: () -> Unit = {},
    onNavigateBack: () -> Unit = {},
    viewModel: SettingsViewModel = viewModel()
) {
    val scrollState = rememberScrollState()
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current

    val amountsHidden by Prefs.amountsHidden.collectAsState()
    val notifPrefs by viewModel.notifPrefs.collectAsState()
    val session by viewModel.session.collectAsState()
    val usernameSaved by viewModel.usernameSaved.collectAsState()
    val entitlement by viewModel.entitlement.collectAsState()
    val theme by viewModel.theme.collectAsState()
    val baseCurrency by viewModel.baseCurrency.collectAsState()
    val profileGender by viewModel.profileGender.collectAsState()
    val profileCountry by viewModel.profileCountry.collectAsState()
    val profileMsg by viewModel.profileMsg.collectAsState()
    val syncConnected by viewModel.syncConnected.collectAsState()
    val syncLastSyncedAt by viewModel.syncLastSyncedAt.collectAsState()
    val diagnosticsEntries by viewModel.diagnosticsEntries.collectAsState()
    val queueOps by viewModel.queueOps.collectAsState()
    val queueDepth by viewModel.queueDepth.collectAsState()
    val discardingStuck by viewModel.discardingStuck.collectAsState()
    val failedWrites by viewModel.failedWrites.collectAsState()
    val problemsBusy by viewModel.problemsBusy.collectAsState()
    val repairStage by viewModel.repairStage.collectAsState()
    val strandedRows by viewModel.strandedRows.collectAsState()
    val repairUnchecked by viewModel.repairUnchecked.collectAsState()
    val repairUploaded by viewModel.repairUploaded.collectAsState()
    val repairFailed by viewModel.repairFailed.collectAsState()
    val deleting by viewModel.deleting.collectAsState()
    val deleteError by viewModel.deleteError.collectAsState()

    var username by rememberSaveable { mutableStateOf("") }
    var confirmSignout by rememberSaveable { mutableStateOf(false) }
    var confirmDelete by rememberSaveable { mutableStateOf(false) }
    var expandedLog by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(session?.username) {
        session?.username?.let { if (username.isEmpty()) username = it }
    }
    LaunchedEffect(usernameSaved) {
        if (usernameSaved) {
            kotlinx.coroutines.delay(1500)
            viewModel.clearUsernameSaved()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onOpenDrawer) {
                        Icon(imageVector = Icons.Default.Menu, contentDescription = "Open Drawer")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background)
            )
        },
        containerColor = MaterialTheme.colorScheme.background
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(scrollState)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // ---- Account ----
            SettingsCard(title = "Account") {
                if (session?.isGuest == true) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 4.dp),
                    ) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(MaterialTheme.colorScheme.primaryContainer, RoundedCornerShape(10.dp))
                                .padding(12.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Text(
                                "You're using Sanvya as a guest.${session?.daysLeft?.let { " Your data will be deleted in $it day${if (it == 1) "" else "s"} unless you create an account." } ?: ""}",
                                fontSize = 13.sp,
                                color = MaterialTheme.colorScheme.onPrimaryContainer,
                            )
                        }
                    }
                } else {
                    Text(
                        "Signed in as ${session?.email ?: "—"}",
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Box(
                        Modifier
                            .size(8.dp)
                            .background(if (syncConnected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error, androidx.compose.foundation.shape.CircleShape)
                    )
                    Text(
                        if (syncConnected) "Synced${syncLastSyncedAt?.let { " · last $it" } ?: ""}" else "Not connected",
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                Text("Display name", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(
                        value = username,
                        onValueChange = { username = it },
                        label = { Text("Your name") },
                        singleLine = true,
                        modifier = Modifier.weight(1f),
                    )
                    OutlinedButton(onClick = { viewModel.saveUsername(username) }) {
                        Text(if (usernameSaved) "Saved" else "Save")
                    }
                }
            }

            // ---- Appearance ----
            SettingsCard(title = "Appearance") {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    FilterChip(selected = theme == "light", onClick = { viewModel.setTheme("light") }, label = { Text("Light") })
                    FilterChip(selected = theme == "dark", onClick = { viewModel.setTheme("dark") }, label = { Text("Dark") })
                }
            }

            // ---- Privacy ----
            SettingsCard(title = "Privacy") {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Hide Amounts", fontWeight = FontWeight.Medium, fontSize = 15.sp, color = MaterialTheme.colorScheme.onSurface)
                        Text("Mask balances and transaction amounts", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Switch(checked = amountsHidden, onCheckedChange = { Prefs.setAmountsHidden(it) })
                }
            }

            // ---- About you (optional traits) ----
            SettingsCard(title = "About you", subtitle = "Optional. Helps us tailor offers and beta invites. Private.") {
                var gender by rememberSaveable(profileGender) { mutableStateOf(profileGender) }
                var country by rememberSaveable(profileCountry) { mutableStateOf(profileCountry) }
                var genderMenu by remember { mutableStateOf(false) }
                var countryMenu by remember { mutableStateOf(false) }

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(modifier = Modifier.weight(1f)) {
                        OutlinedButton(onClick = { genderMenu = true }, modifier = Modifier.fillMaxWidth()) {
                            Text(GENDERS.firstOrNull { it.first == gender }?.second ?: "Not specified")
                        }
                        DropdownMenu(expanded = genderMenu, onDismissRequest = { genderMenu = false }) {
                            GENDERS.forEach { (v, label) ->
                                DropdownMenuItem(text = { Text(label) }, onClick = { gender = v; genderMenu = false })
                            }
                        }
                    }
                    Box(modifier = Modifier.weight(1f)) {
                        OutlinedButton(onClick = { countryMenu = true }, modifier = Modifier.fillMaxWidth()) {
                            Text(country.ifEmpty { "Not specified" })
                        }
                        DropdownMenu(expanded = countryMenu, onDismissRequest = { countryMenu = false }) {
                            COUNTRIES.forEach { c ->
                                DropdownMenuItem(text = { Text(c.ifEmpty { "Not specified" }) }, onClick = { country = c; countryMenu = false })
                            }
                        }
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Button(onClick = { viewModel.saveProfile(gender, country) }) { Text("Save") }
                    profileMsg?.let { Text(it, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
            }

            // ---- Notifications (existing) ----
            if (notifPrefs != null) {
                SettingsCard(title = "Notifications", subtitle = "Get alerted about bills, budgets, low balances and unusual spend.") {
                    NotificationToggleRow("Push notifications", notifPrefs!!.push_enabled == 1L) { v -> viewModel.updatePref { it.copy(push_enabled = if (v) 1 else 0) } }
                    NotificationToggleRow("Upcoming EMIs & bills", notifPrefs!!.emi_due == 1L) { v -> viewModel.updatePref { it.copy(emi_due = if (v) 1 else 0) } }
                    NotificationToggleRow("Budget limits", notifPrefs!!.budget == 1L) { v -> viewModel.updatePref { it.copy(budget = if (v) 1 else 0) } }
                    NotificationToggleRow("Low balance", notifPrefs!!.low_balance == 1L) { v -> viewModel.updatePref { it.copy(low_balance = if (v) 1 else 0) } }
                    NotificationToggleRow("Unusual transactions", notifPrefs!!.outlier == 1L) { v -> viewModel.updatePref { it.copy(outlier = if (v) 1 else 0) } }
                    HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                    Text("Groups & trips", fontWeight = FontWeight.Bold, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    NotificationToggleRow("Group activity", notifPrefs!!.group_invite == 1L) { v -> viewModel.updatePref { it.copy(group_invite = if (v) 1 else 0) } }
                    NotificationToggleRow("Shared expenses", notifPrefs!!.group_expense == 1L) { v -> viewModel.updatePref { it.copy(group_expense = if (v) 1 else 0) } }
                }
            }

            // ---- Base currency ----
            SettingsCard(title = "Base Currency", subtitle = "Used as the default across new accounts and reports.") {
                androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    CURRENCIES.forEach { c ->
                        FilterChip(selected = c == baseCurrency, onClick = { viewModel.setBaseCurrency(c) }, label = { Text(c) })
                    }
                }
            }

            // ---- Plan & billing ----
            SettingsCard(title = "Plan & Billing") {
                Text(
                    "You're on the ${entitlement.tier.replaceFirstChar { it.uppercase() }} plan.",
                    fontSize = 14.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Button(
                    onClick = { /* No native in-app-purchase flow yet -- see settings.md */ },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(if (entitlement.isPaid) "Manage Plan" else "Upgrade to Premium", fontWeight = FontWeight.Bold)
                }
            }

            // ---- Problems syncing (dead-letter queue; renders nothing when empty) ----
            if (failedWrites.isNotEmpty()) {
                SettingsCard(
                    title = "Problems syncing",
                    subtitle = "${failedWrites.size} change${if (failedWrites.size == 1) "" else "s"} couldn't be saved to the server. Still on this device — nothing has been lost.",
                    borderColor = MaterialTheme.colorScheme.error,
                ) {
                    failedWrites.forEach { item -> FailedWriteRow(item, problemsBusy, viewModel, clipboard) }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = { viewModel.retryAllFailedWrites() }, enabled = problemsBusy == null) {
                            Text(if (problemsBusy == "all") "Trying…" else "Try all ${failedWrites.size} again")
                        }
                        OutlinedButton(onClick = { clipboard.setText(AnnotatedString(viewModel.exportFailedWritesJson())) }) {
                            Text("Copy a copy of everything")
                        }
                    }
                }
            }

            // ---- Check for unsynced data ----
            SettingsCard(title = "Check for unsynced data", subtitle = "Compares this device against the server and re-uploads anything that never made it. Safe to run any time.") {
                RepairSection(repairStage, strandedRows, repairUnchecked, repairUploaded, repairFailed, viewModel, clipboard)
            }

            // ---- Diagnostics ----
            SettingsCard(title = "Diagnostics", subtitle = "If something isn't working, share this with support. Amounts, names and contact details are removed automatically.") {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    DiagStat("Status", if (syncConnected) "Connected" else "Not connected")
                    DiagStat("Waiting to upload", queueDepth?.toString() ?: "—", warn = (queueDepth ?: 0) > 0)
                    DiagStat("Errors logged", diagnosticsEntries.count { it.level == "error" }.toString(), warn = diagnosticsEntries.any { it.level == "error" })
                }
                val stuck = queueOps.filter { it.orphaned }
                if (stuck.isNotEmpty()) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(MaterialTheme.colorScheme.errorContainer, RoundedCornerShape(10.dp))
                            .padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text("${stuck.size} change${if (stuck.size == 1) "" else "s"} can't be saved", fontWeight = FontWeight.Bold, fontSize = 13.5.sp, color = MaterialTheme.colorScheme.onErrorContainer)
                        Text(
                            "These refer to something that no longer exists, so they'll never upload — and they're blocking everything queued behind them.",
                            fontSize = 12.sp, color = MaterialTheme.colorScheme.onErrorContainer,
                        )
                        Button(onClick = { viewModel.discardStuck() }, enabled = !discardingStuck) {
                            Text(if (discardingStuck) "Working…" else "Discard ${stuck.size} stuck change${if (stuck.size == 1) "" else "s"}")
                        }
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = {
                        val text = viewModel.diagnosticsShareText()
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, text)
                        }
                        context.startActivity(Intent.createChooser(intent, "Share diagnostics"))
                    }) { Text("Share diagnostics") }
                    OutlinedButton(onClick = { expandedLog = !expandedLog }) {
                        Text(if (expandedLog) "Hide log" else "Show log (${diagnosticsEntries.size})")
                    }
                }
                if (expandedLog) {
                    val logText = if (diagnosticsEntries.isEmpty()) "Nothing logged yet — that's a good sign." else
                        diagnosticsEntries.reversed().joinToString("\n") { "${it.level.uppercase()} [${it.scope}] ${it.message}" }
                    Text(
                        logText,
                        fontSize = 11.sp,
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(8.dp))
                            .padding(10.dp),
                    )
                }
            }

            // ---- Help & support ----
            SettingsCard(title = "Help & Support") {
                OutlinedButton(onClick = {
                    val intent = Intent(Intent.ACTION_SENDTO).apply {
                        data = android.net.Uri.parse("mailto:support@sanvya.app")
                    }
                    try { context.startActivity(intent) } catch (_: Exception) { /* no mail app */ }
                }) { Text("Contact support") }
            }

            // ---- Sign out / delete ----
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.Center,
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    OutlinedButton(onClick = { confirmSignout = true }) { Text("Sign out") }
                    OutlinedButton(
                        onClick = { confirmDelete = true },
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    ) { Text("Delete account") }
                }
            }
        }
    }

    if (confirmSignout) {
        AlertDialog(
            onDismissRequest = { confirmSignout = false },
            title = { Text("Sign out?") },
            text = {
                Text(
                    if (session?.isGuest == true) "You're a guest — signing out deletes this device's data with nothing backed up."
                    else "You can sign back in any time to restore your data.",
                )
            },
            confirmButton = {
                TextButton(onClick = { confirmSignout = false; viewModel.signOut() }) {
                    Text("Sign out anyway", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { confirmSignout = false }) { Text("Cancel") } },
        )
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { if (!deleting) confirmDelete = false },
            title = { Text("Delete account", color = MaterialTheme.colorScheme.error) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("This permanently deletes your account and data. This can't be undone.")
                    deleteError?.let { Text(it, color = MaterialTheme.colorScheme.error, fontSize = 13.sp) }
                }
            },
            confirmButton = {
                TextButton(enabled = !deleting, onClick = { viewModel.deleteAccount() }) {
                    Text(if (deleting) "Deleting…" else "Delete everything", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(enabled = !deleting, onClick = { confirmDelete = false }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun SettingsCard(
    title: String,
    subtitle: String? = null,
    borderColor: androidx.compose.ui.graphics.Color? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(12.dp),
        border = borderColor?.let { androidx.compose.foundation.BorderStroke(1.dp, it) },
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(title, fontWeight = FontWeight.Bold, fontSize = 16.sp, color = MaterialTheme.colorScheme.onSurface)
            subtitle?.let { Text(it, fontSize = 12.5.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            content()
        }
    }
}

@Composable
private fun DiagStat(label: String, value: String, warn: Boolean = false) {
    Column(
        modifier = Modifier
            .background(if (warn) MaterialTheme.colorScheme.errorContainer else MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(10.dp))
            .padding(horizontal = 10.dp, vertical = 8.dp),
    ) {
        Text(label, fontSize = 11.5.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)
    }
}

@Composable
private fun FailedWriteRow(item: FailedWriteItem, busy: String?, viewModel: SettingsViewModel, clipboard: androidx.compose.ui.platform.ClipboardManager) {
    var confirming by remember { mutableStateOf(false) }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.errorContainer, RoundedCornerShape(10.dp))
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(item.label, fontWeight = FontWeight.Bold, fontSize = 13.5.sp, color = MaterialTheme.colorScheme.onErrorContainer)
        Text(item.explanation, fontSize = 12.5.sp, color = MaterialTheme.colorScheme.onErrorContainer)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Button(onClick = { viewModel.retryFailedWrite(item) }, enabled = busy == null) {
                Text(if (busy == item.id) "Trying…" else "Try again")
            }
            OutlinedButton(onClick = { clipboard.setText(AnnotatedString(viewModel.exportFailedWritesJson(listOf(item)))) }) { Text("Copy") }
            if (confirming) {
                OutlinedButton(
                    onClick = { viewModel.discardFailedWrite(item) },
                    enabled = busy == null,
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                ) { Text("Copy & discard") }
            } else {
                OutlinedButton(onClick = { confirming = true }) { Text("Discard") }
            }
        }
    }
}

@Composable
private fun RepairSection(
    stage: String,
    rows: List<StrandedRow>,
    unchecked: List<String>,
    uploaded: Int,
    failed: List<RepairFailure>,
    viewModel: SettingsViewModel,
    clipboard: androidx.compose.ui.platform.ClipboardManager,
) {
    when (stage) {
        "idle" -> Button(onClick = { viewModel.scanForStranded() }) { Text("Check now") }
        "scanning" -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
            Text("Comparing this device with the server…", fontSize = 13.sp)
        }
        "clean" -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Everything is synced.", fontWeight = FontWeight.Bold, fontSize = 13.5.sp)
            if (unchecked.isNotEmpty()) Text("Couldn't check: ${unchecked.joinToString(", ")}.", fontSize = 11.5.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            OutlinedButton(onClick = { viewModel.resetRepair() }) { Text("Check again") }
        }
        "found" -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("${rows.size} item${if (rows.size == 1) "" else "s"} never reached the server", fontWeight = FontWeight.Bold, fontSize = 13.5.sp)
            Text("They're safe here but aren't backed up. Save a copy, then upload them.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            rows.groupBy { it.table }.forEach { (table, items) ->
                Text("${table.replace('_', ' ')} (${items.size})", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { clipboard.setText(AnnotatedString(viewModel.exportStrandedJson())) }) { Text("Copy a copy") }
                Button(onClick = { viewModel.repairStrandedNow() }) { Text("Upload ${rows.size} item${if (rows.size == 1) "" else "s"}") }
            }
        }
        "repairing" -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
            Text("Uploading…", fontSize = 13.sp)
        }
        "done" -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Uploaded $uploaded item${if (uploaded == 1) "" else "s"}.", fontWeight = FontWeight.Bold, fontSize = 13.5.sp)
            if (failed.isNotEmpty()) {
                Text("${failed.size} still couldn't be uploaded.", fontSize = 13.sp, color = MaterialTheme.colorScheme.error)
            }
            OutlinedButton(onClick = { viewModel.resetRepair() }) { Text("Check again") }
        }
        "error" -> OutlinedButton(onClick = { viewModel.resetRepair() }) { Text("Try again") }
    }
}

@Composable
fun NotificationToggleRow(title: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, fontWeight = FontWeight.Medium, fontSize = 15.sp, color = MaterialTheme.colorScheme.onSurface)
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}
