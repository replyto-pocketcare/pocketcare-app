import Foundation

/// Which parts of the app is this person not using yet?
///
/// A port of `packages/core/suggestions` (`@sanvya/suggestions`), which web's
/// dashboard renders as the "Worth a look" strip. Pure and portable: it takes a
/// plain count of what exists and returns an ordered list of features. No DB, no
/// UI, no copy — the app supplies the counts and i18n supplies the words.
///
/// THE DESIGN PROBLEM, kept verbatim from the source because it is the whole
/// reason the rules look like this. A "try this" strip is one step from being an
/// ad for your own product, and a finance app is the wrong place to feel nagged.
/// Three rules keep it honest, and every one of them REMOVES suggestions:
///
///  1. **Earn the suggestion.** Each feature declares a prerequisite. Telling
///     someone to split a bill before they have recorded a single transaction is
///     noise; telling them once they have twenty is a real observation.
///  2. **Say little.** A wall of nine cards reads as a demand.
///     ``maxVisibleSuggestions`` caps what is shown, so the strip stays a nudge.
///  3. **Dismissal is permanent and per-feature.** "Not interested" has to mean
///     it, or the strip becomes something to endure rather than read.
///
/// Mirrors apps/android/domain/.../suggestions/Suggestions.kt.

/// Everything a suggestion can be about.
///
/// The raw values are stable and are what gets persisted in a dismissal, so they
/// match web's own union exactly — a renamed id would silently un-dismiss a card
/// someone has already said no to.
public enum SuggestionFeature: String, CaseIterable, Sendable {
    case subscriptions
    case loans
    case budgets
    case goals
    case splits
    case receipts
    case recurring
    case investments
    case creditCards
}

/// What the user already has. Every field is a row count; absent means zero.
///
/// Counts rather than booleans, because a prerequisite is usually "enough of X
/// to make Y worth mentioning", and that threshold differs per feature.
public struct UsageCounts: Equatable, Sendable {
    public var accounts: Int
    public var transactions: Int
    public var subscriptions: Int
    public var loans: Int
    public var budgets: Int
    public var goals: Int
    public var splitGroups: Int
    public var receipts: Int
    public var recurring: Int
    public var holdings: Int
    public var creditCards: Int
    public var creditCardAccounts: Int

    public init(
        accounts: Int = 0,
        transactions: Int = 0,
        subscriptions: Int = 0,
        loans: Int = 0,
        budgets: Int = 0,
        goals: Int = 0,
        splitGroups: Int = 0,
        receipts: Int = 0,
        recurring: Int = 0,
        holdings: Int = 0,
        creditCards: Int = 0,
        creditCardAccounts: Int = 0
    ) {
        self.accounts = accounts
        self.transactions = transactions
        self.subscriptions = subscriptions
        self.loans = loans
        self.budgets = budgets
        self.goals = goals
        self.splitGroups = splitGroups
        self.receipts = receipts
        self.recurring = recurring
        self.holdings = holdings
        self.creditCards = creditCards
        self.creditCardAccounts = creditCardAccounts
    }
}

/// One row of the catalogue below.
///
/// The two predicates are `@Sendable` so the whole rule table can be a global
/// `let` under strict concurrency — a plain closure would make the struct
/// non-Sendable and the table an unsafe global.
public struct SuggestionRule: Sendable {
    public let id: SuggestionFeature
    /// Already used it? Then there is nothing to suggest.
    public let used: @Sendable (UsageCounts) -> Bool
    /// Is it worth mentioning yet?
    public let eligible: @Sendable (UsageCounts) -> Bool
    /// Tie-break order, lower first. Roughly "how much difference does this make
    /// to someone who is not using it" — budgets before investments.
    public let weight: Int
    /// Needs a paid plan. Never suggested to a free user — see ``pickSuggestions``.
    public let premium: Bool

