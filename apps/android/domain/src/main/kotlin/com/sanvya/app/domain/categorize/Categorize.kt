package com.sanvya.app.domain.categorize

/**
 * The auto-categoriser: text normalisation, cold-start seeds, learned rules,
 * and the scoring that picks a category.
 *
 * Ported from `apps/web/src/categorize/normalize.ts` + `engine.ts`. Everything
 * here is PURE — the database round-trips web does inline are the caller's job,
 * which is what lets the bulk path (statement import) read every rule once and
 * then classify a thousand rows with no further I/O, exactly as web's
 * `buildClassifier` does.
 *
 * The seed tables live in the generated `CategorySeeds`.
 */

/** A learned rule, as stored in `category_rules`. */
data class CategoryRule(
    /** "phrase" | "token". */
    val kind: String,
    val key: String,
    val categoryId: String,
    val weight: Long,
    val corrections: Long,
)

/** The user's categories, as the seed resolver needs them. */
data class CategoryData(val id: String, val name: String)

data class NormalizedResult(
    /** Full cleaned phrase, used for exact learned-phrase lookups. */
    val phrase: String,
    /** Signal tokens plus bigrams, for scoring. Noise removed. */
    val tokens: List<String>,
    /** Best-guess merchant blob for substring matching: letters only, no spaces. */
    val merchant: String,
)

/**
 * If a category reaches this combined weight it is chosen confidently.
 * Phrases never come through here — an exact phrase match wins outright.
 */
const val CONFIDENCE_THRESHOLD = 2L

/** A user correction is worth five ordinary sightings. */
const val CORRECTION_BOOST = 5L

private val RX_NON_ALNUM_SPACE = Regex("[^\\p{L}\\p{N}\\s]")
private val RX_WS = Regex("\\s+")
private val RX_DELIMS = Regex("[\\s/\\-*:|.,;#@()\\[\\]]+")
private val RX_NON_LETTER = Regex("[^\\p{L}]")
private val RX_DIGIT = Regex("\\d")
private val RX_NON_DIGIT = Regex("\\D")

/** True if a token is pure noise: a rail code, a bank, a ref word, or mostly digits. */
private fun isNoise(tok: String): Boolean {
    if (tok.isEmpty()) return true
    if (CategorySeeds.NOISE_TOKENS.contains(tok)) return true
    if (CategorySeeds.STOP_WORDS.contains(tok)) return true
    // Reference numbers and long alphanumerics carry no signal.
    if (RX_DIGIT.containsMatchIn(tok) && tok.replace(RX_NON_DIGIT, "").length >= 4) return true
    return false
}

/**
 * Normalise a description: lowercase, split on the many delimiters banks use,
 * drop noise and reference tokens, and return the surviving merchant tokens
 * plus a concatenated blob for substring matching.
 *
 * Digits INSIDE a merchant name ("5paisa") are preserved deliberately — the
 * digit test above is about reference numbers, and a blanket digit strip would
 * lose a real merchant.
 */
fun normalizeText(text: String): NormalizedResult {
    if (text.isEmpty()) return NormalizedResult("", emptyList(), "")

    val lower = text.lowercase()

    // A cleaned phrase for exact learned-phrase matching. Keep this stable, or
    // every rule a user has already taught the app stops resolving.
    val phrase = lower.replace(RX_NON_ALNUM_SPACE, " ").replace(RX_WS, " ").trim()

    val parts = lower.split(RX_DELIMS).map { it.trim() }.filter { it.isNotEmpty() }

    // Keep tokens with signal: at least 3 letters, not noise.
    val signal = mutableListOf<String>()
    for (p in parts) {
        if (p.replace(RX_NON_LETTER, "").length < 3) continue
        if (isNoise(p)) continue
        signal.add(p)
    }

    // A LinkedHashSet, because web builds a Set and then `Array.from`s it —
    // insertion order, deduplicated. The order reaches scoring, so it matters.
    val tokenSet = LinkedHashSet<String>()
    tokenSet.addAll(signal)
    // Bigrams over the survivors catch "uber eats", "amazon prime".
    for (i in 0 until signal.size - 1) tokenSet.add("${signal[i]} ${signal[i + 1]}")

    val merchant = signal.joinToString("") { it.replace(RX_NON_LETTER, "") }

    return NormalizedResult(phrase, tokenSet.toList(), merchant)
}

