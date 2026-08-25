#!/usr/bin/env node
/**
 * tools/parity/generate-tiles.mjs
 *
 * The dashboard tile catalog, emitted for both native platforms from web's two
 * sources of record:
 *
 *   apps/web/src/dashboard.ts        -- the id list, the fresh-install default,
 *                                       and the width steps (W_COLS)
 *   apps/web/src/dashboard/tiles.tsx -- TILE_CATALOG (premium flags) and
 *                                       TILE_HREF (where a tap goes)
 *
 * Why generated. The dashboard is the one screen where the *set* of things on
 * it is itself user data: a tile id is written into local storage and read back
 * on every launch. A platform that had thirteen of the fourteen ids would not
 * fail loudly -- it would silently drop whichever tile the user had added, on
 * that device only, and look fine to everyone testing it.
 *
 * What is deliberately NOT carried across:
 *
 * - `TileMeta.span` ("full" | "half"). Dead on web: nothing reads it. The live
 *   width comes from `useTileSizes()` -> `W_COLS`.
 * - `dashboardTileSpans` / `TileSpan` / `setTileSpan` / `useTileSpans`, and
 *   `H_ROWS` and `isTileEnabled` besides. All exported from dashboard.ts and
 *   all unimported -- a first attempt at sizing that the {w,h} system replaced
 *   and nobody deleted. Porting it would have doubled the storage format.
 * - Tile *titles*. Web hardcodes all fourteen in English. They now live in the
 *   `dashboard` i18n namespace instead; this file emits the accessor name, so a
 *   renamed key fails the build rather than falling back to English.
 *
 * Emits:
 *   apps/android/app/src/main/java/com/sanvya/app/ui/dashboard/TileCatalog.kt
 *   apps/ios/App/TileCatalog.swift
 *
 * Usage: node tools/parity/generate-tiles.mjs
 */

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = process.env.SANVYA_REPO_ROOT
  ? path.resolve(process.env.SANVYA_REPO_ROOT)
  : path.resolve(__dirname, "../..");

const PREFS_SRC = path.join(REPO_ROOT, "apps/web/src/dashboard.ts");
const TILES_SRC = path.join(REPO_ROOT, "apps/web/src/dashboard/tiles.tsx");
const ANDROID_OUT = path.join(
  REPO_ROOT,
  "apps/android/app/src/main/java/com/sanvya/app/ui/dashboard/TileCatalog.kt",
);
const IOS_OUT = path.join(REPO_ROOT, "apps/ios/App/TileCatalog.swift");

const prefsSrc = readFileSync(PREFS_SRC, "utf8");
const tilesSrc = readFileSync(TILES_SRC, "utf8");

function must(re, src, what) {
  const m = src.match(re);
  if (!m) throw new Error(`generate-tiles: could not find ${what}`);
  return m;
}

/** `export const DASHBOARD_TILE_IDS = [ "recent", … ] as const;` */
const ids = [
  ...must(/export const DASHBOARD_TILE_IDS = \[([\s\S]*?)\] as const;/, prefsSrc, "DASHBOARD_TILE_IDS")[1]
    .matchAll(/"([^"]+)"/g),
].map((m) => m[1]);

/** `const DEFAULT_ENABLED: TileId[] = ["recent", "spending", "upcoming"];` */
const defaults = [
  ...must(/const DEFAULT_ENABLED: TileId\[\] = \[([\s\S]*?)\];/, prefsSrc, "DEFAULT_ENABLED")[1]
    .matchAll(/"([^"]+)"/g),
].map((m) => m[1]);

/** `export const W_COLS: Record<TileDim, number> = { sm: 1, md: 2, lg: 4 };` */
const wCols = Object.fromEntries(
  [...must(/export const W_COLS: Record<TileDim, number> = \{([\s\S]*?)\};/, prefsSrc, "W_COLS")[1]
    .matchAll(/(\w+):\s*(\d+)/g)].map((m) => [m[1], Number(m[2])]),
);

/** Storage keys, read rather than retyped -- a saved dashboard is user data. */
const tileKey = must(/const KEY = "([^"]+)";/, prefsSrc, "the tile-list storage key")[1];
const sizeKey = must(/const SIZE_KEY = "([^"]+)";/, prefsSrc, "the tile-size storage key")[1];

