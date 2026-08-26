package com.sanvya.app.ui.reflect

import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaColors
import com.sanvya.app.theme.SanvyaIcons
import com.sanvya.app.ui.components.SanvyaIcon
import com.sanvya.app.ui.formatMoney
import com.sanvya.app.ui.isoLabel
import com.sanvya.app.ui.transactions.avatarColor
import com.sanvya.app.ui.transactions.merchantTitle
import kotlin.math.abs
import kotlin.math.min
import kotlinx.coroutines.launch

/**
 * Reflect -- ported from apps/web/app/reflect/page.tsx.
 *
 * A card stack over untagged expenses. Left is "need", right is "greed", and
 * the buttons do the same thing for anyone who would rather tap.
 *
 * **Two deliberate divergences, both away from web's version:**
 *
 * 1. Web's buttons are labelled "Need (←)" and "Greed (→)" -- keyboard hints on
 *    a screen that, on a phone, has no keyboard. The arrows are dropped and the
 *    swipe is explained in a line under the stack instead.
 * 2. Web paints the swipe tints and the buttons with raw Material colours
 *    (`#4CAF50`, `#F44336`) rather than the design tokens every other surface
 *    uses. These use `positive` and `negative`, which is what those colours were
 *    reaching for. Recorded in PARITY_AUDIT.
 */
@Composable
fun ReflectScreen(viewModel: ReflectViewModel = viewModel()) {
    val state by viewModel.state.collectAsState()
    val colors = LocalSanvyaColors.current

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.bg)
            .padding(horizontal = 16.dp, vertical = 24.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(bottom = 32.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                S.Reflect.title(sRes()),
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                color = colors.text,
            )
            Spacer(Modifier.weight(1f))
            Text(
                S.Reflect.left(sRes(), state.visible.size),
                fontSize = 14.sp,
                color = colors.text2,
            )
        }

        when {
            state.isLoading -> Box(Modifier.weight(1f).fillMaxWidth(), Alignment.Center) {
                CircularProgressIndicator(color = colors.accent)
            }

            state.visible.isEmpty() -> Box(Modifier.weight(1f).fillMaxWidth(), Alignment.Center) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    SanvyaIcon(SanvyaIcons.check, size = 48.dp, tint = colors.positive)
                    Text(
                        S.Reflect.doneTitle(sRes()),
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Bold,
                        color = colors.text,
                    )
                    Text(
                        S.Reflect.doneBody(sRes()),
                        fontSize = 14.sp,
                        color = colors.text2,
                        textAlign = TextAlign.Center,
                    )
                }
            }

            else -> {
                CardStack(
                    rows = state.visible,
                    colors = colors,
                    onJudge = viewModel::judge,
                    modifier = Modifier.weight(1f),
                )
                Footer(
                    canUndo = state.canUndo,
                    colors = colors,
                    onNeed = { state.visible.firstOrNull()?.let { viewModel.judge(it.id, "need") } },
                    onGreed = { state.visible.firstOrNull()?.let { viewModel.judge(it.id, "greed") } },
                    onUndo = viewModel::undo,
                    onSkip = { state.visible.firstOrNull()?.let { viewModel.skip(it.id) } },
                )
            }
        }
    }
}

