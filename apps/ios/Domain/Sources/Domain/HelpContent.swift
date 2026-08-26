// GENERATED FILE — do not hand-edit.
// Source: apps/web/app/help/page.tsx (SECTIONS)
// Regenerate with: node tools/parity/generate-help.mjs

/// One question and its answer.
public struct HelpItem: Equatable, Sendable, Identifiable {
    public let question: String
    public let answer: String
    public var id: String { question }

    public init(_ question: String, _ answer: String) {
        self.question = question
        self.answer = answer
    }
}

/// One FAQ section: an icon, its accent colour, a title, and its questions.
public struct HelpSection: Equatable, Sendable, Identifiable {
    /// Web's own icon name — look it up in `SanvyaIcons.byWebName`.
    public let icon: String
    /// `#RRGGBB`, straight from web.
    public let color: String
    public let title: String
    public let items: [HelpItem]
    public var id: String { title }

    public init(icon: String, color: String, title: String, items: [HelpItem]) {
        self.icon = icon
        self.color = color
        self.title = title
        self.items = items
    }
}

/**
 * The Help FAQ, exactly as web writes it.
 *
 * English on all three platforms because it is English on web: every string
 * here is a literal in that component rather than a key in the i18n package.
 * Generating it is what keeps the three copies identical rather than merely
 * similar — see tools/parity/generate-help.mjs.
 */
