package com.sanvya.app.ui.assistant

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sanvya.app.domain.assistant.AssistantBlock
import com.sanvya.app.domain.assistant.AssistantCard
import com.sanvya.app.domain.assistant.AssistantUi
import com.sanvya.app.domain.assistant.InlineKind
import com.sanvya.app.domain.assistant.assistantInlineSpans
import com.sanvya.app.domain.assistant.parseAssistantBlocks
import com.sanvya.app.domain.insights.SeriesPoint
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaShape
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.SanvyaBarsChart
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaChip
import com.sanvya.app.ui.components.SanvyaText

/**
 * Rendering an assistant message: markdown prose, then the `<ui>` block.
 *
 * Ported from `richMessage.tsx`'s render half. The PARSE half is Domain's and is
 * vector-pinned; this file is only how the result is drawn, which is the part
 * that is legitimately per-platform.
 *
 * Mirrors iOS's AssistantMessageView.swift.
 */

/**
 * A line of inline markdown as one styled string.
 *
 * A link renders as underlined accent text rather than a tappable region.
 * Compose can make it tappable — `ClickableText` plus an annotation — but the
 * routes the model may emit are the same ones the `<ui>` actions carry, and
 * those ARE buttons. Recorded in ABSENT-BY-DECISION rather than half-built.
 */
@Composable
private fun inlineText(line: String, base: androidx.compose.ui.text.TextStyle) {
    val colors = LocalSanvyaColors.current
    val spans = remember(line) { assistantInlineSpans(line) }
    val text = buildAnnotatedString {
        for (span in spans) {
            when (span.kind) {
                InlineKind.TEXT -> append(span.text)
                InlineKind.BOLD -> withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(span.text) }
                InlineKind.ITALIC -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append(span.text) }
                InlineKind.CODE -> withStyle(
                    SpanStyle(fontFamily = FontFamily.Monospace, background = colors.surface2),
                ) { append(span.text) }
                InlineKind.LINK -> withStyle(
                    SpanStyle(color = colors.accent, textDecoration = TextDecoration.Underline),
                ) { append(span.text) }
            }
        }
    }
    androidx.compose.material3.Text(text = text, style = base, color = colors.text)
}

/** Assistant prose, as blocks. */
@Composable
fun AssistantMarkdown(text: String) {
    val colors = LocalSanvyaColors.current
    val blocks = remember(text) { parseAssistantBlocks(text) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (block in blocks) {
            when (block) {
                is AssistantBlock.Heading -> inlineText(
                    block.text,
                    // Web's three sizes, keyed off the hash count.
                    SanvyaType.body.copy(
                        fontSize = if (block.level <= 1) 17.sp else if (block.level == 2) 15.5.sp else 14.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
                is AssistantBlock.Paragraph -> Column {
                    block.lines.forEach { inlineText(it, SanvyaType.body) }
                }
                is AssistantBlock.Bullets -> Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    block.items.forEach { item ->
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            SanvyaText(
                                // A task list draws its own box; a plain bullet
                                // gets the dot. Web swaps the whole list style
                                // when ANY item is a task, and so does this by
                                // marking each item individually -- the visual
                                // result is the same and the code is smaller.
                                if (item.task) (if (item.checked) "☑" else "☐") else "•",
                                SanvyaType.body,
                                color = colors.text2,
                            )
                            inlineText(
                                item.text,
                                if (item.checked) {
                                    SanvyaType.body.copy(textDecoration = TextDecoration.LineThrough)
                                } else {
                                    SanvyaType.body
                                },
                            )
                        }
                    }
                }
                is AssistantBlock.Ordered -> Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    block.items.forEachIndexed { index, item ->
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            SanvyaText("${index + 1}.", SanvyaType.body, color = colors.text2)
                            inlineText(item, SanvyaType.body)
                        }
                    }
                }
                is AssistantBlock.Quote -> Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Box(Modifier.width(3.dp).height(20.dp).background(colors.accentSoft))
                    Column { block.lines.forEach { inlineText(it, SanvyaType.body.copy(color = colors.text2)) } }
                }
                AssistantBlock.Rule -> HorizontalDivider(color = colors.border)
                is AssistantBlock.Code -> Box(
                    Modifier.fillMaxWidth().clip(SanvyaShape.radiusSm).background(colors.surface2)
                        .horizontalScroll(rememberScrollState()).padding(12.dp),
                ) {
                    SanvyaText(
                        block.text,
                        SanvyaType.body.copy(fontFamily = FontFamily.Monospace, fontSize = 12.5.sp),
                    )
                }
                is AssistantBlock.Table -> AssistantTable(block)
            }
        }
    }
}

