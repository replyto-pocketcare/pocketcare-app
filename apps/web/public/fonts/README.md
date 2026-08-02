# sanvya-icons.woff2

A **subset** of [Material Symbols Rounded](https://github.com/google/material-design-icons)
(npm `material-symbols@0.45.9`), licensed **Apache 2.0** — see
<https://github.com/google/material-design-icons/blob/master/LICENSE>.

## Why a subset, and why self-hosted

The full variable font is **5.2 MB**. This file is **4 KB** — it contains only
the 25 glyphs the navigation actually uses, with the variable axes flattened to
the single style we render (`wght 400, opsz 24, FILL 0, GRAD 0`).

It is self-hosted rather than CDN-loaded because Sanvya is an offline-first
PWA: a CDN font fails offline, and the nav would render raw text instead of
icons. This file is precached by the service worker.

## Regenerating (e.g. to add an icon)

1. Add the icon name to `ICONS` in `apps/web/src/ui/MaterialIcon.tsx`.
2. Run:

```bash
pip install fonttools brotli --break-system-packages
npm pack material-symbols@0.45.9 && tar -xzf material-symbols-*.tgz

# flatten the variable axes to the one style we use
python3 -m fontTools.varLib.instancer package/material-symbols-rounded.woff2 \
  wght=400 opsz=24 FILL=0 GRAD=0 -o static.ttf

# subset to just our codepoints (see MATERIAL_ICON in MaterialIcon.tsx)
python3 -m fontTools.subset static.ttf \
  --unicodes="U+e028,U+e0b6,..." \
  --layout-features='' --no-hinting --desubroutinize \
  --flavor=woff2 --output-file=sanvya-icons.woff2
```

## Why codepoints, not ligatures

Material Symbols normally renders icons from their *name* via `liga`
substitution (`<span>settings</span>`). We deliberately don't:

- Subsetting can't prune the ligature closure — every icon name is spelled from
  the same 26 letters, so keeping `liga` keeps ~3 000 glyphs (252 KB vs 4 KB).
- If the font is slow or fails to load, a ligature-based icon paints the
  **literal word** ("space_dashboard") in the nav. With codepoints it paints
  nothing (a blank box at worst), which degrades far more gracefully.

`MATERIAL_ICON` in `src/ui/MaterialIcon.tsx` is the name → codepoint map.
