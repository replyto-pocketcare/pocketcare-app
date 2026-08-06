import Foundation

enum NavTab: String, CaseIterable, Equatable {
    case dashboard
    case assistant

    case accounts
    case transactions
    case templates
    case cards
    case splits
    case search

    case budgets
    case goals
    case cashflow
    case recurring
    case loans

    case investments
    case reflect
    case insights
    case statements

    case settings
    case help

    /// Renders as its own row ABOVE the titled groups (web AppShell.tsx:303,
    /// Android's separate `notificationsDrawerItem`), not inside `navGroups`
    /// -- still a real NavTab/destination, just a different position in the
    /// drawer's layout. See DrawerMenuView.swift.
    case notifications
}

struct NavItem: Identifiable, Equatable {
    let id = UUID()
    let tab: NavTab
    let label: String
    let icon: String
}

struct NavGroup: Identifiable {
    let id = UUID()
    let title: String
    let items: [NavItem]
}

let navGroups: [NavGroup] = [
    NavGroup(title: "", items: [
        NavItem(tab: .dashboard, label: "Dashboard", icon: "square.grid.2x2"),
        NavItem(tab: .assistant, label: "Ask Sanvya", icon: "sparkles")
    ]),
    NavGroup(title: "Money", items: [
        NavItem(tab: .accounts, label: "Accounts", icon: "building.columns"),
        NavItem(tab: .transactions, label: "Transactions", icon: "arrow.left.arrow.right"),
        NavItem(tab: .templates, label: "Templates", icon: "bookmark"),
        NavItem(tab: .cards, label: "Cards", icon: "creditcard"),
        NavItem(tab: .splits, label: "Splits & groups", icon: "person.2"),
        NavItem(tab: .search, label: "Search", icon: "magnifyingglass")
    ]),
    NavGroup(title: "Planning", items: [
        NavItem(tab: .budgets, label: "Budgets", icon: "chart.pie"),
        NavItem(tab: .goals, label: "Goals", icon: "flag"),
        NavItem(tab: .cashflow, label: "Planned Cashflow", icon: "chart.bar"),
        NavItem(tab: .recurring, label: "Recurring", icon: "arrow.triangle.2.circlepath"),
        NavItem(tab: .loans, label: "Loans", icon: "banknote")
    ]),
    NavGroup(title: "Growth", items: [
        NavItem(tab: .investments, label: "Investments", icon: "chart.bar"),
        NavItem(tab: .reflect, label: "Reflect", icon: "figure.mind.and.body"),
        NavItem(tab: .insights, label: "Insights", icon: "lightbulb"),
        NavItem(tab: .statements, label: "Statements", icon: "doc.plaintext")
    ]),
    NavGroup(title: "", items: [
        NavItem(tab: .settings, label: "Settings", icon: "gearshape"),
        NavItem(tab: .help, label: "Help & FAQ", icon: "questionmark.circle")
    ])
]