/** TILE_CATALOG rows: `{ id: "cashflow", title: "Cashflow", span: "full", premium: true },` */
const catalogBody = must(/export const TILE_CATALOG: TileMeta\[\] = \[([\s\S]*?)\n\];/, tilesSrc, "TILE_CATALOG")[1];
const premium = new Set(
  [...catalogBody.matchAll(/\{\s*id:\s*"([^"]+)"[^}]*?premium:\s*true[^}]*\}/g)].map((m) => m[1]),
);

/** TILE_HREF: `recent: "/transactions",` */
const hrefBody = must(/export const TILE_HREF: Record<TileId, string> = \{([\s\S]*?)\n\};/, tilesSrc, "TILE_HREF")[1];
const hrefs = Object.fromEntries(
  [...hrefBody.matchAll(/(\w+):\s*"([^"]+)"/g)].map((m) => [m[1], m[2]]),
);

// Sanity: the two files must agree on the id set, or one of them has drifted.
const catalogIds = [...catalogBody.matchAll(/id:\s*"([^"]+)"/g)].map((m) => m[1]);
const missing = ids.filter((id) => !catalogIds.includes(id));
const extra = catalogIds.filter((id) => !ids.includes(id));
if (missing.length || extra.length) {
  throw new Error(
    `generate-tiles: DASHBOARD_TILE_IDS and TILE_CATALOG disagree.` +
      (missing.length ? ` Missing from the catalog: ${missing.join(", ")}.` : "") +
      (extra.length ? ` Not in the id list: ${extra.join(", ")}.` : ""),
  );
}
for (const id of ids) if (!hrefs[id]) throw new Error(`generate-tiles: TILE_HREF has no entry for "${id}"`);

/**
 * Web's href -> the native address for the same screen.
 *
 * `/friends` is the one that is not a straight strip: the screen is called
 * Splits in both native trees and `friends` only in the nav catalog id.
 */
const NATIVE_DEST = { friends: "splits" };
const destOf = (href) => {
  const slug = href.replace(/^\//, "").split("#")[0] || "dashboard";
  return NATIVE_DEST[slug] ?? slug;
};

/**
 * iOS's destination is a `NavTab` case, not a string.
 *
 * Read the enum and check every destination against it, so a tile pointing at a
 * screen the shell cannot show fails HERE -- at generate time, in a job that
 * takes seconds -- rather than compiling to a `NavTab(rawValue:)` that quietly
 * returns nil and makes the tile untappable on one platform only.
 */
const NAV_SRC = path.join(REPO_ROOT, "apps/ios/App/NavModels.swift");
const navTabs = new Set(
  [...must(/enum NavTab: String[\s\S]*?\n\}/, readFileSync(NAV_SRC, "utf8"), "the NavTab enum")[0]
    .matchAll(/^\s*case (\w+)/gm)].map((m) => m[1]),
);
for (const id of ids) {
  const dest = destOf(hrefs[id]);
  if (!navTabs.has(dest)) {
    throw new Error(
      `generate-tiles: tile "${id}" points at "${dest}", which is not a NavTab case. ` +
        `Add the case, or map the href in NATIVE_DEST.`,
    );
  }
}

const pascal = (s) => s[0].toUpperCase() + s.slice(1);
const upperSnake = (s) => s.replace(/([a-z0-9])([A-Z])/g, "$1_$2").toUpperCase();
const labelAccessor = (id) => `tile${pascal(id)}`;

const banner = (tool) => `// GENERATED by tools/parity/${tool} -- do not edit by hand.
// Sources: apps/web/src/dashboard.ts and apps/web/src/dashboard/tiles.tsx.
// Run \`node tools/parity/${tool}\` after changing either.`;

/* ----------------------------- Android ----------------------------- */

const kt = `package com.sanvya.app.ui.dashboard

${banner("generate-tiles.mjs")}

import android.content.res.Resources
import com.sanvya.app.i18n.S

/**
 * How wide a tile sits in the dashboard grid.
 *
 * Three steps, not a free drag. Web offers exactly these and stores the chosen
 * step rather than a pixel width, which is what lets the same saved dashboard
 * open on a phone and a tablet without arriving half off-screen.
 */
enum class TileWidth(val columns: Int) {
${Object.entries(wCols).map(([k, v]) => `    ${k.toUpperCase()}(${v}),`).join("\n")};

    /** Cycles on tap, exactly as web's width button does. */
    fun next(): TileWidth = entries[(ordinal + 1) % entries.size]
}

/** Every dashboard tile, in catalog order. */
enum class TileId(
    val key: String,
    val isPremium: Boolean,
    /** Nav route a tap on the tile opens, mirroring web's TILE_HREF. */
    val destination: String,
    private val label: (Resources) -> String,
) {
${ids
  .map(
    (id) =>
      `    ${upperSnake(id)}("${id}", ${premium.has(id)}, "${destOf(hrefs[id])}", S.Dashboard::${labelAccessor(id)}),`,
  )
  .join("\n")}
    ;

    fun title(res: Resources): String = label(res)

    companion object {
        fun from(key: String?): TileId? = entries.firstOrNull { it.key == key }
    }
}

/** What a fresh install shows before the user touches anything. */
val DEFAULT_TILE_IDS: List<TileId> = listOf(${defaults.map((d) => `TileId.${upperSnake(d)}`).join(", ")})

/** Storage keys, shared verbatim with web so a preference means one thing. */
const val TILE_ORDER_KEY = "${tileKey}"
const val TILE_SIZE_KEY = "${sizeKey}"
`;

/* ------------------------------- iOS ------------------------------- */

const swift = `import Foundation

${banner("generate-tiles.mjs")}

/// How wide a tile sits in the dashboard grid.
///
/// Three steps, not a free drag. Web offers exactly these and stores the chosen
/// step rather than a pixel width, which is what lets the same saved dashboard
/// open on a phone and an iPad without arriving half off-screen.
enum TileWidth: String, CaseIterable, Sendable {
${Object.keys(wCols).map((k) => `    case ${k}`).join("\n")}

    var columns: Int {
        switch self {
${Object.entries(wCols).map(([k, v]) => `        case .${k}: return ${v}`).join("\n")}
        }
    }

    /// Cycles on tap, exactly as web's width button does.
    var next: TileWidth {
        let all = TileWidth.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// Every dashboard tile, in catalog order.
enum TileId: String, CaseIterable, Identifiable, Sendable {
${ids.map((id) => `    case ${id}`).join("\n")}

    var id: String { rawValue }

    var isPremium: Bool {
        switch self {
${ids.filter((id) => premium.has(id)).length
      ? `        case ${ids.filter((id) => premium.has(id)).map((id) => `.${id}`).join(", ")}: return true\n        default: return false`
      : "        default: return false"}
        }
    }

    /// Where a tap on the tile goes, mirroring web's TILE_HREF.
    var destination: NavTab {
        switch self {
${ids.map((id) => `        case .${id}: return .${destOf(hrefs[id])}`).join("\n")}
        }
    }

    var title: String {
        switch self {
${ids.map((id) => `        case .${id}: return S.Dashboard.${labelAccessor(id)}`).join("\n")}
        }
    }
}

/// What a fresh install shows before the user touches anything.
let defaultTileIds: [TileId] = [${defaults.map((d) => `.${d}`).join(", ")}]

/// Storage keys, shared verbatim with web so a preference means one thing.
let tileOrderKey = "${tileKey}"
let tileSizeKey = "${sizeKey}"
`;

mkdirSync(path.dirname(ANDROID_OUT), { recursive: true });
writeFileSync(ANDROID_OUT, kt);
writeFileSync(IOS_OUT, swift);

console.log(
  `tiles: ${ids.length} tiles (${[...premium].length} premium), ` +
    `${defaults.length} on by default, widths ${Object.entries(wCols).map(([k, v]) => `${k}=${v}`).join("/")}`,
);
console.log("Wrote:");
console.log(` - ${path.relative(REPO_ROOT, ANDROID_OUT)}`);
console.log(` - ${path.relative(REPO_ROOT, IOS_OUT)}`);
