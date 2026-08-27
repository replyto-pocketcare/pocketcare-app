import Foundation

/**
 The auto-categoriser: text normalisation, cold-start seeds, learned rules, and
 the scoring that picks a category.

 Ported from `apps/web/src/categorize/normalize.ts` + `engine.ts`. Everything
 here is PURE — the database round-trips web does inline are the caller's job,
 which is what lets the bulk path (statement import) read every rule once and
 then classify a thousand rows with no further I/O, exactly as web's
 `buildClassifier` does.

 The seed tables live in the generated `CategorySeeds`.

 Mirrors Android's Categorize.kt.
 */

/// A learned rule, as stored in `category_rules`.
public struct CategoryRule: Equatable, Sendable {
    /// "phrase" | "token".
    public let kind: String
    public let key: String
    public let categoryId: String
    public let weight: Int64
    public let corrections: Int64

    public init(kind: String, key: String, categoryId: String, weight: Int64, corrections: Int64) {
        self.kind = kind
        self.key = key
        self.categoryId = categoryId
        self.weight = weight
        self.corrections = corrections
    }
}

/// The user's categories, as the seed resolver needs them.
public struct CategoryData: Equatable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct NormalizedResult: Equatable, Sendable {
    /// Full cleaned phrase, used for exact learned-phrase lookups.
    public let phrase: String
    /// Signal tokens plus bigrams, for scoring. Noise removed.
    public let tokens: [String]
    /// Best-guess merchant blob for substring matching: letters only, no spaces.
    public let merchant: String
}

/// If a category reaches this combined weight it is chosen confidently.
/// Phrases never come through here — an exact phrase match wins outright.
public let categorizeConfidenceThreshold: Int64 = 2

/// A user correction is worth five ordinary sightings.
public let categorizeCorrectionBoost: Int64 = 5

/// True if a token is pure noise: a rail code, a bank, a ref word, or mostly digits.
private func isNoise(_ tok: String) -> Bool {
    if tok.isEmpty { return true }
    if CategorySeeds.noiseTokens.contains(tok) { return true }
    if CategorySeeds.stopWords.contains(tok) { return true }
    // Reference numbers and long alphanumerics carry no signal.
    // Web writes this as `/\d/.test(tok) && digitCount >= 4`; the first half is
    // implied by the second, and the count is the whole test.
    let digits = tok.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
    return digits >= 4
}

/**
 Normalise a description: lowercase, split on the many delimiters banks use,
 drop noise and reference tokens, and return the surviving merchant tokens plus
 a concatenated blob for substring matching.

 Digits INSIDE a merchant name ("5paisa") are preserved deliberately — the digit
 test above is about reference numbers, and a blanket digit strip would lose a
 real merchant.
 */
public func normalizeText(_ text: String) -> NormalizedResult {
    if text.isEmpty { return NormalizedResult(phrase: "", tokens: [], merchant: "") }

    let lower = text.lowercased()

    // A cleaned phrase for exact learned-phrase matching. Keep this stable, or
    // every rule a user has already taught the app stops resolving.
    var phrase = regexReplace(lower, "[^\\p{L}\\p{N}\\s]", " ")
    phrase = regexReplace(phrase, "\\s+", " ").trimmingCharacters(in: .whitespaces)

    let parts = splitByRegex(lower, "[\\s/\\-*:|.,;#@()\\[\\]]+")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

    // Keep tokens with signal: at least 3 letters, not noise.
    var signal: [String] = []
    for p in parts {
        if lettersOnly(p).count < 3 { continue }
        if isNoise(p) { continue }
        signal.append(p)
    }

    // Insertion-ordered and deduplicated, because web builds a Set and then
    // `Array.from`s it. The order reaches scoring, so it matters.
    var seen = Set<String>()
    var tokens: [String] = []
    func addToken(_ t: String) {
        if seen.insert(t).inserted { tokens.append(t) }
    }
    for s in signal { addToken(s) }
    // Bigrams over the survivors catch "uber eats", "amazon prime".
    if signal.count > 1 {
        for i in 0..<(signal.count - 1) { addToken("\(signal[i]) \(signal[i + 1])") }
    }

    let merchant = signal.map(lettersOnly).joined()

    return NormalizedResult(phrase: phrase, tokens: tokens, merchant: merchant)
}

private func lettersOnly(_ s: String) -> String {
    String(String.UnicodeScalarView(s.unicodeScalars.filter { CharacterSet.letters.contains($0) }))
}

private func splitByRegex(_ s: String, _ pattern: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [s] }
    let ns = s as NSString
    var out: [String] = []
    var last = 0
    regex.enumerateMatches(in: s, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
        guard let m else { return }
        out.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
        last = m.range.location + m.range.length
    }
    out.append(ns.substring(from: last))
    return out
}

/**
 keyword → the user's own category id.

 Seeds name a category ("Food & Dining"); the ids belong to the user, whose
 categories may be renamed, translated or merged. Resolution is exact first,
 then a tolerant contains-match in EITHER direction so a user's "Food" still
 catches a "Food & Dining" seed and vice versa.
 */
