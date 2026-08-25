import Foundation
import SwiftUI

/**
 Which tiles are on the dashboard, in what order, and how wide each one is.

 A faithful port of `apps/web/src/dashboard.ts`, down to the two storage keys
 (`dashboardTiles`, `dashboardTileSizes`) and the JSON shapes, so a saved
 dashboard means the same thing wherever it is read. Same pattern as
 `NavPrefs` — an `ObservableObject` singleton over `UserDefaults`.

 **This is per-device and does not sync**, and that is web's behaviour too:
 `dashboard.ts` writes to localStorage, not to a table. Putting the native copy
 in the database "because we can" would make two devices disagree about a
 preference the browser has always kept to itself.

 Web stores a **third** key, `dashboardTileSpans`, plus `TileSpan`,
 `setTileSpan`, `useTileSpans`, `H_ROWS` and `isTileEnabled`. Every one of them
 is exported and unimported — a first sizing attempt that the `{w,h}` system
 replaced and nobody deleted. None of it is ported.
 */
@MainActor
final class DashboardPrefs: ObservableObject {
    static let shared = DashboardPrefs()

    /// Enabled tiles, in the user's chosen order.
    @Published private(set) var ids: [TileId]

    /// Per-tile width overrides. A tile with no entry uses ``defaultWidth``.
    @Published private(set) var widths: [TileId: TileWidth]

    /// The width a tile starts at.
    ///
    /// Web's grid is four columns wide and its default size is `md` (two of
    /// them) — half the row. An iPhone renders one column whatever this says,
    /// so the value only becomes visible on an iPad, which is exactly where a
    /// wrong default would look worst.
    static let defaultWidth: TileWidth = .md

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ids = DashboardPrefs.readIds(from: defaults)
        widths = DashboardPrefs.readWidths(from: defaults)
    }

    func width(of id: TileId) -> TileWidth { widths[id] ?? DashboardPrefs.defaultWidth }

    /// Add or remove a tile. Adding appends, which keeps a custom order intact.
    func setEnabled(_ id: TileId, _ on: Bool) {
        if on {
            guard !ids.contains(id) else { return }
            write(ids + [id])
        } else {
            write(ids.filter { $0 != id })
        }
    }

    /// Persist an explicit order — drag, or the move-up/move-down buttons.
    func reorder(_ ordered: [TileId]) {
        var seen = Set<TileId>()
        write(ordered.filter { seen.insert($0).inserted })
    }

    /// Move one tile by one position. Returns false at either end.
    @discardableResult
    func move(_ id: TileId, by delta: Int) -> Bool {
        guard let from = ids.firstIndex(of: id) else { return false }
        let to = from + delta
        guard to >= 0, to < ids.count else { return false }
        var next = ids
        next.remove(at: from)
        next.insert(id, at: to)
        write(next)
        return true
    }

    func setWidth(_ id: TileId, _ width: TileWidth) {
        var next = widths
        next[id] = width
        // Web stores {w,h}. Only `w` is ever read back — `H_ROWS` exists but
        // nothing uses it, and row height is measured from content instead. The
        // `h` is written so a dashboard saved on a phone still parses in the
        // browser, rather than tripping web's `isDim(s.h)` guard and being
        // dropped whole.
        let payload = next.reduce(into: [String: [String: String]]()) { acc, pair in
            acc[pair.key.rawValue] = ["w": pair.value.rawValue, "h": "md"]
        }
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let json = String(data: data, encoding: .utf8) {
            defaults.set(json, forKey: tileSizeKey)
        }
        widths = next
    }

    private func write(_ next: [TileId]) {
        if let data = try? JSONSerialization.data(withJSONObject: next.map(\.rawValue)),
           let json = String(data: data, encoding: .utf8) {
            defaults.set(json, forKey: tileOrderKey)
        }
        ids = next
    }

    private static func readIds(from defaults: UserDefaults) -> [TileId] {
        guard let raw = defaults.string(forKey: tileOrderKey),
              let data = raw.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else { return defaultTileIds }
        // Preserve the chosen ORDER; drop unknown ids and duplicates. An empty
        // saved list is a real state — the user removed every tile — and must
        // NOT fall back to the defaults, or a tile they deleted comes back on
        // the next launch.
        var seen = Set<TileId>()
        return array
            .compactMap { $0 as? String }
            .compactMap(TileId.init(rawValue:))
            .filter { seen.insert($0).inserted }
    }

    private static func readWidths(from defaults: UserDefaults) -> [TileId: TileWidth] {
        guard let raw = defaults.string(forKey: tileSizeKey),
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        var out: [TileId: TileWidth] = [:]
        for (key, value) in object {
            guard let id = TileId(rawValue: key),
                  let entry = value as? [String: Any],
                  let w = entry["w"] as? String,
                  let width = TileWidth(rawValue: w)
            else { continue }
            out[id] = width
        }
        return out
    }
}
