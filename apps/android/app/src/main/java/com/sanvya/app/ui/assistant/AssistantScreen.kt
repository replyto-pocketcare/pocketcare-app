package com.sanvya.app.ui.assistant

import android.content.res.Resources
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.data.repository.parseAssistantUiPayload
import com.sanvya.app.domain.assistant.AssistantUi
import com.sanvya.app.domain.assistant.splitAssistantUi
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaColors
import com.sanvya.app.theme.SanvyaIcons
import com.sanvya.app.theme.SanvyaShape
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.Prefs
import com.sanvya.app.ui.components.ConfirmDialog
import com.sanvya.app.ui.components.Muted
import com.sanvya.app.ui.components.SanvyaArrowUpIcon
import com.sanvya.app.ui.components.SanvyaButton
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaChip
import com.sanvya.app.ui.components.SanvyaIcon
import com.sanvya.app.ui.components.SanvyaModal
import com.sanvya.app.ui.components.SanvyaPage
import com.sanvya.app.ui.components.SanvyaText
import com.sanvya.app.ui.shortDateLabel

/**
 * The assistant -- ported from `apps/web/src/assistant/AssistantChat.tsx`.
 *
 * Two views behind one route, exactly as web has them: a LANDING that starts a
 * chat or reopens a saved one, and the CHAT itself. Web keeps both in one
 * component because the model conversation, the quota and the pending
 * confirmation have to survive moving between them; so does this.
 *
 * What is NOT here, and why:
 *
 *  * **The credit-pack purchase.** Web's out-of-quota card offers three
 *    Razorpay top-ups. There is no in-app purchase flow anywhere in this app
 *    yet (Settings' own "Upgrade" button is a no-op for the same reason), so
 *    the card states the situation and stops rather than showing three buttons
 *    that cannot charge anyone. In ABSENT-BY-DECISION.
 *  * **Voice input.** `speech.ts` + `MicButton.tsx` are a separate port with
 *    its own permission story. Also in ABSENT-BY-DECISION.
 *
 * Mirrors iOS's AssistantView.swift.
 */
@Composable
fun AssistantScreen(
    onOpenHref: (String) -> Unit = {},
    onOpenHelp: () -> Unit = {},
    onOpenSettings: () -> Unit = {},
    viewModel: AssistantViewModel = viewModel(),
) {
    LaunchedEffect(Unit) { viewModel.start() }

    val res = sRes()
    val view by viewModel.view.collectAsState()
    val isPaid by viewModel.isPaid.collectAsState()
    val entitlementKnown by viewModel.entitlementKnown.collectAsState()

    // Nothing at all until the entitlement has been read once. The gate and the
    // chat are mutually exclusive, so rendering either on a guess means the
    // wrong one flashes on every open.
    if (!entitlementKnown) return

    if (!isPaid) {
        AssistantPremiumGate(res = res, onOpenSettings = onOpenSettings)
        return
    }

    if (view == "landing") {
        AssistantLanding(res = res, viewModel = viewModel, onOpenHelp = onOpenHelp)
    } else {
        AssistantChat(res = res, viewModel = viewModel, onOpenHref = onOpenHref, onOpenSettings = onOpenSettings)
    }
}

/** Web's `!isPremiumUser && !hasActiveTrial` branch. */
@Composable
private fun AssistantPremiumGate(res: Resources, onOpenSettings: () -> Unit) {
    val colors = LocalSanvyaColors.current
    SanvyaPage(title = S.Assistant.title(res)) {
        SanvyaCard(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            padding = PaddingValues(28.dp),
        ) {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                // Web draws its own stroked padlock; this is the Material
                // Symbol of the same name, already in the bundled subset.
                SanvyaIcon(SanvyaIcons.lock, size = 30.dp, tint = colors.text2)
                SanvyaText(S.Assistant.premiumFeature(res), SanvyaType.h2)
                Muted(S.Assistant.premiumBody(res))
                SanvyaButton(onClick = onOpenSettings) { SanvyaText(S.Assistant.goPremium(res), SanvyaType.button, color = Color.White) }
            }
        }
    }
}

