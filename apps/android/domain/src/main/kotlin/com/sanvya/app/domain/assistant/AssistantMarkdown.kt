package com.sanvya.app.domain.assistant

import com.sanvya.app.domain.js.jsRound
import com.sanvya.app.domain.js.jsToFixed1

/**
 * The assistant's message parser — prose and the structured block it may append.
 *
 * Ported from the JSX-free half of `apps/web/src/assistant/richMessage.tsx`.
 * The split is the same one the PDF work uses: what the model says is parsed
 * identically on every client, and only the drawing is per-platform. A phone
 * that disagreed with the browser about whether a line is a table row would
 * render a different answer to the same question.
 *
 * Mirrors iOS's AssistantMarkdown.swift.
 */

/**
 * Indian-scale compact number: 1.2k, 3.4L, 1.2Cr.
 *
 * Lakh and crore rather than M and B, deliberately — this is web's own scale,
 * and it is the one every other number on these screens uses.
 */
fun assistantCompactNum(n: Double): String {
    val abs = kotlin.math.abs(n)
    if (abs >= 1e7) return "${jsToFixed1(n / 1e7)}Cr"
    if (abs >= 1e5) return "${jsToFixed1(n / 1e5)}L"
    if (abs >= 1e3) return "${jsToFixed1(n / 1e3)}k"
    // `${Math.round(n)}` on a Double: JS prints -0 as "0", and so does this
    // once the value goes through Long.
    return jsRound(n).toLong().toString()
}

// ---- inline formatting -----------------------------------------------------

/** What a run of inline text is. */
enum class InlineKind { TEXT, BOLD, ITALIC, CODE, LINK }

/** One run. [href] is set only for [InlineKind.LINK]. */
data class InlineSpan(val kind: InlineKind, val text: String, val href: String? = null)

/**
 * The regex is web's, character for character. Its branch ORDER is load-bearing
 * too: a link is tried before emphasis, so `[**a**](/x)` is a link whose label
 * happens to contain asterisks rather than bold text followed by junk.
 */
private val INLINE_RX = Regex(
    "\\[([^\\]]+)\\]\\(([^)\\s]+)\\)|\\*\\*([^*]+)\\*\\*|__([^_]+)__|\\*([^*\\n]+)\\*|`([^`]+)`",
)
private val HTTP_RX = Regex("^https?://")

/**
 * Split a line into formatted runs.
 *
 * **The link filter is a security control, not formatting.** Only an internal
 * route (`/…`) or an explicit http(s) URL becomes a link; anything else —
 * `javascript:`, `data:`, a bare `evil.test` — degrades to the label as plain
 * text. Web does the same and for the same reason: this string came from a
 * language model, which can be talked into emitting whatever a user's
 * transaction description tells it to.
 */
fun assistantInlineSpans(s: String): List<InlineSpan> {
    val out = mutableListOf<InlineSpan>()
    var last = 0
    for (m in INLINE_RX.findAll(s)) {
        if (m.range.first > last) out.add(InlineSpan(InlineKind.TEXT, s.substring(last, m.range.first)))
        val g = m.groups
        val label = g[1]?.value
        if (label != null) {
            val href = g[2]?.value.orEmpty()
            when {
                href.startsWith("/") -> out.add(InlineSpan(InlineKind.LINK, label, href))
                HTTP_RX.containsMatchIn(href) -> out.add(InlineSpan(InlineKind.LINK, label, href))
                else -> out.add(InlineSpan(InlineKind.TEXT, label))
            }
        } else {
            val bold = g[3]?.value ?: g[4]?.value
            val italic = g[5]?.value
            val code = g[6]?.value
            when {
                // `m[3] ?? m[4]` in JS is nullish, not falsy: an EMPTY capture
                // would still win the branch. The regex requires one or more
                // characters, so it cannot be empty -- but the ordering is
                // copied rather than reasoned about, because the day the regex
                // changes this comment is the only warning.
                bold != null -> out.add(InlineSpan(InlineKind.BOLD, bold))
                italic != null && italic.isNotEmpty() -> out.add(InlineSpan(InlineKind.ITALIC, italic))
                code != null && code.isNotEmpty() -> out.add(InlineSpan(InlineKind.CODE, code))
            }
        }
        last = m.range.last + 1
    }
    if (last < s.length) out.add(InlineSpan(InlineKind.TEXT, s.substring(last)))
    return out
}

// ---- block structure -------------------------------------------------------

/** One bullet. [task] and [checked] only mean anything for a `- [ ]` item. */
data class AssistantListItem(val text: String, val task: Boolean = false, val checked: Boolean = false)

