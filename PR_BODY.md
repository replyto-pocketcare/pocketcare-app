## What this is

The native Android and iOS apps brought up to parity with web's mobile layout, plus the generator
pipeline that keeps them from drifting again. 24 commits.

**Web is untouched by design.** Everything here reads from web as the parity source; nothing
changes how it behaves. The two exceptions are called out below and both are additive.

CI on `mobile/parity` is green at `1eb4029` — `parity ✅ · android ✅ · ios ✅`.

---

## What landed

**The app shell, on both platforms.** Both apps had a navigation drawer. Web has never had one —
it has a floating bottom bar with four user-customizable slots, a raised centre "+", and a grouped
More sheet. The drawers are deleted (`NavDrawer.kt`, `MainTabView.swift`, `DrawerMenuView.swift`)
and replaced with a real port: banners, utility row, contextual add action, bottom-nav customizer.

**Tablets, foldables and large windows.** Three width classes on each platform, at the *platform's*
breakpoints (Material 3's 600/840 plus a 480 height gate, and the equivalent on iOS) rather than
web's CSS pixels — so the apps switch where every other app on the device switches. Expanded gets
web's sidebar + inset window frame. Orientation policy: phones portrait, tablets and foldables
free, with device type read from `FEATURE_SENSOR_HINGE_ANGLE` and `sw600dp` rather than inferred
from size.

**A generator pipeline.** Design tokens, strings, icons, the currency→locale table and the form
option lists are all generated from single sources, and the `parity` CI job fails if any generated
file drifts from its source. 50/50 token assertions are verified against `globals.css` — no design
value is a literal in native code.

**Money correctness.** `baseCurrency` was a write-only setting: choosing USD in Settings changed
nothing, anywhere, because eleven Android screens each built their own
`NumberFormat(Locale("en","IN"))` with `Currency.getInstance("INR")`. Two of those eleven were both
named `formatMoney` with different fraction digits, so the same amount rendered differently on two
screens. There is now one formatter per platform, and `"INR"` appears in native source in exactly
two places: the generated default, and the lakh/crore grouping table.

**i18n, roughly half done.** ~780 of ~1,430 hardcoded English strings now resolve through the
generated accessors, which had been referenced zero times. Android also gained the `I18n.kt` its
own generated `S.kt` had referred to since it was written but which never existed — likely the
reason nothing used the accessors.

---

## Reviewing this

The commit history is the intended read — each commit explains the bug it fixes and why the fix is
shaped the way it is. Two documents carry the rest:

- `docs/mobile/PARITY_AUDIT.md` — the boot file. Route→platform map, traps, the de-hardcoding
  programme with honest status (§6a), and what remains.
- `docs/mobile/screen-specs/app-shell.md` — every shell value traced to its line in `globals.css`.

---

## Changes outside the native apps

| Path | What | Risk |
|---|---|---|
| `packages/core/i18n/.../translation/{en,hi,nl}.json` | **+6 keys per locale**, verified additive: 0 removed, 0 values changed. `nav.recurring/reflect/help` did not exist in any locale (web renders them from inline `t()` fallbacks); `common.saveChanges/saving/adding` were each defined separately in five namespaces | None — web renders identically |
| `packages/core/catalog` | New package. **Generator input only** — nothing in `apps/web` imports it | None |
| `apps/web/src/ui/MaterialIcon.tsx`, `public/fonts/pocketcare-icons.woff2` | One added glyph (`lock`) and the font rebuilt to include it. `generate-icons.mjs` parses this file as its source of truth | Additive — no existing glyph moved or changed codepoint. **Flagged for a decision:** if web must be untouched absolutely, the icon generator needs a non-web source |
| `tools/parity/**` | The generators and the i18n matcher | Build-time only |
| `.github/workflows/` | `mobile.yml` added; the Android job removed from `ci.yml` (it now lives in `mobile.yml`) | — |

---

## Known and deliberate

- **Neither app has ever been run.** Green CI means it compiles, generated artifacts are in sync,
  and unit tests pass. Nothing here has been on a device or simulator.
- **~650 strings still hardcoded English**, plus ~165 where native copy has drifted from web and
  adopting the key is a judgement call. `tools/parity/i18n-match.mjs` reports both.
- **Every screen still draws its own title bar**, which web has at no width below 1024.
  `SanvyaPage` exists to replace them; no screen uses it yet.
- **13 web routes have no native screen** on either platform.
- **Three money bugs on web** are fixed *only* in the native ports, which now deliberately diverge
  from their stated source. Documented in `PARITY_AUDIT.md` §6b with enough detail to fix
  separately, on web's own schedule. All three are invisible to an INR user and wrong for JPY, KWD
  and BHD.
