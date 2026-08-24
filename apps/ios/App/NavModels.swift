import Foundation

/**
 Every destination the shell can show.

 One case per live web route — `/templates` and `/cashflow` are gone from
 `apps/web/app`, so their cases and placeholder screens went with them rather
 than lingering as dead ends the bottom-bar customizer could still surface.

 The nav *catalog* (which of these can sit in the bottom bar) lives in
 `Shell/NavPrefs.swift`; the grouped list lives in `Shell/MoreSheet.swift`,
 both mirroring web's `AppShell.tsx`. This enum is only the address space.
 */
enum NavTab: String, CaseIterable, Equatable {
    case dashboard
    case assistant

    case accounts
    case transactions
    case cards
    case splits
    case search

    case budgets
    case goals
    case recurring
    case loans

    case investments
    case reflect
    case insights
    case statements

    case settings
    case help

    /// Renders as its own row ABOVE the titled groups in the More sheet (web
    /// AppShell.tsx:303), not inside `navGroups` — still a real destination,
    /// just a different position in the list.
    case notifications
}