public func buildSeedMap(_ categories: [CategoryData]) -> [(keyword: String, categoryId: String)] {
    var nameToId: [String: String] = [:]
    for c in categories { nameToId[c.name.lowercased()] = c.id }

    func resolve(_ categoryName: String) -> String? {
        let lower = categoryName.lowercased()
        if let exact = nameToId[lower] { return exact }
        for c in categories {
            let cn = c.name.lowercased()
            if cn == lower || cn.contains(lower) || lower.contains(cn) { return c.id }
        }
        return nil
    }

    // Returned as an ordered ARRAY, not a Dictionary: web iterates the seed map
    // in insertion order and the tie-break in `scoreTokens` depends on it.
    var out: [(keyword: String, categoryId: String)] = []
    for entry in CategorySeeds.seedRules {
        if let id = resolve(entry.category) { out.append((entry.keyword, id)) }
    }
    return out
}

public struct SeedEntry: Equatable, Sendable {
    public let keyword: String
    public let categoryId: String
}

/**
 The same resolution as `buildSeedMap`, flattened for substring matching against
 a merchant blob ("swiggylimited" contains "swiggy").

 LONGEST keyword first, so the most specific merchant wins a tie.
 */
public func buildSeedList(_ categories: [CategoryData]) -> [SeedEntry] {
    let rows = buildSeedMap(categories).map { SeedEntry(keyword: $0.keyword, categoryId: $0.categoryId) }
    return stableSorted(rows) { $0.keyword.count > $1.keyword.count }
}

/**
 Score a normalised description against learned token rules plus the seeds.

 Shared by the single-shot and bulk paths so they can never disagree — web
 factors it out for the same reason.
 */
public func scoreTokens(
    _ norm: NormalizedResult,
    tokenRules: [String: [CategoryRule]],
    seedMap: [(keyword: String, categoryId: String)],
    seedList: [SeedEntry]
) -> String? {
    // Insertion-ordered scores: a tie keeps the FIRST-scored category, and a
    // Dictionary walk here would make that a coin flip that differs between
    // platforms and between runs.
    var order: [String] = []
    var scores: [String: Int64] = [:]
    func add(_ catId: String, _ pts: Int64) {
        if scores[catId] == nil { order.append(catId) }
        scores[catId] = (scores[catId] ?? 0) + pts
    }

    // 1. Learned token rules, exact token match.
    for tok in norm.tokens {
        for r in tokenRules[tok] ?? [] {
            add(r.categoryId, r.weight + r.corrections * categorizeCorrectionBoost)
        }
    }

    // 2. Cold-start seeds, exact token match. Worth 2 — enough on its own.
    let seedLookup = Dictionary(seedMap.map { ($0.keyword, $0.categoryId) }, uniquingKeysWith: { first, _ in first })
    for tok in norm.tokens {
        if let cat = seedLookup[tok] { add(cat, 2) }
    }

    // 3. Cold-start seeds, substring match on the merchant blob. Catches the
    // mangled names that never tokenise cleanly: "swiggylimited", "amazonin".
    if norm.merchant.count >= 3 {
        for entry in seedList where entry.keyword.count >= 4 && norm.merchant.contains(entry.keyword) {
            add(entry.categoryId, 2)
        }
    }

    var best: String?
    var maxScore: Int64 = 0
    for catId in order {
        let score = scores[catId] ?? 0
        if score > maxScore { maxScore = score; best = catId }
    }
    return maxScore >= categorizeConfidenceThreshold ? best : nil
}

/**
 A preloaded classifier for BULK work — statement import, the auto-categorise
 job. Built once from every learned rule, then classifies in memory with no
 further round-trips.
 */
public struct BulkClassifier: Sendable {
    private let phraseRules: [String: String]
    private let tokenRules: [String: [CategoryRule]]
    private let seedMap: [(keyword: String, categoryId: String)]
    private let seedList: [SeedEntry]

    public init(rules: [CategoryRule], categories: [CategoryData]) {
        var phrases: [String: String] = [:]
        var tokens: [String: [CategoryRule]] = [:]
        for r in rules {
            if r.kind == "phrase" {
                // First wins, matching web's `if (!phraseRules.has(key))`. The
                // caller decides the order; the repository orders by weight
                // descending, so "first" means "highest weight".
                if phrases[r.key] == nil { phrases[r.key] = r.categoryId }
            } else {
                tokens[r.key, default: []].append(r)
            }
        }
        phraseRules = phrases
        tokenRules = tokens
        seedMap = buildSeedMap(categories)
        seedList = buildSeedList(categories)
    }

    public func classify(_ text: String) -> String? {
        let norm = normalizeText(text)
        if norm.phrase.isEmpty { return nil }
        if let hit = phraseRules[norm.phrase] { return hit }
        if norm.tokens.isEmpty && norm.merchant.isEmpty { return nil }
        return scoreTokens(norm, tokenRules: tokenRules, seedMap: seedMap, seedList: seedList)
    }
}