/**
 * keyword -> the user's own category id.
 *
 * Seeds name a category ("Food & Dining"); the ids belong to the user, whose
 * categories may be renamed, translated or merged. Resolution is exact first,
 * then a tolerant contains-match in EITHER direction so a user's "Food" still
 * catches a "Food & Dining" seed and vice versa.
 */
fun buildSeedMap(categories: List<CategoryData>): Map<String, String> {
    val nameToId = LinkedHashMap<String, String>()
    for (c in categories) nameToId[c.name.lowercase()] = c.id

    fun resolve(categoryName: String): String? {
        val lower = categoryName.lowercase()
        nameToId[lower]?.let { return it }
        for (c in categories) {
            val cn = c.name.lowercase()
            if (cn == lower || cn.contains(lower) || lower.contains(cn)) return c.id
        }
        return null
    }

    val map = LinkedHashMap<String, String>()
    for ((keyword, categoryName) in CategorySeeds.SEED_RULES) {
        val id = resolve(categoryName)
        if (id != null) map[keyword] = id
    }
    return map
}

data class SeedEntry(val keyword: String, val categoryId: String)

/**
 * The same resolution as [buildSeedMap], flattened for substring matching
 * against a merchant blob ("swiggylimited" contains "swiggy").
 *
 * LONGEST keyword first, so the most specific merchant wins a tie.
 */
fun buildSeedList(categories: List<CategoryData>): List<SeedEntry> =
    buildSeedMap(categories).map { SeedEntry(it.key, it.value) }
        .sortedByDescending { it.keyword.length }

/**
 * Score a normalised description against learned token rules plus the seeds.
 *
 * Shared by the single-shot and bulk paths so they can never disagree — web
 * factors it out for the same reason.
 */
fun scoreTokens(
    norm: NormalizedResult,
    tokenRules: Map<String, List<CategoryRule>>,
    seedMap: Map<String, String>,
    seedList: List<SeedEntry>,
): String? {
    val scores = LinkedHashMap<String, Long>()
    fun add(catId: String, pts: Long) { scores[catId] = (scores[catId] ?: 0L) + pts }

    // 1. Learned token rules, exact token match.
    for (tok in norm.tokens) {
        tokenRules[tok]?.forEach { add(it.categoryId, it.weight + it.corrections * CORRECTION_BOOST) }
    }

    // 2. Cold-start seeds, exact token match. Worth 2 -- enough on its own.
    for (tok in norm.tokens) {
        seedMap[tok]?.let { add(it, 2L) }
    }

    // 3. Cold-start seeds, substring match on the merchant blob. Catches the
    // mangled names that never tokenise cleanly: "swiggylimited", "amazonin".
    if (norm.merchant.length >= 3) {
        for (entry in seedList) {
            if (entry.keyword.length >= 4 && norm.merchant.contains(entry.keyword)) add(entry.categoryId, 2L)
        }
    }

    var best: String? = null
    var max = 0L
    // Strictly greater, so a tie keeps the FIRST-scored category -- and the
    // insertion order above is web's. A HashMap here would make ties a coin
    // flip that differs between platforms.
    for ((catId, score) in scores) {
        if (score > max) { max = score; best = catId }
    }
    return if (max >= CONFIDENCE_THRESHOLD) best else null
}

/**
 * A preloaded classifier for BULK work — statement import, the auto-categorise
 * job. Built once from every learned rule, then classifies in memory with no
 * further round-trips.
 */
class BulkClassifier(
    rules: List<CategoryRule>,
    categories: List<CategoryData>,
) {
    private val phraseRules = LinkedHashMap<String, String>()
    private val tokenRules = LinkedHashMap<String, MutableList<CategoryRule>>()
    private val seedMap = buildSeedMap(categories)
    private val seedList = buildSeedList(categories)

    init {
        for (r in rules) {
            if (r.kind == "phrase") {
                // First wins, matching web's `if (!phraseRules.has(key))`. The
                // caller decides the order; the repository orders by weight
                // descending, so "first" means "highest weight".
                if (!phraseRules.containsKey(r.key)) phraseRules[r.key] = r.categoryId
            } else {
                tokenRules.getOrPut(r.key) { mutableListOf() }.add(r)
            }
        }
    }

    fun classify(text: String): String? {
        val norm = normalizeText(text)
        if (norm.phrase.isEmpty()) return null
        phraseRules[norm.phrase]?.let { return it }
        if (norm.tokens.isEmpty() && norm.merchant.isEmpty()) return null
        return scoreTokens(norm, tokenRules, seedMap, seedList)
    }
}
