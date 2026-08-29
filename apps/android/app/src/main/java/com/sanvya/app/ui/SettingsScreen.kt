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
// rememberSaveable is in runtime.saveable, NOT runtime — the wildcard above
// does not reach it. Its absence cascaded into 11 compile errors here,
// including a baffling one about WideNavigationRailValue.not().
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.ClipboardManager
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.data.repository.FailedWriteItem
import com.sanvya.app.domain.notifications.PushState
import com.sanvya.app.domain.notifications.pushState
import com.sanvya.app.ui.notifications.LocalNotificationPermissionRequester
import com.sanvya.app.ui.notifications.PushController
import com.sanvya.app.data.repository.StrandedRow
import com.sanvya.app.theme.*
import com.sanvya.app.ui.components.ConfirmDialog
import com.sanvya.app.ui.onboarding.OnboardingDeckScreen
import com.sanvya.app.ui.payments.PaymentHandlePanelBody
import com.sanvya.app.ui.shell.LocalShellNavigate
import com.sanvya.app.ui.security.SecurityPanelBody
import com.sanvya.app.ui.shell.SettingsSection
import com.sanvya.app.ui.shell.SettingsSectionRequest
import kotlin.math.roundToInt
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes

private val CURRENCIES = FormOptions.currencies
private val GENDERS = FormOptions.genders.map { it.value to it.label }
private val COUNTRIES = FormOptions.countries

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onNavigateBack: () -> Unit = {},
    onManageCategories: () -> Unit = {},
    onManageLabels: () -> Unit = {},
    onImportExport: () -> Unit = {},
    viewModel: SettingsViewModel = viewModel()
) {
    val scrollState = rememberScrollState()
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    // Hoisted once: several strings below are assembled inside plain (non
    // composable) lambdas -- `buildString`, `semantics` -- where `sRes()`
    // cannot be called.
    val res = sRes()
    // Web links straight to `/login` from the guest card and the sign-out
    // dialog. The nav graph hands this screen no such callback, so it asks the
    // shell, which owns navigation for every page inside it.
    val navigate = LocalShellNavigate.current

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
    val pushPermission by viewModel.pushPermission.collectAsState()
    val pushBusy by viewModel.pushBusy.collectAsState()
    val pushMessage by viewModel.pushMessage.collectAsState()
    val requestNotificationPermission = LocalNotificationPermissionRequester.current
    val pushController = remember(context) { PushController(context.applicationContext) }
    // Re-read on every entry: the user can revoke notifications from system
    // settings while the app is backgrounded, and a stale "on" switch would be
    // the last thing they see before wondering why nothing arrives.
    LaunchedEffect(Unit) { viewModel.refreshPushPermission(pushController) }

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
    var confirmReplay by rememberSaveable { mutableStateOf(false) }
    var replayOpen by rememberSaveable { mutableStateOf(false) }
    var expandedLog by rememberSaveable { mutableStateOf(false) }

    // ---- Deep link into the Problems panel -------------------------------
    //
    // Web's sync-problems banner pushes `/settings#problems` and the browser
    // scrolls the panel into view. A native route has no fragment, so the
    // shell records the request (see SettingsSectionRequest) and this screen
    // performs the scroll once it knows where the panel actually is.
    //
    // Positions are read in ROOT coordinates and differenced, rather than
    // trusting a child's offset inside a scrolling column: `viewportTop` is
    // measured before `verticalScroll` and so does not move, while `problemsTop`
    // does -- which makes `scrollState.value + (problemsTop - viewportTop)` the
    // panel's absolute offset no matter where the page is currently scrolled.
    val pendingSection by SettingsSectionRequest.pending.collectAsState()
    var viewportTop by remember { mutableStateOf(0f) }
    var problemsTop by remember { mutableStateOf<Float?>(null) }

    LaunchedEffect(pendingSection, problemsTop) {
        if (pendingSection != SettingsSection.PROBLEMS) return@LaunchedEffect
        // Null until the panel has been laid out -- and it is only laid out when
        // something is actually stuck, which is the only time the banner exists
        // to send anyone here.
        val top = problemsTop ?: return@LaunchedEffect
        scrollState.animateScrollTo(
            (scrollState.value + (top - viewportTop)).roundToInt().coerceAtLeast(0),
        )
        // One-shot: returning to Settings later must not jump the page again.
        SettingsSectionRequest.consume()
        problemsTop = null
    }

    // A request that could not be honoured -- the panel was not on screen
    // because the failed writes had already cleared -- dies with the screen
    // rather than waiting to surprise the next visit.
    DisposableEffect(Unit) {
        onDispose { SettingsSectionRequest.consume() }
    }

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
                title = { Text(S.Settings.title(sRes()), fontWeight = FontWeight.Bold) },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background)
            )
        },
        containerColor = MaterialTheme.colorScheme.background
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                // BEFORE verticalScroll on purpose: this reports the viewport,
                // which stays put, rather than the content, which moves.
                .onGloballyPositioned { viewportTop = it.localToRoot(Offset.Zero).y }
                .verticalScroll(scrollState)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // ---- Account ----
            SettingsCard(title = S.Settings.account(sRes())) {
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
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            // Web's four fragments in web's order: the lead-in,
                            // the bolded word "guest", the full stop, then the
                            // countdown -- omitted entirely when the sign-up
                            // date could not be read, rather than guessed at.
                            // There is no inline <strong> here, so the three
                            // fragments join into one sentence; the emphasis is
                            // the only thing lost and the deadline is the half
                            // that does the work.
                            val daysLeft = session?.daysLeft
                            Text(
                                buildString {
                                    append(S.Settings.guestPre(res))
                                    append(S.Settings.guestBold(res))
                                    append(S.Settings.guestDot(res))
                                    if (daysLeft != null) {
                                        append(" ")
                                        append(S.Settings.guestDelete(res, daysLeft))
                                    }
                                },
                                fontSize = 13.sp,
                                color = MaterialTheme.colorScheme.onPrimaryContainer,
                            )
                            // The way out of the warning. Both phones printed
                            // the deadline and then offered nothing to do about
                            // it; web has had this button since the card
                            // existed.
                            Button(onClick = { navigate("login") }) {
                                Text(S.Settings.createToKeep(res))
                            }
                        }
                    }
                } else {
                    Text(
                        "${S.Settings.signedInAs(res)} ${session?.email ?: "—"}",
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

                Text(S.Settings.displayName(sRes()), fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(
                        value = username,
                        onValueChange = { username = it },
                        label = { Text(S.Settings.yourName(sRes())) },
                        singleLine = true,
                        modifier = Modifier.weight(1f),
                    )
                    OutlinedButton(onClick = { viewModel.saveUsername(username) }) {
                        Text(if (usernameSaved) S.Settings.saved(sRes()) else S.Settings.save(sRes()))
                    }
                }
            }

            // ---- Appearance ----
            SettingsCard(title = S.Settings.appearance(sRes())) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    FilterChip(selected = theme == "light", onClick = { viewModel.setTheme("light") }, label = { Text(S.Settings.light(sRes())) })
                    FilterChip(selected = theme == "dark", onClick = { viewModel.setTheme("dark") }, label = { Text(S.Settings.dark(sRes())) })
                }
            }

            // ---- Privacy ----
            SettingsCard(title = S.Settings.privacy(sRes())) {
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
                    Button(onClick = { viewModel.saveProfile(gender, country) }) { Text(S.Settings.save(sRes())) }
                    profileMsg?.let { Text(it, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
            }

            // ---- Notifications ----
            //
            // The push row used to be a plain toggle that wrote `push_enabled`
            // and nothing else: no permission ask, no token, no way to send a
            // test. It was a switch that turned on a lie. Ported properly from
            // web's NotificationPanel.tsx, whose hints and test button come
            // with it.
            if (notifPrefs != null) {
                val prefs = notifPrefs!!
                val state = pushState(
                    supported = pushController.supported(),
                    permission = pushPermission,
                    prefEnabled = prefs.push_enabled == 1L,
                )
                SettingsCard(title = S.Translation.navNotifications(sRes()), subtitle = "Get alerted about bills, budgets, low balances and unusual spend.") {
                    if (state == PushState.UNSUPPORTED) {
                        Text(
                            "This device can't show notifications. In-app alerts still work.",
                            fontSize = 13.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    } else {
                        NotificationToggleRow(
                            title = if (pushBusy) "Working\u2026" else "Push notifications",
                            checked = state == PushState.ON,
                            // BLOCKED is not OFF: once Android has refused
                            // twice it will never show the prompt again, so a
                            // live switch here would be a control that can
                            // never do anything. The hint sends them to system
                            // settings instead.
                            enabled = !pushBusy && state != PushState.BLOCKED,
                            hint = when (state) {
                                PushState.BLOCKED -> "Blocked in your system settings"
                                else -> "Deliver alerts to this device"
                            },
                        ) { v ->
                            if (v) {
                                viewModel.enablePush(pushController, requestNotificationPermission)
                            } else {
                                viewModel.disablePush(pushController)
                            }
                        }
                        pushMessage?.let {
                            Text(it, fontSize = 12.5.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        TextButton(onClick = { viewModel.sendTestNotification(pushController) }) {
                            Text("Send test notification", fontSize = 13.sp, color = LocalSanvyaColors.current.accent)
                        }
                    }
                    HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                    NotificationToggleRow(
                        "Upcoming EMIs & bills", prefs.emi_due == 1L,
                        hint = "Alert ${prefs.emi_lead_days} days before due",
                    ) { v -> viewModel.updatePref { it.copy(emi_due = if (v) 1 else 0) } }
                    NotificationToggleRow(
                        "Budget limits", prefs.budget == 1L,
                        hint = "When you cross 80% and 100% of a budget",
                    ) { v -> viewModel.updatePref { it.copy(budget = if (v) 1 else 0) } }
                    NotificationToggleRow(
                        "Low balance", prefs.low_balance == 1L,
                        hint = "When an account drops below your floor",
                    ) { v -> viewModel.updatePref { it.copy(low_balance = if (v) 1 else 0) } }
                    NotificationToggleRow(
                        "Unusual transactions", prefs.outlier == 1L,
                        hint = "Large or out-of-pattern spends",
                    ) { v -> viewModel.updatePref { it.copy(outlier = if (v) 1 else 0) } }
                    HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                    Text(S.Groups.title(sRes()), fontWeight = FontWeight.Bold, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    NotificationToggleRow(
                        "Group activity", prefs.group_invite == 1L,
                        hint = "When someone joins a group or trip you're in",
                    ) { v -> viewModel.updatePref { it.copy(group_invite = if (v) 1 else 0) } }
                    NotificationToggleRow(
                        "Shared expenses", prefs.group_expense == 1L,
                        hint = "When someone adds an expense to split",
                    ) { v -> viewModel.updatePref { it.copy(group_expense = if (v) 1 else 0) } }
                }
            }

            // ---- Security & encryption ----
            //
            // Web renders <SecurityPanel /> here, between NotificationPanel and
            // the base-currency section, and the order is the order: this card
            // is about the same thing the notification card is (what leaves
            // this device), and burying it below Diagnostics would hide the
            // one control that makes notes unreadable to us.
            //
            // The heading and the intro paragraph are this card's title and
            // subtitle, which is exactly the <h2> + muted <p> web opens its
            // <section> with; the body is the four-state machine.
            SettingsCard(title = S.Security.title(res), subtitle = S.Security.intro(res)) {
                SecurityPanelBody()
            }

            // ---- Base currency ----
            SettingsCard(title = S.Settings.baseCurrency(sRes()), subtitle = "Used as the default across new accounts and reports.") {
                androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    CURRENCIES.forEach { c ->
                        FilterChip(selected = c == baseCurrency, onClick = { viewModel.setBaseCurrency(c) }, label = { Text(c) })
                    }
                }
            }

            // ---- Categories & labels ----
            //
            // Web's `#categories` section. Neither native Settings screen had
            // it, so both taxonomy screens were unreachable even once they
            // existed.
            SettingsCard(
                title = S.Settings.catsLabels(sRes()),
                subtitle = S.Settings.catsLabelsDesc(sRes()),
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedButton(onClick = onManageCategories) {
                        Text(S.Settings.manageCategories(sRes()))
                    }
                    OutlinedButton(onClick = onManageLabels) {
                        Text(S.Settings.manageLabels(sRes()))
                    }
                }
            }

            // ---- Import & export ----
            //
            // Web's `#data` section. Neither native Settings screen had it, so
            // the screen was unreachable even once it existed.
            SettingsCard(title = S.Data.title(sRes()), subtitle = S.Data.introPre(sRes())) {
                OutlinedButton(onClick = onImportExport) {
                    Text(S.Data.exportBtn(sRes()))
                }
            }

            // ---- Your UPI ID ----
            //
            // Web renders <PaymentHandlePanel /> immediately after the `#data`
            // section and before the sync panels, and the position is the point:
            // it is a thing you set up once, not a thing that goes wrong. The
            // heading and the intro are this card's title and subtitle, exactly
            // as web's <strong> + muted <p> open its <section>.
            SettingsCard(
                title = S.Payments.settingsTitle(res),
                subtitle = S.Payments.settingsIntro(res),
            ) {
                PaymentHandlePanelBody()
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
                    // The anchor the sync-problems banner scrolls to -- web's
                    // `id="problems"`, which its `/settings#problems` link lands
                    // on. Measured rather than assumed: the panels above it come
                    // and go (the notification card is absent until prefs load),
                    // so a fixed offset would be wrong most of the time.
                    // Measured ONCE, and only while a jump is pending. Writing
                    // on every layout pass would recompose this whole screen on
                    // every scroll frame, and re-writing it mid-animation would
                    // restart the animation that is moving it.
                    modifier = Modifier.onGloballyPositioned {
                        if (pendingSection != null && problemsTop == null) {
                            problemsTop = it.localToRoot(Offset.Zero).y
                        }
                    },
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
            SettingsCard(title = S.Settings.help(res)) {
                OutlinedButton(onClick = {
                    val intent = Intent(Intent.ACTION_SENDTO).apply {
                        data = android.net.Uri.parse("mailto:support@sanvya.app")
                    }
                    try { context.startActivity(intent) } catch (_: Exception) { /* no mail app */ }
                }) { Text(S.Settings.contactSupport(res)) }
                // Web's "Replay the intro". Four translated strings for it have
                // existed in the catalogue since the deck was ported and nothing
                // rendered any of them.
                OutlinedButton(onClick = { confirmReplay = true }) {
                    Text(S.Settings.replayIntro(res))
                }
                Text(
                    S.Settings.helpNote(res),
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // ---- Sign out / delete ----
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.Center,
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    OutlinedButton(onClick = { confirmSignout = true }) { Text(S.Settings.signoutTitle(sRes())) }
                    OutlinedButton(
                        onClick = { confirmDelete = true },
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    ) { Text(S.Settings.deleteAccount(sRes())) }
                }
            }
        }
    }

    if (confirmSignout) {
        AlertDialog(
            onDismissRequest = { confirmSignout = false },
            title = { Text(S.Settings.signoutTitle(res)) },
            text = {
                Text(
                    if (session?.isGuest == true) {
                        S.Settings.guestSignoutWarn(res)
                    } else {
                        S.Settings.signoutRestore(res)
                    },
                )
            },
            confirmButton = {
                TextButton(onClick = { confirmSignout = false; viewModel.signOut() }) {
                    Text(S.Settings.signOutAnyway(res), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    TextButton(onClick = { confirmSignout = false }) { Text(S.Settings.cancel(res)) }
                    // Web puts "Create account" beside Cancel for a guest, and
                    // it is the whole point of the warning above it: signing out
                    // as a guest is a delete, so the dialog has to offer the one
                    // action that prevents it.
                    if (session?.isGuest == true) {
                        TextButton(onClick = { confirmSignout = false; navigate("login") }) {
                            Text(S.Settings.createAccount(res))
                        }
                    }
                }
            },
        )
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { if (!deleting) confirmDelete = false },
            title = { Text(S.Settings.deleteAccount(sRes()), color = MaterialTheme.colorScheme.error) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(S.Settings.deleteBody(res))
                    deleteError?.let { Text(it, color = MaterialTheme.colorScheme.error, fontSize = 13.sp) }
                }
            },
            confirmButton = {
                TextButton(enabled = !deleting, onClick = { viewModel.deleteAccount() }) {
                    Text(if (deleting) S.Settings.deleting(sRes()) else S.Settings.deleteEverything(sRes()), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(enabled = !deleting, onClick = { confirmDelete = false }) { Text(S.Settings.cancel(res)) } },
        )
    }

    if (confirmReplay) {
        // `danger = false`: web passes exactly that, because replaying the intro
        // destroys nothing.
        ConfirmDialog(
            title = S.Settings.replayTitle(res),
            message = S.Settings.replayMsg(res),
            confirmLabel = S.Settings.replayConfirm(res),
            cancelLabel = S.Settings.cancel(res),
            danger = false,
            onConfirm = { confirmReplay = false; replayOpen = true },
            onDismiss = { confirmReplay = false },
        )
    }

    /*
     * The deck itself, shown here rather than by clearing `onboardingSeen` and
     * signing out.
     *
     * Web can do it the other way round because `signOut()` ends in
     * `window.location.href = "/onboarding"` -- a full reload, after which the
     * auth gate re-reads localStorage and the deck is what a signed-out visitor
     * meets. Neither phone reloads: both gates read the flag ONCE, into
     * `rememberSaveable` / `@State` at launch (MainActivity.kt, SanvyaApp.swift),
     * so clearing it after that point changes nothing until the next cold start
     * and the user would be dropped on the login form having been promised the
     * welcome screens.
     *
     * So the deck is presented and the sign-out happens on the way OUT of it,
     * on whichever of its three exits is taken. The screens the user sees, and
     * the state they end in -- signed out, at the login form -- are web's.
     */
    if (replayOpen) {
        Dialog(
            onDismissRequest = { replayOpen = false },
            // The platform default caps a dialog well below full width, and the
            // deck is a full-screen experience, not a card.
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            OnboardingDeckScreen(
                onDone = {
                    replayOpen = false
                    viewModel.signOut()
                },
            )
        }
    }
}

@Composable
private fun SettingsCard(
    title: String,
    subtitle: String? = null,
    borderColor: androidx.compose.ui.graphics.Color? = null,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    Card(
        modifier = modifier.fillMaxWidth(),
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
fun NotificationToggleRow(
    title: String,
    checked: Boolean,
    /**
     * The line under the label. Web has one on every row and both phones had
     * none, which turned "Upcoming EMIs & bills" into a switch whose meaning
     * you had to guess — the lead time it actually uses was invisible.
     */
    hint: String? = null,
    enabled: Boolean = true,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.Medium, fontSize = 15.sp, color = MaterialTheme.colorScheme.onSurface)
            if (hint != null) {
                Text(hint, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Switch(checked = checked, onCheckedChange = onCheckedChange, enabled = enabled)
    }
}