/**
 * The quota chip -- `3 / 50 +12 credits queries`.
 *
 * Web writes `background: isOutOfQuota ? "var(--negative-ghost)" : "var(--surface-2)"`,
 * and **`--negative-ghost` is not defined anywhere in `globals.css`** -- the
 * only other use of it, in `SecurityPanel.tsx`, carries an inline fallback,
 * which says someone already knew. An undefined custom property makes the whole
 * declaration invalid, so on web the out-of-quota chip silently keeps `.chip`'s
 * own surface rather than turning red. That is reproduced here rather than
 * "fixed": the token belongs in web's stylesheet, and inventing a colour on the
 * phone would make the two clients disagree about a state the user can see.
 * Recorded in PARITY_AUDIT as a web defect.
 */
@Composable
private fun QuotaChip(res: Resources, viewModel: AssistantViewModel) {
    val quota by viewModel.quota.collectAsState()
    val q = quota ?: return
    val colors = LocalSanvyaColors.current
    val suffix = if (q.purchased > 0) S.Assistant.creditsSuffix(res, q.purchased) else ""
    Box(
        modifier = Modifier
            .clip(SanvyaShape.pill)
            .background(if (q.left <= 0) colors.surface else colors.surface2)
            .border(1.dp, colors.border, SanvyaShape.pill)
            .padding(horizontal = 8.dp, vertical = 6.dp),
    ) {
        SanvyaText(
            "${q.planLeft} / ${q.total}$suffix ${S.Assistant.queries(res)}",
            SanvyaType.chip.copy(fontSize = 11.sp),
            color = colors.text,
            maxLines = 1,
        )
    }
}