@Composable
private fun CardStack(
    rows: List<LedgerRepository.IntentQueueRow>,
    colors: SanvyaColors,
    onJudge: (String, String) -> Unit,
    modifier: Modifier = Modifier,
) {
    // Three cards at most; web renders the same slice for the same reason.
    val cards = rows.take(3)
    val top = cards.firstOrNull() ?: return
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    // Keyed on the top card's id: a fresh Animatable per card, so the next one
    // does not inherit the last one's offset.
    val offsetX = remember(top.id) { Animatable(0f) }
    val commitPx = with(density) { 100.dp.toPx() }

    Box(modifier = modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        cards.asReversed().forEachIndexed { reversedIndex, row ->
            val index = cards.size - 1 - reversedIndex
            val isTop = index == 0
            IntentCard(
                row = row,
                colors = colors,
                offsetPx = if (isTop) offsetX.value else 0f,
                modifier = Modifier
                    .fillMaxSize()
                    .scale(if (isTop) 1f else 1f - index * 0.05f)
                    .padding(top = if (isTop) 0.dp else (index * 15).dp)
                    .rotate(if (isTop) offsetX.value / 40f else 0f)
                    .then(
                        if (!isTop) {
                            Modifier
                        } else {
                            Modifier.pointerInput(top.id) {
                                detectHorizontalDragGestures(
                                    onDragEnd = {
                                        val x = offsetX.value
                                        when {
                                            x < -commitPx -> onJudge(top.id, "need")
                                            x > commitPx -> onJudge(top.id, "greed")
                                            else -> scope.launch { offsetX.animateTo(0f) }
                                        }
                                    },
                                ) { _, dragAmount ->
                                    scope.launch { offsetX.snapTo(offsetX.value + dragAmount) }
                                }
                            }
                        },
                    ),
            )
        }
    }
}

@Composable
private fun IntentCard(
    row: LedgerRepository.IntentQueueRow,
    colors: SanvyaColors,
    offsetPx: Float,
    modifier: Modifier = Modifier,
) {
    val raw = (row.description ?: row.note).orEmpty().ifBlank { S.Reflect.unknown(sRes()) }
    val title = merchantTitle(raw)
    val tint = avatarColor(title)
    Box(
        modifier = modifier
            .offset { IntOffset(offsetPx.toInt(), 0) }
            .clip(RoundedCornerShape(24.dp))
            .background(colors.surface)
            .border(2.dp, tint, RoundedCornerShape(24.dp)),
    ) {
        // The tint the card takes on as it moves -- green left, red right, the
        // same feedback web's two motion layers give.
        Box(
            Modifier
                .fillMaxSize()
                .background(
                    (if (offsetPx < 0) colors.positive else colors.negative)
                        .copy(alpha = min(0.2f, abs(offsetPx) / 2500f)),
                ),
        )
        Column(
            modifier = Modifier.fillMaxSize().padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(
                formatMoney(row.amountMinor, row.currency),
                fontSize = 42.sp,
                fontWeight = FontWeight.ExtraBold,
                color = colors.text,
            )
            Spacer(Modifier.size(8.dp))
            Text(
                title,
                fontSize = 24.sp,
                fontWeight = FontWeight.SemiBold,
                color = colors.text2,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.size(24.dp))
            row.accountName?.let { account ->
                Row(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(tint)
                        .padding(horizontal = 12.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    SanvyaIcon(SanvyaIcons.accountBalance, size = 16.dp, tint = Color.White)
                    Text(account, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                }
                Spacer(Modifier.size(12.dp))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Text(isoLabel(row.occurredAt, "d MMM y"), fontSize = 13.sp, color = colors.text2)
                row.categoryName?.let {
                    Text("• $it", fontSize = 13.sp, color = colors.text2)
                }
            }
        }
    }
}

@Composable
private fun Footer(
    canUndo: Boolean,
    colors: SanvyaColors,
    onNeed: () -> Unit,
    onGreed: () -> Unit,
    onUndo: () -> Unit,
    onSkip: () -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(top = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(S.Reflect.hint(sRes()), fontSize = 13.sp, color = colors.text2)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = onNeed) {
                Text(S.Reflect.need(sRes()), color = colors.positive)
            }
            OutlinedButton(onClick = onGreed) {
                Text(S.Reflect.greed(sRes()), color = colors.negative)
            }
        }
        Row(modifier = Modifier.fillMaxWidth()) {
            OutlinedButton(onClick = onUndo, enabled = canUndo) {
                Text(S.Reflect.undo(sRes()))
            }
            Spacer(Modifier.weight(1f))
            OutlinedButton(onClick = onSkip) {
                Text(S.Reflect.skip(sRes()))
            }
        }
    }
}