/** The GitHub-flavoured subset the assistant is allowed to use. */
sealed interface AssistantBlock {
    data class Heading(val level: Int, val text: String) : AssistantBlock
    data class Paragraph(val lines: List<String>) : AssistantBlock
    data class Bullets(val items: List<AssistantListItem>) : AssistantBlock
    data class Ordered(val items: List<String>) : AssistantBlock
    data class Quote(val lines: List<String>) : AssistantBlock
    data class Table(val header: List<String>, val rows: List<List<String>>) : AssistantBlock
    data object Rule : AssistantBlock
    data class Code(val text: String) : AssistantBlock
}

private val RX_FENCE = Regex("^```")
private val RX_RULE = Regex("^\\s*([-*_])\\1\\1[-*_ ]*$")
private val RX_HEADING = Regex("^(#{1,6})\\s+(.*)$")
private val RX_TABLE_SEP = Regex("^\\s*\\|?\\s*:?-{2,}:?\\s*(\\|\\s*:?-{1,}:?\\s*)*\\|?\\s*$")
private val RX_QUOTE = Regex("^\\s*>\\s?")
private val RX_BULLET = Regex("^\\s*[-*+]\\s+")
private val RX_ORDERED = Regex("^\\s*\\d+[.)]\\s+")
private val RX_TASK = Regex("^\\[( |x|X)\\]\\s+")
private val RX_BLOCK_START = Regex("^(#{1,6}\\s|>\\s?|\\s*[-*+]\\s+|\\s*\\d+[.)]\\s+|```)")

private fun splitRow(l: String): List<String> =
    l.trim()
        .replace(Regex("^\\|"), "")
        .replace(Regex("\\|$"), "")
        .split("|")
        .map { it.trim() }

private fun isBlockStart(l: String): Boolean =
    RX_BLOCK_START.containsMatchIn(l) || RX_RULE.containsMatchIn(l)

/**
 * Parse assistant prose into blocks.
 *
 * A straight port of web's `parseBlocks`, including the details that look like
 * accidents and are not:
 *
 * * a table needs its separator row to be the NEXT line, so a lone pipe in a
 *   sentence stays a sentence.
 * * an unterminated fence swallows the rest of the message, because the
 *   alternative — treating it as prose — would print raw backticks.
 * * a paragraph stops at the first line that STARTS a block, which is why
 *   `isBlockStart` exists separately from the dispatch above it.
 */
fun parseAssistantBlocks(src: String): List<AssistantBlock> {
    val lines = src.replace("\r\n", "\n").split("\n")
    val blocks = mutableListOf<AssistantBlock>()
    var i = 0
    while (i < lines.size) {
        val line = lines[i]
        if (line.isBlank()) { i++; continue }

        if (RX_FENCE.containsMatchIn(line)) {
            val buf = mutableListOf<String>()
            i++
            while (i < lines.size && !RX_FENCE.containsMatchIn(lines[i])) { buf.add(lines[i]); i++ }
            i++
            blocks.add(AssistantBlock.Code(buf.joinToString("\n")))
            continue
        }
        if (RX_RULE.containsMatchIn(line)) { blocks.add(AssistantBlock.Rule); i++; continue }

        val heading = RX_HEADING.find(line)
        if (heading != null) {
            blocks.add(AssistantBlock.Heading(heading.groupValues[1].length, heading.groupValues[2].trim()))
            i++
            continue
        }

        if (line.contains("|") && i + 1 < lines.size && RX_TABLE_SEP.containsMatchIn(lines[i + 1])) {
            val header = splitRow(line)
            i += 2
            val rows = mutableListOf<List<String>>()
            while (i < lines.size && lines[i].contains("|") && lines[i].isNotBlank()) {
                rows.add(splitRow(lines[i]))
                i++
            }
            blocks.add(AssistantBlock.Table(header, rows))
            continue
        }
        if (RX_QUOTE.containsMatchIn(line)) {
            val buf = mutableListOf<String>()
            while (i < lines.size && RX_QUOTE.containsMatchIn(lines[i])) {
                buf.add(RX_QUOTE.replaceFirst(lines[i], ""))
                i++
            }
            blocks.add(AssistantBlock.Quote(buf))
            continue
        }
        if (RX_BULLET.containsMatchIn(line)) {
            val items = mutableListOf<AssistantListItem>()
            while (i < lines.size && RX_BULLET.containsMatchIn(lines[i])) {
                val it = RX_BULLET.replaceFirst(lines[i], "")
                val task = RX_TASK.find(it)
                if (task != null) {
                    items.add(
                        AssistantListItem(
                            text = RX_TASK.replaceFirst(it, ""),
                            task = true,
                            checked = task.groupValues[1].lowercase() == "x",
                        ),
                    )
                } else {
                    items.add(AssistantListItem(it))
                }
                i++
            }
            blocks.add(AssistantBlock.Bullets(items))
            continue
        }
        if (RX_ORDERED.containsMatchIn(line)) {
            val items = mutableListOf<String>()
            while (i < lines.size && RX_ORDERED.containsMatchIn(lines[i])) {
                items.add(RX_ORDERED.replaceFirst(lines[i], ""))
                i++
            }
            blocks.add(AssistantBlock.Ordered(items))
            continue
        }

        val buf = mutableListOf<String>()
        while (i < lines.size && lines[i].isNotBlank() && !isBlockStart(lines[i])) { buf.add(lines[i]); i++ }
        blocks.add(AssistantBlock.Paragraph(buf))
    }
    return blocks
}