public let helpSectionsAll: [HelpSection] = [
    HelpSection(
        icon: "space_dashboard",
        color: "#b06a4f",
        title: "Getting started",
        items: [
            HelpItem("What is Sanvya?", "An offline-first personal expense & wealth manager. Your data lives on your device and syncs securely — you can use most of the app with no connection."),
            HelpItem("How do I begin?", "Add your first account (bank, cash, card, or investments) from the Dashboard or Accounts page. Then start logging transactions. Set your base currency in Settings."),
            HelpItem("Can I install it like an app?", "Yes — on mobile or desktop use your browser's “Install app” / “Add to Home Screen” option (or the Install button in the sidebar) for a full-screen, offline experience."),
            HelpItem("Does it work offline?", "Yes. You can add and edit accounts, transactions, budgets, goals and splits offline; everything syncs the next time you're online."),
        ]
    ),
    HelpSection(
        icon: "swap_horiz",
        color: "#5f7a52",
        title: "Transactions",
        items: [
            HelpItem("How do I add a transaction?", "Tap Add transaction, choose Expense / Income / Transfer, enter the amount, pick an account and (optionally) a category, labels and a note."),
            HelpItem("Can one transaction have multiple items?", "Yes — on an expense, use “Add item / split” to break a bill into named items; the total is their sum."),
            HelpItem("Can I back-date a transaction?", "Yes, set the Date field when adding it. Balances recompute from your ledger automatically."),
            HelpItem("Can I import or export my data?", "Settings → Import & export. Export all transactions to CSV, or import from a CSV (including a Wallet-by-BudgetBakers importer). New accounts and categories are created automatically."),
        ]
    ),
    HelpSection(
        icon: "donut_small",
        color: "#c08a3e",
        title: "Budgets",
        items: [
            HelpItem("How do budgets work?", "Create a spending cap for a period (weekly/monthly/etc.) or for custom dates. Scope it to specific categories or labels, or leave it open for all spending."),
            HelpItem("Will it warn me before I overspend?", "Budgets flag at ~80% used and when you go over — and you'll see it surfaced in the Insights feed too."),
        ]
    ),
    HelpSection(
        icon: "flag",
        color: "#3e4a38",
        title: "Goals & emergency fund",
        items: [
            HelpItem("How do savings goals work?", "Create a goal with a target (e.g. a trip or a phone), then “Add funds” to reserve money from a savings account toward it. The reserved amount is blocked from your available balance."),
            HelpItem("What's the emergency fund for?", "Mark one goal as your emergency fund — it's kept liquid and filled first, and your other goals unlock once it's funded."),
        ]
    ),
    HelpSection(
        icon: "autorenew",
        color: "#7c4a3a",
        title: "Subscriptions",
        items: [
            HelpItem("How do I track subscriptions?", "Subscriptions page → Add subscription. See your total monthly and yearly load at a glance."),
            HelpItem("What is “Before you subscribe…”?", "A simulator (Premium) that shows a new subscription's true long-term cost versus investing that money instead — before you commit."),
        ]
    ),
    HelpSection(
        icon: "call_split",
        color: "#b06a4f",
        title: "Splits & friends",
        items: [
            HelpItem("How do I split a bill?", "Open Add transaction → turn on “Split this expense” → pick a group/trip → choose who's in and how to split (equally, exact amounts, or percentages) → mark who paid. Only your own share counts in your budget; the rest is tracked as owed or lent."),
            HelpItem("How do I add friends?", "Everyone in a split must be in a shared group. Go to Groups & trips → open a group → Invite by email (they're added instantly if they're on Sanvya) or share an invite link. They join, then you can split with them."),
            HelpItem("Where do I see who owes whom?", "The Friends page shows your net balance with each person — who owes you and who you owe — across all groups, plus a per-group view inside each group."),
            HelpItem("How do I settle up?", "On Friends, tap Settle next to a person. Record the repayment into an account, or choose “None” to just mark it settled without moving money."),
            HelpItem("Can a trip split automatically?", "Yes — give a trip a date range and turn on auto-split. Any expense you add within those dates is split equally with the group (you can turn it off per transaction)."),
            HelpItem("Is my private data shared with friends?", "No. Friends only see the shared fact — the amount, who paid, and each person's share. Your accounts, payment method and categories are never shared."),
        ]
    ),
    HelpSection(
        icon: "credit_card",
        color: "#5f6647",
        title: "Cards & accounts",
        items: [
            HelpItem("Can I track credit cards?", "Yes — add a Credit Card account and its details on the Cards page. Balances and spending are tracked like any other account."),
            HelpItem("What about investments?", "Stocks and mutual-fund accounts are supported; money moves in and out via transfers, and holdings are tracked separately."),
            HelpItem("How is net worth calculated?", "It's the sum of your accounts' ledger-derived balances. You can toggle any account in or out of net worth from the Dashboard."),
        ]
    ),
    HelpSection(
        icon: "insights",
        color: "#4f46e5",
        title: "Insights & statements",
        items: [
            HelpItem("What is the Insights feed?", "A swipeable, TikTok-style stack of bite-sized cards — weekly recaps, budget alerts, spending patterns, savings wins and more, drawn from your own data. It's a Premium feature."),
            HelpItem("How do statements work?", "Statements (Premium) generates a clean summary for any date range that you can print or save as a PDF."),
        ]
    ),
    HelpSection(
        icon: "auto_awesome",
        color: "#b06a4f",
        title: "Ask Sanvya (AI)",
        items: [
            HelpItem("What can the assistant do?", "It helps you use the app and think through your own money — and can create goals, budgets, subscriptions and groups, reserve money to a goal, and log a transaction (always asking you to confirm first)."),
            HelpItem("What data does it see?", "Only an aggregated on-device snapshot (balances, average income/expense, goals, upcoming bills, split totals) — never your individual transactions. It won't write or explain code or give tax/legal/investment advice."),
            HelpItem("What are AI credits?", "Each plan includes a monthly prompt quota; you can buy extra credit packs that never expire. Free users don't have the assistant."),
        ]
    ),
    HelpSection(
        icon: "redeem",
        color: "#a8503a",
        title: "Premium & billing",
        items: [
            HelpItem("What are the plans?", "Free (all core money tracking), Lite (₹49/mo or ₹499/yr) and Pro (₹99/mo or ₹999/yr). Lite and Pro unlock Insights, Statements, Ask Sanvya, auto-categorisation and more; Pro has a larger AI quota."),
            HelpItem("Is there a trial?", "New accounts get a 14-day free trial with full access. You'll see a countdown and can upgrade anytime from Settings."),
            HelpItem("Can I cancel or get invoices?", "Yes — cancel anytime from Settings → Plan & billing (you keep access until the cycle ends). Every payment has a downloadable invoice in your billing history."),
        ]
    ),
    HelpSection(
        icon: "health_and_safety",
        color: "#7c7264",
        title: "Privacy & sync",
        items: [
            HelpItem("Where is my data stored?", "Locally on your device first, then synced to your private account. Each person only ever syncs their own rows (plus the shared split facts of groups they're in)."),
            HelpItem("Is splitting safe for privacy?", "Yes — shared split tables carry no private data. Your accounts, categories and personal transactions stay entirely yours."),
        ]
    ),
]
