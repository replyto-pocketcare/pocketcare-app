import Domain
import Foundation

/**
 The last step of the web-path translation: `AppLink` to somewhere in this app.

 Everything ABOVE this — which path means which screen, what the query decodes
 to, which paths are refused — is Domain's and is shared with Android. What is
 here is only the part that genuinely cannot be shared: this app's navigation,
 which is a single `NavTab` plus, for two screens, a payload the target view
 consumes.

 **This shell has no detail routing.** `ContentView` maps a tab to a screen and
 nothing pushes a stack of its own — an account edit, a loan detail and a
 recurring direction are all local state inside their parent list. So a link to
 one of those lands on its PARENT: `/accounts/<id>/edit` opens Accounts, not
 that account. Android navigates precisely because its graph has the routes.
 That difference is real, visible and recorded in ABSENT-BY-DECISION; the
 alternative — refusing the link — would leave the user staring at an action
 chip that does nothing, which is worse than one tap short.

 Mirrors Android's `AppRoutes.kt`.
 */
struct AppDestination {
    let tab: NavTab
    /// A group `SplitsView` should open on arrival.
    let groupId: String?
    /// Filters `SearchView` should start with.
    let searchPrefill: SearchPrefill?

    init(_ tab: NavTab, groupId: String? = nil, searchPrefill: SearchPrefill? = nil) {
        self.tab = tab
        self.groupId = groupId
        self.searchPrefill = searchPrefill
    }
}

/**
 Where `link` lands.

 The switch is exhaustive over `AppScreen` on purpose (no `default`), so adding
 a destination to Domain fails this build until this app decides where it goes,
 instead of silently returning nil and producing a dead link.
 */
func appDestination(for link: AppLink) -> AppDestination? {
    switch link.screen {
    case .dashboard: return AppDestination(.dashboard)

    case .accounts, .accountNew, .accountEdit: return AppDestination(.accounts)
    case .transactions, .transactionNew, .transactionEdit: return AppDestination(.transactions)
    case .budgets: return AppDestination(.budgets)
    case .goals: return AppDestination(.goals)
    case .recurring, .recurringDirection: return AppDestination(.recurring)
    case .loans, .loanDetail: return AppDestination(.loans)
    case .investments: return AppDestination(.investments)
    case .cards: return AppDestination(.cards)

    // Web's Splits screen is `/friends`; this app's tab is `splits`. A group
    // detail is the one deep link this shell CAN honour exactly — `SplitsView`
    // already takes an `openGroupId`, because a just-accepted invite needs it.
    case .splits: return AppDestination(.splits)
    case .groupDetail: return AppDestination(.splits, groupId: link.id)

    case .insights: return AppDestination(.insights)
    case .reflect: return AppDestination(.reflect)
    case .statements, .statementsAnalyze: return AppDestination(.statements)

    // Receipt capture is a sheet over Transactions, not a tab.
    case .receiptNew: return AppDestination(.transactions)

    case .search:
        return AppDestination(.search, searchPrefill: searchPrefillFromQuery(link.query))

    case .notifications: return AppDestination(.notifications)
    case .assistant: return AppDestination(.assistant)
    case .help: return AppDestination(.help)
    case .settings, .settingsData, .settingsCategories, .settingsLabels:
        return AppDestination(.settings)

    // The login screen is the gate ABOVE this shell, reached by signing out —
    // not a destination inside it. Refused rather than mapped to something else.
    case .login: return nil
    }
}

/// Convenience for the callers that hold a raw web path.
func appDestination(forHref href: String) -> AppDestination? {
    guard let link = parseAppLink(href) else { return nil }
    return appDestination(for: link)
}