/**
 * A markdown table.
 *
 * Horizontally scrollable, because the model emits comparison tables with three
 * or four money columns and a phone is 360dp wide. Web's own table sits in an
 * `overflow-x: auto` box for the same reason.
 */
@Composable
private fun AssistantTable(block: AssistantBlock.Table) {
    val colors = LocalSanvyaColors.current
    Box(
        Modifier.fillMaxWidth().clip(SanvyaShape.radiusSm)
            .background(colors.surface).horizontalScroll(rememberScrollState()),
    ) {
        Column {
            Row(Modifier.padding(horizontal = 12.dp, vertical = 7.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                block.header.forEach {
                    SanvyaText(it, SanvyaType.body.copy(fontSize = 13.sp, fontWeight = FontWeight.SemiBold), color = colors.text2)
                }
            }
            HorizontalDivider(color = colors.border)
            block.rows.forEachIndexed { rowIndex, row ->
                if (rowIndex > 0) HorizontalDivider(color = colors.border)
                Row(Modifier.padding(horizontal = 12.dp, vertical = 7.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    block.header.indices.forEach { col ->
                        SanvyaText(
                            row.getOrNull(col).orEmpty(),
                            SanvyaType.body.copy(
                                fontSize = 13.sp,
                                fontWeight = if (col == 0) FontWeight.SemiBold else FontWeight.Normal,
                            ),
                        )
                    }
                }
            }
        }
    }
}

/** The `<ui>` block: cards, then action chips. */
@Composable
fun AssistantUiBlock(ui: AssistantUi, onSend: (String) -> Unit, onOpen: (String) -> Unit, enabled: Boolean) {
    val colors = LocalSanvyaColors.current
    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        ui.cards.forEach { card ->
            SanvyaCard(padding = PaddingValues(14.dp), modifier = Modifier.fillMaxWidth()) {
                when (card) {
                    is AssistantCard.Stat -> {
                        SanvyaText(card.label, SanvyaType.body.copy(fontSize = 11.5.sp), color = colors.text2)
                        SanvyaText(
                            card.value,
                            SanvyaType.h2,
                            color = when (card.tone) {
                                "positive" -> colors.positive
                                "negative" -> colors.negative
                                "neutral" -> colors.text
                                else -> colors.accent
                            },
                        )
                        card.sub?.let { SanvyaText(it, SanvyaType.body.copy(fontSize = 11.5.sp), color = colors.text2) }
                    }
                    is AssistantCard.Progress -> {
                        SanvyaText(card.label, SanvyaType.body.copy(fontSize = 11.5.sp), color = colors.text2)
                        card.value?.let { SanvyaText(it, SanvyaType.body) }
                        AssistantBar(card.pct)
                    }
                    is AssistantCard.Breakdown -> {
                        SanvyaText(card.label, SanvyaType.body.copy(fontSize = 11.5.sp), color = colors.text2)
                        card.items.forEach { item ->
                            Row(
                                Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                SanvyaText(item.label, SanvyaType.body.copy(fontSize = 13.sp))
                                item.value?.let { SanvyaText(it, SanvyaType.body.copy(fontSize = 13.sp), color = colors.text2) }
                            }
                            // An ABSENT pct means "no bar" -- Domain keeps that
                            // distinction from "a bar at zero" on purpose.
                            item.pct?.let { AssistantBar(it) }
                        }
                    }
                    is AssistantCard.Chart -> {
                        SanvyaText(card.label, SanvyaType.body.copy(fontSize = 11.5.sp), color = colors.text2)
                        card.value?.let { SanvyaText(it, SanvyaType.h2) }
                        SanvyaBarsChart(
                            series = card.points.map { SeriesPoint(it.x, it.y) },
                            horizontal = false,
                            accent = colors.accent,
                            colors = colors,
                        )
                    }
                }
            }
        }
        if (ui.actions.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                ui.actions.forEach { action ->
                    SanvyaChip(
                        action.label,
                        active = false,
                        onClick = {
                            if (!enabled) return@SanvyaChip
                            // `send` and `href` are mutually exclusive by the
                            // time Domain has validated the action, and `href`
                            // is guaranteed to start with "/".
                            action.send?.let(onSend) ?: action.href?.let(onOpen)
                        },
                    )
                }
            }
        }
    }
}

/** The progress/breakdown bar. 0..100, already clamped by Domain. */
@Composable
private fun AssistantBar(pct: Double) {
    val colors = LocalSanvyaColors.current
    Box(
        Modifier.fillMaxWidth().height(6.dp).clip(SanvyaShape.pill).background(colors.surface2),
    ) {
        Box(
            Modifier.fillMaxWidth((pct / 100.0).toFloat().coerceIn(0f, 1f))
                .height(6.dp).clip(SanvyaShape.pill).background(colors.accent),
        )
    }
}
