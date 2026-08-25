package com.sanvya.app.ui.dashboard

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

/**
 * Which tiles are on the dashboard, in what order, and how wide each one is.
 *
 * A faithful port of `apps/web/src/dashboard.ts`, down to the two storage keys
 * (`dashboardTiles`, `dashboardTileSizes`) and the JSON shapes, so a saved
 * dashboard means the same thing wherever it is read. Same pattern as
 * `NavPrefs` — a Koin-injected SharedPreferences behind a StateFlow.
 *
 * **This is per-device and does not sync**, and that is web's behaviour too:
 * `dashboard.ts` writes to localStorage, not to a table. Putting the native
 * copy in the database "because we can" would make two devices disagree about
 * a preference the browser has always kept to itself.
 *
 * Web stores a **third** key, `dashboardTileSpans`, plus `TileSpan`,
 * `setTileSpan`, `useTileSpans`, `H_ROWS` and `isTileEnabled`. Every one of
 * them is exported and unimported — a first sizing attempt that the {w,h}
 * system replaced and nobody deleted. None of it is ported.
 */
object DashboardPrefs : KoinComponent {

    private const val PREFS_NAME = "sanvya_prefs"

    private val context: Context by inject()
    private val sharedPrefs: SharedPreferences by lazy {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private val _ids: MutableStateFlow<List<TileId>> by lazy { MutableStateFlow(readIds()) }

    /** Enabled tiles, in the user's chosen order. */
    val ids: StateFlow<List<TileId>> get() = _ids

    private val _widths: MutableStateFlow<Map<TileId, TileWidth>> by lazy { MutableStateFlow(readWidths()) }

    /** Per-tile width overrides. A tile with no entry uses [defaultWidth]. */
    val widths: StateFlow<Map<TileId, TileWidth>> get() = _widths

    /**
     * The width a tile starts at.
     *
     * Web's grid is four columns wide and its default size is `md` (two of
     * them) — half the row. A phone renders one column whatever this says, so
     * the value only becomes visible on a tablet, which is exactly where a
     * wrong default would look worst.
     */
    val defaultWidth: TileWidth = TileWidth.MD

    fun widthOf(id: TileId): TileWidth = _widths.value[id] ?: defaultWidth

    /** Add or remove a tile. Adding appends, which keeps a custom order intact. */
    fun setEnabled(id: TileId, on: Boolean) {
        val current = _ids.value
        val next = when {
            on && id !in current -> current + id
            !on -> current.filterNot { it == id }
            else -> return
        }
        writeIds(next)
    }

    /** Persist an explicit order — drag, or the move-up/move-down buttons. */
    fun reorder(ordered: List<TileId>) = writeIds(ordered.distinct())

    /** Move one tile by one position. Returns false at either end. */
    fun move(id: TileId, delta: Int): Boolean {
        val current = _ids.value.toMutableList()
        val from = current.indexOf(id)
        val to = from + delta
        if (from < 0 || to < 0 || to >= current.size) return false
        current.removeAt(from)
        current.add(to, id)
        writeIds(current)
        return true
    }

    fun setWidth(id: TileId, width: TileWidth) {
        val next = _widths.value + (id to width)
        val json = JSONObject()
        // Web stores {w,h}. Only `w` is ever read back -- `H_ROWS` exists but
        // nothing uses it, and row height is measured from content instead. The
        // `h` is written so a dashboard saved on a phone still parses in the
        // browser, rather than tripping web's `isDim(s.h)` guard and being
        // dropped whole.
        next.forEach { (tile, w) ->
            json.put(tile.key, JSONObject().put("w", w.name.lowercase()).put("h", "md"))
        }
        sharedPrefs.edit().putString(TILE_SIZE_KEY, json.toString()).apply()
        _widths.value = next
    }

    private fun writeIds(ids: List<TileId>) {
        sharedPrefs.edit().putString(TILE_ORDER_KEY, JSONArray(ids.map { it.key }).toString()).apply()
        _ids.value = ids
    }

    private fun readIds(): List<TileId> {
        val raw = sharedPrefs.getString(TILE_ORDER_KEY, null) ?: return DEFAULT_TILE_IDS
        return try {
            val array = JSONArray(raw)
            // Preserve the chosen ORDER; drop unknown ids and duplicates. An
            // empty saved list is a real state -- the user removed every tile --
            // and must NOT fall back to the defaults, or a tile they deleted
            // comes back on the next launch.
            (0 until array.length())
                .mapNotNull { TileId.from(array.optString(it, null)) }
                .distinct()
        } catch (_: Exception) {
            DEFAULT_TILE_IDS
        }
    }

    private fun readWidths(): Map<TileId, TileWidth> {
        val raw = sharedPrefs.getString(TILE_SIZE_KEY, null) ?: return emptyMap()
        return try {
            val json = JSONObject(raw)
            buildMap {
                json.keys().forEach { key ->
                    val id = TileId.from(key) ?: return@forEach
                    val w = json.optJSONObject(key)?.optString("w") ?: return@forEach
                    TileWidth.entries.firstOrNull { it.name.equals(w, ignoreCase = true) }
                        ?.let { put(id, it) }
                }
            }
        } catch (_: Exception) {
            emptyMap()
        }
    }
}
