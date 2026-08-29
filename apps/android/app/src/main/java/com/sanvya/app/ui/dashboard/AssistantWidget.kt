package com.sanvya.app.ui.dashboard

import android.content.res.Resources
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaIcons
import com.sanvya.app.theme.SanvyaShape
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.assistant.AssistantScreen
import com.sanvya.app.ui.assistant.AssistantViewModel
import com.sanvya.app.ui.components.H2
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaChip
import com.sanvya.app.ui.components.SanvyaIcon
import com.sanvya.app.ui.components.SanvyaInput
import com.sanvya.app.ui.components.SanvyaText
import com.sanvya.app.ui.shell.LocalShellNavigate

/**
 * "Ask Sanvya" on the wide-window dashboard -- a card that opens into a docked
 * chat panel. A port of `apps/web/src/ui/desktop/AssistantWidget.tsx`.
 *
 * **Asking never leaves the dashboard**, which is the whole point of the widget
 * and the reason it is not simply a link to the Assistant tab. The panel mounts
 * the app's REAL assistant screen -- threads, tools, quota, confirmations -- so
 * there is still exactly one chat implementation; it is embedded here rather
 * than navigated to. The collapsed card is only a launcher: whatever you type or
 * tap on it becomes the panel's opening question.
 *
 * That hand-off is why the panel owns an [AssistantViewModel] and passes it down
 * rather than letting `AssistantScreen` create its own. `AssistantScreen` already
 * takes the view model as a parameter, so nothing in the assistant had to change
 * to make this work.
 *
 * TWO deliberate divergences from web, both about presentation rather than
 * behaviour:
 *
 *  * Web's card MORPHS into the panel with a shared `layoutId`. There is no
 *    cheap Compose equivalent of framer-motion's FLIP between two different
 *    elements, and a hand-rolled one would be a large amount of animation code
 *    guarding a transition nobody would miss.
 *  * The orb is a static gradient sphere. Web's `AssistantOrb` is animated; the
 *    animation is decoration on a launcher, and a permanently-running animation
 *    on the dashboard is a battery cost with nothing behind it.
 *
 * Mirrors apps/ios/App/Components/AssistantWidget.swift.
 */
@Composable
fun AssistantWidget(modifier: Modifier = Modifier) {
    val res = sRes()
    val colors = LocalSanvyaColors.current
    var open by rememberSaveable { mutableStateOf(false) }
    // The question that opened the panel, handed to the chat as its first turn.
    var opening by rememberSaveable { mutableStateOf<String?>(null) }
    var draft by rememberSaveable { mutableStateOf("") }

    val ask: (String) -> Unit = { text ->
        val trimmed = text.trim()
        if (trimmed.isNotEmpty()) {
            opening = trimmed
            open = true
            draft = ""
        }
    }

    SanvyaCard(modifier = modifier, padding = PaddingValues(20.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            H2(S.Assistant.title(res), modifier = Modifier.weight(1f))
            IconTarget(
                glyph = SanvyaIcons.spaceDashboard,
                description = S.Dashboard.askExpandA11y(res),
                onClick = { opening = null; open = true },
            )
        }

        Box(
            modifier = Modifier.fillMaxWidth().padding(vertical = 14.dp),
            contentAlignment = Alignment.Center,
        ) {
            AssistantOrb()
        }

        // Four openers, so the blank-page problem never happens: nobody has to
        // work out what an assistant over their own ledger is even for.
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            quickPrompts(res).forEach { quick ->
                SanvyaChip(
                    label = quick.label,
                    active = false,
                    onClick = { ask(quick.prompt) },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SanvyaInput(
                value = draft,
                onValueChange = { draft = it },
                modifier = Modifier.weight(1f),
                placeholder = S.Dashboard.askPlaceholder(res),
            )
            IconTarget(
                glyph = SanvyaIcons.chevronRight,
                description = S.Dashboard.askSendA11y(res),
                onClick = { ask(draft) },
                tint = colors.accent,
            )
        }
    }

    if (open) {
        AssistantPanel(
            openingPrompt = opening,
            onClose = { open = false; opening = null },
        )
    }
}

/** One of the four openers on the collapsed card. */
private data class QuickPrompt(val label: String, val prompt: String)

private fun quickPrompts(res: Resources): List<QuickPrompt> = listOf(
    QuickPrompt(S.Dashboard.askQuickWhereLabel(res), S.Dashboard.askQuickWherePrompt(res)),
    QuickPrompt(S.Dashboard.askQuickBudgetLabel(res), S.Dashboard.askQuickBudgetPrompt(res)),
    QuickPrompt(S.Dashboard.askQuickGoalLabel(res), S.Dashboard.askQuickGoalPrompt(res)),
    QuickPrompt(S.Dashboard.askQuickFindLabel(res), S.Dashboard.askQuickFindPrompt(res)),
)

/**
 * The docked chat panel.
 *
 * A side panel rather than a centred dialog, because web docks it to the right
 * edge and the dashboard stays visible beside it -- an assistant that covers the
 * numbers you are asking about is answering the wrong way round.
 */
@Composable
private fun AssistantPanel(
    openingPrompt: String?,
    onClose: () -> Unit,
    viewModel: AssistantViewModel = viewModel(),
) {
    val res = sRes()
    val colors = LocalSanvyaColors.current
    val navigate = LocalShellNavigate.current
    val entitlementKnown by viewModel.entitlementKnown.collectAsState()
    val isPaid by viewModel.isPaid.collectAsState()
    var sent by remember { mutableStateOf(false) }

    // Held until the entitlement has been read AND is paid. Sending sooner would
    // burn the question against a gate the user is about to be shown instead --
    // and the gate is what web shows a free user too.
    LaunchedEffect(openingPrompt, entitlementKnown, isPaid) {
        val text = openingPrompt?.trim().orEmpty()
        if (sent || text.isEmpty() || !entitlementKnown || !isPaid) return@LaunchedEffect
        sent = true
        viewModel.newChat(S.Assistant.greeting(res))
        viewModel.send(text) { key, raw -> assistantError(res, key, raw) }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        val scrim = remember { MutableInteractionSource() }
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(colors.text.copy(alpha = 0.28f))
                .clickable(interactionSource = scrim, indication = null, onClick = onClose),
        )
        SanvyaCard(
            modifier = Modifier
                .align(Alignment.CenterEnd)
                .fillMaxHeight()
                .widthIn(max = PANEL_WIDTH)
                .padding(16.dp),
            padding = PaddingValues(16.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                H2(S.Assistant.title(res), modifier = Modifier.weight(1f))
                IconTarget(
                    glyph = SanvyaIcons.close,
                    description = S.Dashboard.askCollapseA11y(res),
                    onClick = onClose,
                )
            }
            AssistantScreen(
                onOpenHref = { href -> onClose(); navigate(href) },
                onOpenHelp = { onClose(); navigate("help") },
                onOpenSettings = { onClose(); navigate("settings") },
                viewModel = viewModel,
            )
        }
    }
}