    public init(
        id: SuggestionFeature,
        used: @escaping @Sendable (UsageCounts) -> Bool,
        eligible: @escaping @Sendable (UsageCounts) -> Bool,
        weight: Int,
        premium: Bool = false
    ) {
        self.id = id
        self.used = used
        self.eligible = eligible
        self.weight = weight
        self.premium = premium
    }
}

/// The catalogue.
///
/// Prerequisites are deliberately conservative. The failure mode that matters is
/// suggesting something irrelevant — that teaches the user the strip is worth
/// ignoring, and once learned they never read it again.
public let suggestionRules: [SuggestionRule] = [
    SuggestionRule(
        // Nearly everyone has some. Cheap to add, immediately useful, so it leads.
        id: .subscriptions,
        used: { $0.subscriptions > 0 },
        eligible: { $0.transactions >= 5 },
        weight: 10
    ),
    SuggestionRule(
        id: .budgets,
        used: { $0.budgets > 0 },
        // A budget over three transactions is a guess. Wait for a real month.
        eligible: { $0.transactions >= 15 },
        weight: 20
    ),
    SuggestionRule(
        id: .recurring,
        used: { $0.recurring > 0 },
        eligible: { $0.transactions >= 15 },
        weight: 30
    ),
    SuggestionRule(
        // Only if they actually hold a credit-card account — otherwise it is an ad.
        id: .creditCards,
        used: { $0.creditCards > 0 },
        eligible: { $0.creditCardAccounts > 0 },
        weight: 35
    ),
    SuggestionRule(
        id: .loans,
        used: { $0.loans > 0 },
        eligible: { $0.transactions >= 10 },
        weight: 40
    ),
    SuggestionRule(
        id: .goals,
        used: { $0.goals > 0 },
        eligible: { $0.transactions >= 10 },
        weight: 50
    ),
    SuggestionRule(
        id: .splits,
        used: { $0.splitGroups > 0 },
        eligible: { $0.transactions >= 10 },
        weight: 60
    ),
    SuggestionRule(
        id: .receipts,
        used: { $0.receipts > 0 },
        eligible: { $0.transactions >= 10 },
        weight: 70,
        // Scanning is a Lite/Pro feature, so this is an ad rather than a tip for
        // anyone who cannot reach it.
        premium: true
    ),
    SuggestionRule(
        id: .investments,
        used: { $0.holdings > 0 },
        eligible: { $0.accounts >= 1 && $0.transactions >= 20 },
        weight: 80
    ),
]

/// How many cards the strip shows at once. A long list reads as a demand.
public let maxVisibleSuggestions: Int = 5

/// Ordered features to suggest.
///
/// Returns an empty array freely — an empty strip is a perfectly good outcome,
/// and the caller is expected to render nothing at all rather than an empty
/// state. "You have used everything" needs no announcement.
///
/// `sorted(by:)` is NOT used on the weights alone: Swift's sort is not stable,
/// and two rules with the same weight would then be free to swap between runs.
/// The weights in ``suggestionRules`` are all distinct, so comparing them is
/// already a total order — this is written as a strict `<` on weight so that
/// stays true by construction rather than by luck.
public func pickSuggestions(
    usage: UsageCounts,
    dismissed: Set<String> = [],
    isPaid: Bool = false,
    max: Int = maxVisibleSuggestions
) -> [SuggestionFeature] {
    // A user with nothing at all is being onboarded, not upsold. The first-run
    // walkthrough owns that moment; a suggestion strip on top of it is clutter.
    if usage.accounts == 0 && usage.transactions == 0 { return [] }

    let picked = suggestionRules
        .filter { !dismissed.contains($0.id.rawValue) }
        .filter { !$0.used(usage) }
        .filter { $0.eligible(usage) }
        // Suggesting something they would have to pay to touch is an ad, not a tip.
        .filter { !$0.premium || isPaid }
        .sorted { $0.weight < $1.weight }
        .map { $0.id }

    return Array(picked.prefix(Swift.max(0, max)))
}