@Composable
private fun AssistantLanding(res: Resources, viewModel: AssistantViewModel, onOpenHelp: () -> Unit) {
    val colors = LocalSanvyaColors.current
    val threads by viewModel.threads.collectAsState()
    val quota by viewModel.quota.collectAsState()
    var confirmDelete by remember { mutableStateOf<String?>(null) }

    confirmDelete?.let { id ->
        ConfirmDialog(
            title = S.Assistant.deleteChatTitle(res),
            message = S.Assistant.deleteChatMsg(res),
            confirmLabel = S.Translation.commonDelete(res),
            cancelLabel = S.Translation.commonCancel(res),
            onConfirm = { viewModel.deleteThread(id); confirmDelete = null },
            onDismiss = { confirmDelete = null },
        )
    }

    SanvyaPage(
        title = S.Assistant.title(res),
        modifier = Modifier.verticalScroll(rememberScrollState()),
        action = {
            QuotaChip(res, viewModel)
            SanvyaChip(S.Assistant.help(res), active = false, onClick = onOpenHelp)
        },
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Muted(S.Assistant.landingIntro(res), style = SanvyaType.body.copy(fontSize = 13.sp))

            quota?.resetDate?.takeIf { it.isNotEmpty() }?.let {
                Muted(
                    S.Assistant.quotaResets(res, shortDateLabel(it)),
                    style = SanvyaType.body.copy(fontSize = 12.sp),
                )
            }

            SanvyaButton(onClick = { viewModel.newChat(S.Assistant.greeting(res)) }) {
                SanvyaIcon(SanvyaIcons.autoAwesome, size = 16.dp, tint = Color.White)
                SanvyaText(S.Assistant.startChat(res), SanvyaType.button, color = Color.White)
            }

            SanvyaCard(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Muted(S.Assistant.continueConversation(res), style = SanvyaType.body.copy(fontSize = 12.sp))
                    if (threads.isEmpty()) {
                        Muted(S.Assistant.noChats(res), style = SanvyaType.body.copy(fontSize = 13.sp))
                    }
                    threads.forEach { thread ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            ThreadRow(
                                title = thread.title?.takeIf { it.isNotEmpty() } ?: S.Assistant.untitledChat(res),
                                subtitle = shortDateLabel(thread.updatedAt),
                                colors = colors,
                                modifier = Modifier.weight(1f),
                                onClick = { viewModel.openThread(thread.id) },
                            )
                            SanvyaIcon(
                                SanvyaIcons.close,
                                size = 18.dp,
                                tint = colors.text2,
                                description = S.Assistant.deleteChatAria(res),
                                modifier = Modifier
                                    .clip(SanvyaShape.pill)
                                    .clickable { confirmDelete = thread.id }
                                    .padding(6.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

/** One saved chat: its title, and the day it was last touched. */
@Composable
private fun ThreadRow(
    title: String,
    subtitle: String,
    colors: SanvyaColors,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Column(
        modifier = modifier
            .clip(SanvyaShape.radiusSm)
            .border(1.dp, colors.border, SanvyaShape.radiusSm)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        SanvyaText(title, SanvyaType.body)
        SanvyaText(subtitle, SanvyaType.body.copy(fontSize = 11.sp), color = colors.text2)
    }
}

@Composable
private fun AssistantChat(
    res: Resources,
    viewModel: AssistantViewModel,
    onOpenHref: (String) -> Unit,
    onOpenSettings: () -> Unit,
) {
    val colors = LocalSanvyaColors.current
    val bubbles by viewModel.bubbles.collectAsState()
    val busy by viewModel.busy.collectAsState()
    val pendingTool by viewModel.pendingTool.collectAsState()
    val quota by viewModel.quota.collectAsState()
    val isPaid by viewModel.isPaid.collectAsState()
    val payload by viewModel.payload.collectAsState()
    val acked by Prefs.aiDisclaimerAcked.collectAsState()

    var input by remember { mutableStateOf("") }
    var payloadOpen by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()

    val outOfQuota = quota?.let { it.left <= 0 } ?: false
    val hasUserTurn = bubbles.any { it.role == "user" }
    val canSend = !busy && pendingTool == null && !outOfQuota
    val errorText: (String, String) -> String = { key, raw -> assistantErrorString(res, key, raw) }
    val send: (String) -> Unit = { text -> viewModel.send(text, errorText) }

    // The newest message stays in view. Web scrolls its `endRef` into view on
    // every change to the transcript, the busy flag or the pending card.
    LaunchedEffect(bubbles.size, busy, pendingTool) {
        val last = bubbles.size + 3
        if (last > 0) listState.animateScrollToItem(maxOf(0, last))
    }

    if (!acked) {
        SanvyaModal(open = true, onClose = { Prefs.setAiDisclaimerAcked() }) {
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                SanvyaText(S.Assistant.privacyTitle(res), SanvyaType.h2)
                Muted(S.Assistant.privacyBody(res))
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    SanvyaButton(onClick = { Prefs.setAiDisclaimerAcked() }) {
                        SanvyaText(S.Assistant.understand(res), SanvyaType.button, color = Color.White)
                    }
                }
            }
        }
    }

    Column(modifier = Modifier.fillMaxSize().imePadding()) {
        // Header: back to the thread list on the left, quota + new chat on the
        // right. Stays put while the transcript below scrolls.
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SanvyaChip(S.Assistant.chats(res), active = false, onClick = { viewModel.backToLanding() })
            Spacer(Modifier.weight(1f))
            QuotaChip(res, viewModel)
            SanvyaChip(
                S.Assistant.newChat(res),
                active = false,
                onClick = { viewModel.newChat(S.Assistant.greeting(res)) },
            )
        }

        LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxWidth().weight(1f).padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item("payload") {
                payload?.takeIf { it.isNotEmpty() }?.let { text ->
                    SanvyaCard(
                        modifier = Modifier.fillMaxWidth(),
                        padding = PaddingValues(horizontal = 14.dp, vertical = 8.dp),
                        background = colors.surface2,
                    ) {
                        Muted(
                            S.Assistant.viewData(res),
                            modifier = Modifier.fillMaxWidth().clickable { payloadOpen = !payloadOpen },
                            style = SanvyaType.body.copy(fontSize = 12.sp),
                        )
                        if (payloadOpen) {
                            Box(modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())) {
                                SanvyaText(
                                    text,
                                    SanvyaType.body.copy(fontFamily = FontFamily.Monospace, fontSize = 11.sp),
                                    color = colors.text2,
                                )
                            }
                        }
                    }
                }
            }

            items(bubbles.size, key = { bubbles[it].id }) { index ->
                val bubble = bubbles[index]
                when (bubble.role) {
                    "action" -> Muted(bubble.text, style = SanvyaType.body.copy(fontSize = 13.sp))
                    "user" -> Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        SanvyaCard(
                            modifier = Modifier.fillMaxWidth(0.85f),
                            padding = PaddingValues(horizontal = 14.dp, vertical = 10.dp),
                            background = colors.accent,
                        ) {
                            SanvyaText(bubble.text, SanvyaType.body, color = Color.White)
                        }
                    }
                    else -> AssistantBubble(
                        raw = bubble.text,
                        enabled = canSend,
                        onSend = send,
                        onOpen = onOpenHref,
                    )
                }
            }

            // The suggestion chips ride along with the greeting until the first
            // user turn, then never come back.
            item("suggestions") {
                if (!hasUserTurn) {
                    Column(
                        modifier = Modifier.fillMaxWidth(0.85f),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        S.Assistant.suggestions(res).forEach { suggestion ->
                            SuggestionChip(
                                label = suggestion,
                                enabled = canSend,
                                colors = colors,
                                onClick = { send(suggestion) },
                            )
                        }
                    }
                }
            }

            item("status") {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (busy) Muted(S.Assistant.thinking(res), style = SanvyaType.body.copy(fontSize = 13.sp))

                    if (outOfQuota) {
                        SanvyaCard(modifier = Modifier.fillMaxWidth(), background = colors.accentGhost) {
                            // Web branches on the same `isPaid` its premium gate
                            // uses, so the free copy below is unreachable there
                            // too -- kept because the branch is web's and the day
                            // the gate loosens, the right words are already here.
                            if (isPaid) {
                                SanvyaText(S.Assistant.outPaidBold(res), SanvyaType.body.copy(fontWeight = FontWeight.Bold))
                            } else {
                                SanvyaText(S.Assistant.outFreeBold(res), SanvyaType.body.copy(fontWeight = FontWeight.Bold))
                                Muted(S.Assistant.outFreeRest(res))
                                SanvyaButton(onClick = onOpenSettings) {
                                    SanvyaText(S.Assistant.seePlans(res), SanvyaType.button, color = Color.White)
                                }
                            }
                        }
                    }

                    pendingTool?.let { tool ->
                        SanvyaCard(modifier = Modifier.fillMaxWidth(), background = colors.accentGhost) {
                            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                SanvyaText(S.Assistant.confirmAction(res), SanvyaType.body.copy(fontWeight = FontWeight.Bold))
                                SanvyaText(viewModel.describePending(tool), SanvyaType.body)
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    SanvyaButton(onClick = { viewModel.resolvePending(true, errorText) }) {
                                        SanvyaText(S.Assistant.confirm(res), SanvyaType.button, color = Color.White)
                                    }
                                    SanvyaChip(
                                        S.Assistant.skip(res),
                                        active = false,
                                        onClick = { viewModel.resolvePending(false, errorText) },
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        Composer(
            res = res,
            value = input,
            onValueChange = { input = it },
            enabled = !busy,
            canSend = canSend && input.isNotBlank(),
            onSend = { send(input); input = "" },
        )
    }
}

/** An assistant turn: markdown prose, then the `<ui>` block if there was one. */
@Composable
private fun AssistantBubble(
    raw: String,
    enabled: Boolean,
    onSend: (String) -> Unit,
    onOpen: (String) -> Unit,
) {
    val colors = LocalSanvyaColors.current
    val split = remember(raw) { splitAssistantUi(raw) }
    val ui: AssistantUi? = remember(raw) { parseAssistantUiPayload(split.json) }
    Column(
        modifier = Modifier.fillMaxWidth(if (ui == null) 0.85f else 1f),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (split.text.isNotEmpty()) {
            SanvyaCard(
                modifier = Modifier.fillMaxWidth(),
                padding = PaddingValues(horizontal = 14.dp, vertical = 10.dp),
            ) {
                AssistantMarkdown(split.text)
            }
        }
        ui?.let {
            AssistantUiBlock(ui = it, onSend = onSend, onOpen = onOpen, enabled = enabled)
        }
    }
    // An empty turn draws an empty column rather than an empty bubble, which is
    // what web's `{text && ...}` does.
}

/** A starter suggestion. Full width, left-aligned, wraps -- web's own chip. */
@Composable
private fun SuggestionChip(label: String, enabled: Boolean, colors: SanvyaColors, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(SanvyaShape.radiusSm)
            .background(colors.surface)
            .border(1.dp, colors.border, SanvyaShape.radiusSm)
            .clickable(interactionSource = interaction, indication = null, enabled = enabled, onClick = onClick)
            .alpha(if (enabled) 1f else 0.45f)
            .padding(horizontal = 14.dp, vertical = 10.dp),
    ) {
        SanvyaText(label, SanvyaType.body)
    }
}

/**
 * The composer: a pill holding a growing text field and a round send button.
 *
 * Multiline and Enter-inserts-a-newline, as web's textarea is -- there is no
 * "Enter sends" on either platform, because a phone keyboard's return key is
 * how you write a second sentence. The field caps at roughly six lines and
 * scrolls, which is web's `maxHeight: 150`.
 */
@Composable
private fun Composer(
    res: Resources,
    value: String,
    onValueChange: (String) -> Unit,
    enabled: Boolean,
    canSend: Boolean,
    onSend: () -> Unit,
) {
    val colors = LocalSanvyaColors.current
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        Row(
            modifier = Modifier
                .weight(1f)
                .clip(SanvyaShape.pill)
                .background(colors.surface)
                .border(1.dp, colors.borderStrong, SanvyaShape.pill)
                .padding(start = 16.dp, end = 6.dp, top = 4.dp, bottom = 4.dp),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Box(modifier = Modifier.weight(1f).heightIn(max = 150.dp).padding(vertical = 9.dp)) {
                if (value.isEmpty()) {
                    SanvyaText(S.Assistant.composerPlaceholder(res), SanvyaType.body, color = colors.text2)
                }
                BasicTextField(
                    value = value,
                    onValueChange = onValueChange,
                    enabled = enabled,
                    textStyle = SanvyaType.body.copy(color = colors.text),
                    cursorBrush = androidx.compose.ui.graphics.SolidColor(colors.accent),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(SanvyaShape.pill)
                    .background(if (canSend) colors.accent else colors.surface2)
                    .clickable(enabled = canSend, onClick = onSend),
                contentAlignment = Alignment.Center,
            ) {
                SanvyaArrowUpIcon(
                    size = 19.dp,
                    tint = if (canSend) Color.White else colors.text3,
                    description = S.Assistant.sendAria(res),
                )
            }
        }
    }
}

/**
 * The i18n key `assistantErrorKey` returns, resolved.
 *
 * Domain returns a key rather than a string so the decision stays vector-pinned
 * and the wording stays in the catalogue -- neither of which a Domain module
 * that formatted the sentence itself could manage.
 */
private fun assistantErrorString(res: Resources, key: String, raw: String): String = when (key) {
    "errNotConfigured" -> S.Assistant.errNotConfigured(res)
    "errModel" -> S.Assistant.errModel(res)
    "errNetwork" -> S.Assistant.errNetwork(res)
    // The only key that interpolates. Web passes the raw provider message
    // through unchanged, on the grounds that "something went wrong" with no
    // detail is not something anyone can act on.
    "errGeneric" -> S.Assistant.errGeneric(res, raw)
    else -> S.Assistant.errDefault(res)
}