// ---- the <ui> block --------------------------------------------------------

/**
 * The card shapes the model is allowed to emit.
 *
 * "Allowed" is the operative word. Everything below is validated defensively
 * and anything that does not fit is DROPPED, not rendered best-effort — a
 * language model that has been talked into emitting a malformed card should
 * cost the user a card, not a broken screen.
 */
sealed interface AssistantCard {
    data class Stat(
        val label: String,
        val value: String,
        val sub: String? = null,
        /** "accent" | "positive" | "negative" | "neutral". Anything else becomes "accent". */
        val tone: String = "accent",
    ) : AssistantCard

    data class Progress(val label: String, val value: String? = null, val pct: Double) : AssistantCard

    data class BreakdownItem(val label: String, val value: String? = null, val pct: Double? = null)
    data class Breakdown(val label: String, val items: List<BreakdownItem>) : AssistantCard

    data class ChartPoint(val x: String, val y: Double)
    /** [chart] is "line" | "bar". */
    data class Chart(
        val label: String,
        val chart: String,
        val points: List<ChartPoint>,
        val value: String? = null,
    ) : AssistantCard
}

/** A suggestion: either sends a chat message or opens an app route, never both. */
data class AssistantAction(val label: String, val send: String? = null, val href: String? = null)

data class AssistantUi(val cards: List<AssistantCard>, val actions: List<AssistantAction>)

internal const val ASSISTANT_MAX_CARDS = 4
internal const val ASSISTANT_MAX_ACTIONS = 4
internal const val ASSISTANT_MAX_BREAKDOWN_ITEMS = 6
internal const val ASSISTANT_MAX_CHART_POINTS = 12
internal const val ASSISTANT_MIN_CHART_POINTS = 2

/** Web's UI_RE. Non-greedy, so a second block is left in the prose rather than swallowed. */
internal val ASSISTANT_UI_RX = Regex("<ui>\\s*([\\s\\S]*?)\\s*</ui>")

/** `Math.min(100, Math.max(0, …))`, with a non-finite or non-numeric value as 0. */
internal fun clampPct(v: Double?): Double =
    if (v == null || !v.isFinite()) 0.0 else kotlin.math.min(100.0, kotlin.math.max(0.0, v))

/**
 * A parsed JSON value, in the smallest shape this validator needs.
 *
 * **Why Domain declares its own instead of taking a library's.** The `<ui>`
 * block is JSON, so something has to parse it — but `:domain` has no JSON
 * dependency in its main source set and Swift's Domain has none either, and
 * that symmetry is the thing that makes the two Domains provably the same code.
 * Adding kotlinx.serialization here to save twenty lines would have bought a
 * shipped dependency and an asymmetry.
 *
 * Each platform adapts its own parser into this — `JsonElement` on Android,
 * `JSONSerialization`'s `Any` on iOS — and everything downstream is shared and
 * vector-pinned.
 */
sealed interface AssistantJson {
    data class Str(val value: String) : AssistantJson
    data class Num(val value: Double) : AssistantJson
    data class Bool(val value: Boolean) : AssistantJson
    data class Arr(val values: List<AssistantJson>) : AssistantJson
    data class Obj(val values: Map<String, AssistantJson>) : AssistantJson
    data object Null : AssistantJson
}

/** `typeof v === "string" && v.length > 0` — an empty string is NOT a value here. */
private fun AssistantJson?.str(): String? =
    (this as? AssistantJson.Str)?.value?.takeIf { it.isNotEmpty() }

private fun AssistantJson?.num(): Double? = (this as? AssistantJson.Num)?.value

private fun AssistantJson?.obj(): Map<String, AssistantJson>? = (this as? AssistantJson.Obj)?.values