private val PANEL_WIDTH = 420.dp

/** A round icon target, matching the shell's utility buttons. */
@Composable
private fun IconTarget(
    glyph: String,
    description: String,
    onClick: () -> Unit,
    tint: Color = LocalSanvyaColors.current.text,
) {
    val colors = LocalSanvyaColors.current
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier = Modifier
            .size(32.dp)
            .clip(SanvyaShape.pill)
            .background(colors.surface2)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        SanvyaIcon(glyph = glyph, size = 16.dp, tint = tint, description = description)
    }
}

/**
 * The assistant's sphere.
 *
 * Static, and web's is animated -- see the note on [AssistantWidget]. The
 * gradient is the accent over the forest green the net-worth hero uses, so the
 * two cards in the hero row read as one object rather than two.
 */
@Composable
private fun AssistantOrb() {
    val colors = LocalSanvyaColors.current
    Box(
        modifier = Modifier
            .size(ORB_SIZE)
            .clip(SanvyaShape.pill)
            .background(
                Brush.radialGradient(
                    colors = listOf(colors.accentSoft, colors.accent, colors.forest),
                    center = Offset(ORB_HIGHLIGHT_X, ORB_HIGHLIGHT_Y),
                ),
            ),
    )
}

/** Web's `<AssistantOrb size={116} />`. */
private val ORB_SIZE = 116.dp

/** Off-centre, so the sphere reads as lit from the top-left rather than flat. */
private const val ORB_HIGHLIGHT_X = 100f
private const val ORB_HIGHLIGHT_Y = 90f

/**
 * `AssistantScreen.kt`'s own `assistantErrorString`, repeated.
 *
 * Six lines of duplication, deliberately: the original is `private` in a file
 * this pass does not own, and promoting it would mean editing a screen another
 * slice is working in to save a `when`. If the two ever drift, the keys are the
 * contract -- Domain returns the key, the catalogue owns the words -- so the
 * worst case is one surface showing a stale sentence, not a wrong one.
 */
private fun assistantError(res: Resources, key: String, raw: String): String = when (key) {
    "errNotConfigured" -> S.Assistant.errNotConfigured(res)
    "errModel" -> S.Assistant.errModel(res)
    "errNetwork" -> S.Assistant.errNetwork(res)
    "errGeneric" -> S.Assistant.errGeneric(res, raw)
    else -> S.Assistant.errDefault(res)
}
