import Foundation
import SwiftUI

/**
 Which destinations sit in the bottom bar's four customizable slots.

 A faithful port of `apps/web/src/navPrefs.ts`, down to the storage key
 (`pc_bottomNav`) and the JSON-array shape, so web, Android and iOS never
 disagree about what a saved preference means.
 */
/// `Equatable` is gone with the string label — a closure cannot be compared,
/// and nothing needed it: the catalog is a constant and rows are keyed by `id`.
struct NavCatalogItem: Identifiable, Sendable {
    let id: String
    let tab: NavTab
    let glyph: String
    /**
     How this item names itself.

     A closure, not a string and not a string key. It used to be both: a `tkey`
     of `"nav.transactions"` that nothing ever resolved, sitting beside an
     English `label` that got rendered directly — so the app shipped English to
     hi and nl while carrying the key that would have fixed it.

     Holding the typed accessor instead means a renamed key fails to compile
     rather than falling back to English at runtime, and there is no second
     string to keep in sync with the first.
     */
    let label: @Sendable () -> String
}

@MainActor
final class NavPrefs: ObservableObject {
    static let shared = NavPrefs()

    /// The 14 destinations eligible for a slot. Home and More are fixed and
    /// deliberately absent, exactly as on web.
    static let catalog: [NavCatalogItem] = [
        NavCatalogItem(id: "transactions", tab: .transactions, glyph: SanvyaIcons.swapHoriz, label: { S.Translation.navTransactions }),
        NavCatalogItem(id: "friends", tab: .splits, glyph: SanvyaIcons.groups, label: { S.Translation.navFriends }),
        NavCatalogItem(id: "insights", tab: .insights, glyph: SanvyaIcons.insights, label: { S.Translation.navInsights }),
        NavCatalogItem(id: "accounts", tab: .accounts, glyph: SanvyaIcons.accountBalance, label: { S.Translation.navAccounts }),
        NavCatalogItem(id: "budgets", tab: .budgets, glyph: SanvyaIcons.donutSmall, label: { S.Translation.navBudgets }),
        NavCatalogItem(id: "goals", tab: .goals, glyph: SanvyaIcons.flag, label: { S.Translation.navGoals }),
        NavCatalogItem(id: "recurring", tab: .recurring, glyph: SanvyaIcons.autorenew, label: { S.Translation.navRecurring }),
        NavCatalogItem(id: "loans", tab: .loans, glyph: SanvyaIcons.requestQuote, label: { S.Translation.navLoans }),
        NavCatalogItem(id: "investments", tab: .investments, glyph: SanvyaIcons.trendingUp, label: { S.Translation.navInvestments }),
        NavCatalogItem(id: "cards", tab: .cards, glyph: SanvyaIcons.creditCard, label: { S.Translation.navCards }),
        NavCatalogItem(id: "statements", tab: .statements, glyph: SanvyaIcons.description, label: { S.Translation.navStatements }),
        NavCatalogItem(id: "search", tab: .search, glyph: SanvyaIcons.search, label: { S.Translation.navSearch }),
        NavCatalogItem(id: "assistant", tab: .assistant, glyph: SanvyaIcons.autoAwesome, label: { S.Translation.navAssistant }),
        NavCatalogItem(id: "settings", tab: .settings, glyph: SanvyaIcons.settings, label: { S.Translation.navSettings }),
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