private fun AssistantJson?.arr(): List<AssistantJson>? = (this as? AssistantJson.Arr)?.values

private fun toCard(raw: AssistantJson): AssistantCard? {
    val c = raw.obj() ?: return null
    when (c["kind"].str()) {
        "stat" -> {
            val label = c["label"].str() ?: return null
            val value = c["value"].str() ?: return null
            val rawTone = c["tone"].str()
            val tone = if (rawTone == "positive" || rawTone == "negative" || rawTone == "neutral") rawTone else "accent"
            return AssistantCard.Stat(label, value, c["sub"].str(), tone)
        }
        "progress" -> {
            val label = c["label"].str() ?: return null
            return AssistantCard.Progress(label, c["value"].str(), clampPct(c["pct"].num()))
        }
        "breakdown" -> {
            val label = c["label"].str() ?: return null
            val rawItems = c["items"].arr() ?: return null
            val items = rawItems
                .filter { it is AssistantJson.Obj }
                .filter { it.obj()?.get("label").str() != null }
                .take(ASSISTANT_MAX_BREAKDOWN_ITEMS)
                .map { item ->
                    val o = item.obj().orEmpty()
                    AssistantCard.BreakdownItem(
                        label = o["label"].str().orEmpty(),
                        value = o["value"].str(),
                        // `i.pct == null ? undefined : clampPct(i.pct)` -- an
                        // ABSENT pct means "no bar", a present-but-nonsense one
                        // means "a bar at zero". Collapsing the two would draw
                        // a full-width empty bar for every item.
                        pct = if (o["pct"] == null || o["pct"] is AssistantJson.Null) null else clampPct(o["pct"].num()),
                    )
                }
            return if (items.isEmpty()) null else AssistantCard.Breakdown(label, items)
        }
        "chart" -> {
            val label = c["label"].str() ?: return null
            val chart = c["chart"].str()
            if (chart != "line" && chart != "bar") return null
            val rawPoints = c["points"].arr() ?: return null
            val points = rawPoints
                .filter { it is AssistantJson.Obj }
                .mapNotNull { p ->
                    val o = p.obj().orEmpty()
                    val x = o["x"].str() ?: return@mapNotNull null
                    val y = o["y"].num()?.takeIf { it.isFinite() } ?: return@mapNotNull null
                    AssistantCard.ChartPoint(x, y)
                }
                .take(ASSISTANT_MAX_CHART_POINTS)
            // Two points or it is not a chart, it is a number with axes.
            return if (points.size >= ASSISTANT_MIN_CHART_POINTS) {
                AssistantCard.Chart(label, chart, points, c["value"].str())
            } else {
                null
            }
        }
        else -> return null
    }
}

private fun toAction(raw: AssistantJson): AssistantAction? {
    val a = raw.obj() ?: return null
    val label = a["label"].str() ?: return null
    a["send"].str()?.let { return AssistantAction(label, send = it) }
    // Internal routes only. An `href` the model invented pointing anywhere else
    // is dropped entirely rather than rendered as an external link.
    a["href"].str()?.let { if (it.startsWith("/")) return AssistantAction(label, href = it) }
    return null
}

/**
 * Validate a parsed `<ui>` payload. Null when nothing in it survived.
 */
fun assistantUiFrom(parsed: AssistantJson): AssistantUi? {
    val root = parsed.obj() ?: return null
    val cards = (root["cards"].arr() ?: emptyList())
        .mapNotNull { toCard(it) }
        .take(ASSISTANT_MAX_CARDS)
    val actions = (root["actions"].arr() ?: emptyList())
        .mapNotNull { toAction(it) }
        .take(ASSISTANT_MAX_ACTIONS)
    return if (cards.isEmpty() && actions.isEmpty()) null else AssistantUi(cards, actions)
}

/** The prose and the raw `<ui>` payload, separated. */
data class AssistantSplit(val text: String, val json: String?)

/**
 * Split a raw assistant message into prose and the `<ui>` payload.
 *
 * Separate from [assistantUiFrom] because this half needs no JSON parser at
 * all, and keeping it that way is what lets the platform supply one.
 */
fun splitAssistantUi(raw: String): AssistantSplit {
    val m = ASSISTANT_UI_RX.find(raw) ?: return AssistantSplit(raw.trim(), null)
    // `raw.replace(UI_RE, "")` in JS with a NON-global regex replaces only the
    // first match, and so does this. A model that emits two blocks keeps the
    // second one visible in the prose, which is the loud failure.
    return AssistantSplit(ASSISTANT_UI_RX.replaceFirst(raw, "").trim(), m.groupValues[1])
}
