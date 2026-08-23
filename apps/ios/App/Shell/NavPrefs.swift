import Foundation
import SwiftUI

/**
 Which destinations sit in the bottom bar's four customizable slots.

 A faithful port of `apps/web/src/navPrefs.ts`, down to the storage key
 (`pc_bottomNav`) and the JSON-array shape, so web, Android and iOS never
 disagree about what a saved preference means.
 */
struct NavCatalogItem: Identifiable, Equatable {
    let id: String
    let tab: NavTab
    /// The i18n key web passes to `t()`.
    let tkey: String
    /// English fallback, matching web's second argument to `t()`.
    let label: String
    let glyph: String
}

@MainActor
final class NavPrefs: ObservableObject {
    static let shared = NavPrefs()

    /// The 14 destinations eligible for a slot. Home and More are fixed and
    /// deliberately absent, exactly as on web.
    static let catalog: [NavCatalogItem] = [
        NavCatalogItem(id: "transactions", tab: .transactions, tkey: "nav.transactions", label: "Transactions", glyph: SanvyaIcons.swapHoriz),
        NavCatalogItem(id: "friends", tab: .splits, tkey: "nav.friends", label: "Shared", glyph: SanvyaIcons.groups),
        NavCatalogItem(id: "insights", tab: .insights, tkey: "nav.insights", label: "Insights", glyph: SanvyaIcons.insights),
        NavCatalogItem(id: "accounts", tab: .accounts, tkey: "nav.accounts", label: "Accounts", glyph: SanvyaIcons.accountBalance),
        NavCatalogItem(id: "budgets", tab: .budgets, tkey: "nav.budgets", label: "Budgets", glyph: SanvyaIcons.donutSmall),
        NavCatalogItem(id: "goals", tab: .goals, tkey: "nav.goals", label: "Goals", glyph: SanvyaIcons.flag),
        NavCatalogItem(id: "recurring", tab: .recurring, tkey: "nav.recurring", label: "Recurring", glyph: SanvyaIcons.autorenew),
        NavCatalogItem(id: "loans", tab: .loans, tkey: "nav.loans", label: "Loans", glyph: SanvyaIcons.requestQuote),
        NavCatalogItem(id: "investments", tab: .investments, tkey: "nav.investments", label: "Investments", glyph: SanvyaIcons.trendingUp),
        NavCatalogItem(id: "cards", tab: .cards, tkey: "nav.cards", label: "Cards", glyph: SanvyaIcons.creditCard),
        NavCatalogItem(id: "statements", tab: .statements, tkey: "nav.statements", label: "Statements", glyph: SanvyaIcons.description),
        NavCatalogItem(id: "search", tab: .search, tkey: "nav.search", label: "Search", glyph: SanvyaIcons.search),
        NavCatalogItem(id: "assistant", tab: .assistant, tkey: "nav.assistant", label: "Ask Sanvya", glyph: SanvyaIcons.autoAwesome),
        NavCatalogItem(id: "settings", tab: .settings, tkey: "nav.settings", label: "Settings", glyph: SanvyaIcons.settings),
    ]

    static let defaultIds = ["transactions", "accounts", "friends", "insights"]
    static let slots = 4

    private static let key = "pc_bottomNav"
    private let defaults = UserDefaults.standard

    @Published private(set) var ids: [String]

    private init() {
        ids = NavPrefs.read(from: UserDefaults.standard)
    }

    func setIds(_ ids: [String]) {
        let clean = NavPrefs.sanitize(ids)
        if let data = try? JSONSerialization.data(withJSONObject: clean),
           let json = String(data: data, encoding: .utf8) {
            defaults.set(json, forKey: NavPrefs.key)
        }
        self.ids = clean
    }

    func items(for ids: [String]) -> [NavCatalogItem] {
        ids.compactMap { id in NavPrefs.catalog.first { $0.id == id } }
    }

    private static func read(from defaults: UserDefaults) -> [String] {
        guard let json = defaults.string(forKey: key),
              let data = json.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else { return defaultIds }
        return sanitize(raw.compactMap { $0 as? String })
    }

    /**
     Port of web's `sanitize()` — drop unknown ids, dedupe, take the first four,
     fall back to the defaults when nothing survives, and **top up from the
     defaults when the list is short**.

     That last step is not defensive padding. A preference saved before the bar
     grew to four slots holds three ids, and rendering it as-is leaves one side
     of the bar short — the lopsided layout this design replaced.
     */
    static func sanitize(_ ids: [String]) -> [String] {
        let valid = ids.filter { id in catalog.contains { $0.id == id } }
        var deduped: [String] = []
        for id in valid where !deduped.contains(id) && deduped.count < slots {
            deduped.append(id)
        }
        if deduped.isEmpty { return defaultIds }
        for id in defaultIds where deduped.count < slots && !deduped.contains(id) {
            deduped.append(id)
        }
        return deduped
    }
}
