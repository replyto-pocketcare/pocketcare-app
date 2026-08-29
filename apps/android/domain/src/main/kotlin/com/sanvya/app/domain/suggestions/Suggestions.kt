package com.sanvya.app.domain.suggestions

/**
 * Which parts of the app is this person not using yet?
 *
 * A port of `packages/core/suggestions` (`@sanvya/suggestions`), which web's
 * dashboard renders as the "Worth a look" strip. Pure and portable: it takes a
 * plain count of what exists and returns an ordered list of feature ids. No DB,
 * no UI, no copy -- the app supplies the counts and i18n supplies the words.
 *
 * THE DESIGN PROBLEM, kept verbatim from the source because it is the whole
 * reason the rules look like this. A "try this" strip is one step from being an
 * ad for your own product, and a finance app is the wrong place to feel nagged.
 * Three rules keep it honest, and every one of them REMOVES suggestions:
 *
 *  1. **Earn the suggestion.** Each feature declares a prerequisite. Telling
 *     someone to split a bill before they have recorded a single transaction is
 *     noise; telling them once they have twenty is a real observation.
 *  2. **Say little.** A wall of nine cards reads as a demand.
 *     [MAX_VISIBLE_SUGGESTIONS] caps what is shown, so the strip stays a nudge.
 *  3. **Dismissal is permanent and per-feature.** "Not interested" has to mean
 *     it, or the strip becomes something to endure rather than read.
 *
 * Mirrors apps/ios/Domain/Sources/Domain/Suggestions.swift.
 */

/**
 * Everything a suggestion can be about.
 *
 * The [id] strings are stable and are what gets persisted in a dismissal, so
 * they match web's own union exactly -- a renamed id would silently un-dismiss
 * a card someone has already said no to.
 */
enum class SuggestionFeature(val id: String) {
    SUBSCRIPTIONS("subscriptions"),
    LOANS("loans"),
    BUDGETS("budgets"),
    GOALS("goals"),
    SPLITS("splits"),
    RECEIPTS("receipts"),
    RECURRING("recurring"),
    INVESTMENTS("investments"),
    CREDIT_CARDS("creditCards");

    companion object {
        /**
         * The known feature for a persisted id, or null.
         *
         * Web's `isFeatureId` guard, in the shape Kotlin actually wants: the
         * caller filters stored dismissals through this so a stale id from an
         * older build cannot linger in the set forever.
         */
        fun fromId(value: String): SuggestionFeature? = values().firstOrNull { it.id == value }
    }
}

/**
 * What the user already has. Every field is a row count; absent means zero.
 *
 * Counts rather than booleans, because a prerequisite is usually "enough of X
 * to make Y worth mentioning", and that threshold differs per feature.
 */
data class UsageCounts(
    val accounts: Int = 0,
    val transactions: Int = 0,
    val subscriptions: Int = 0,
    val loans: Int = 0,
    val budgets: Int = 0,
    val goals: Int = 0,
    val splitGroups: Int = 0,
    val receipts: Int = 0,
    val recurring: Int = 0,
    val holdings: Int = 0,
    val creditCards: Int = 0,
    val creditCardAccounts: Int = 0,
)

/** One row of the catalogue below. */
data class SuggestionRule(
    val id: SuggestionFeature,
    /** Already used it? Then there is nothing to suggest. */
    val used: (UsageCounts) -> Boolean,
    /** Is it worth mentioning yet? */
    val eligible: (UsageCounts) -> Boolean,
    /**
     * Tie-break order, lower first. Roughly "how much difference does this make
     * to someone who is not using it" -- budgets before investments.
     */
    val weight: Int,
    /** Needs a paid plan. Never suggested to a free user -- see [pickSuggestions]. */
    val premium: Boolean = false,
)

/**
 * The catalogue.
 *
 * Prerequisites are deliberately conservative. The failure mode that matters is
 * suggesting something irrelevant -- that teaches the user the strip is worth
 * ignoring, and once learned they never read it again.
 */
val SUGGESTION_RULES: List<SuggestionRule> = listOf(
    SuggestionRule(
        // Nearly everyone has some. Cheap to add, immediately useful, so it leads.
        id = SuggestionFeature.SUBSCRIPTIONS,
        used = { it.subscriptions > 0 },
        eligible = { it.transactions >= 5 },
        weight = 10,
    ),
    SuggestionRule(
        id = SuggestionFeature.BUDGETS,
        used = { it.budgets > 0 },
        // A budget over three transactions is a guess. Wait for a real month.
        eligible = { it.transactions >= 15 },
        weight = 20,
    ),
    SuggestionRule(
        id = SuggestionFeature.RECURRING,
        used = { it.recurring > 0 },
        eligible = { it.transactions >= 15 },
        weight = 30,
    ),
    SuggestionRule(
        // Only if they actually hold a credit-card account -- otherwise it is an ad.
        id = SuggestionFeature.CREDIT_CARDS,
        used = { it.creditCards > 0 },
        eligible = { it.creditCardAccounts > 0 },
        weight = 35,
    ),
    SuggestionRule(
        id = SuggestionFeature.LOANS,
        used = { it.loans > 0 },
        eligible = { it.transactions >= 10 },
        weight = 40,
    ),
    SuggestionRule(
        id = SuggestionFeature.GOALS,
        used = { it.goals > 0 },
        eligible = { it.transactions >= 10 },
        weight = 50,
    ),
    SuggestionRule(
        id = SuggestionFeature.SPLITS,
        used = { it.splitGroups > 0 },
        eligible = { it.transactions >= 10 },
        weight = 60,
    ),
    SuggestionRule(
        id = SuggestionFeature.RECEIPTS,
        used = { it.receipts > 0 },
        eligible = { it.transactions >= 10 },
        weight = 70,
        // Scanning is a Lite/Pro feature, so this is an ad rather than a tip for
        // anyone who cannot reach it.
        premium = true,
    ),
    SuggestionRule(
        id = SuggestionFeature.INVESTMENTS,
        used = { it.holdings > 0 },
        eligible = { it.accounts >= 1 && it.transactions >= 20 },
        weight = 80,
    ),
)

/** How many cards the strip shows at once. A long list reads as a demand. */
const val MAX_VISIBLE_SUGGESTIONS: Int = 5

/**
 * Ordered features to suggest.
 *
 * Returns an empty list freely -- an empty strip is a perfectly good outcome,
 * and the caller is expected to render nothing at all rather than an empty
 * state. "You have used everything" needs no announcement.
 */
fun pickSuggestions(
    usage: UsageCounts,
    dismissed: Set<String> = emptySet(),
    isPaid: Boolean = false,
    max: Int = MAX_VISIBLE_SUGGESTIONS,
): List<SuggestionFeature> {
    // A user with nothing at all is being onboarded, not upsold. The first-run
    // walkthrough owns that moment; a suggestion strip on top of it is clutter.
    if (usage.accounts == 0 && usage.transactions == 0) return emptyList()

    return SUGGESTION_RULES
        .filter { it.id.id !in dismissed }
        .filter { !it.used(usage) }
        .filter { it.eligible(usage) }
        // Suggesting something they would have to pay to touch is an ad, not a tip.
        .filter { !it.premium || isPaid }
        .sortedBy { it.weight }
        .take(if (max < 0) 0 else max)
        .map { it.id }
}
