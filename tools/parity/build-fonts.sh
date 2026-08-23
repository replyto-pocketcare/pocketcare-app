#!/usr/bin/env bash
# tools/parity/build-fonts.sh
#
# Rebuilds the two font binaries the native apps bundle. Run it when an icon is
# added to MATERIAL_ICON in apps/web/src/ui/MaterialIcon.tsx, or to reproduce
# the files from scratch. Output is committed — CI does not run this.
#
#   apps/android/app/src/main/res/font/inter_variable.ttf
#   apps/android/app/src/main/res/font/sanvya_icons.ttf
#   apps/ios/App/Resources/Fonts/InterVariable.ttf
#   apps/ios/App/Resources/Fonts/SanvyaIcons.ttf
#   apps/web/public/fonts/pocketcare-icons.woff2   (regenerated identically)
#
# Requires: node (npm registry access) and python3 with fontTools + brotli.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

pip install fonttools brotli --break-system-packages -q

# ---------------------------------------------------------------------------
# 1. Inter — VARIABLE, not static weights.
#
# globals.css uses font-weight 550 (.trx-title, .pc-seg-btn) and 650 (h2,
# .side-nav-item.active). Static weight files only exist at 100-step
# increments, so those two would round to 500/600 and every affected heading
# would be subtly wrong. A variable font with a live `wght` axis hits them
# exactly. Android supports variable fonts from API 26 (our minSdk); iOS via
# Core Text font variations.
#
# @fontsource-variable/inter ships woff2 only, which neither platform reads —
# fontTools decompresses it to the TTF both do.
# ---------------------------------------------------------------------------
npm pack @fontsource-variable/inter@5.3.0 >/dev/null
tar xzf fontsource-variable-inter-*.tgz
python3 -c "
from fontTools.ttLib.woff2 import decompress
decompress('package/files/inter-latin-wght-normal.woff2', 'InterVariable.ttf')
from fontTools.ttLib import TTFont
axes = [(a.axisTag, a.minValue, a.maxValue) for a in TTFont('InterVariable.ttf')['fvar'].axes]
assert any(t == 'wght' for t, _, _ in axes), f'no wght axis: {axes}'
print('Inter axes:', axes)
"

# ---------------------------------------------------------------------------
# 2. Icon subset — the same pipeline apps/web/public/fonts/README.md documents,
#    extended to also emit a TTF for the native apps. Codepoints come from
#    MATERIAL_ICON in MaterialIcon.tsx, read here rather than duplicated.
# ---------------------------------------------------------------------------
npm pack material-symbols@0.45.9 >/dev/null
tar xzf material-symbols-*.tgz

UNICODES="$(node "$ROOT/tools/parity/generate-icons.mjs" --codepoints)"
if [ -z "$UNICODES" ]; then
  echo "no codepoints parsed from MaterialIcon.tsx" >&2
  exit 1
fi

python3 -m fontTools.varLib.instancer package/material-symbols-rounded.woff2 \
  wght=400 opsz=24 FILL=0 GRAD=0 -o static.ttf >/dev/null

for FLAVOR in ttf woff2; do
  ARGS=(--unicodes="$UNICODES" --layout-features= --no-hinting --desubroutinize)
  [ "$FLAVOR" = woff2 ] && ARGS+=(--flavor=woff2)
  python3 -m fontTools.subset static.ttf "${ARGS[@]}" --output-file="sanvya-icons.$FLAVOR"
done

python3 -c "
from fontTools.ttLib import TTFont
print('icon glyphs mapped:', len(TTFont('sanvya-icons.ttf').getBestCmap()))
"

# ---------------------------------------------------------------------------
# 3. Install
# ---------------------------------------------------------------------------
install -m 644 InterVariable.ttf   "$ROOT/apps/android/app/src/main/res/font/inter_variable.ttf"
install -m 644 sanvya-icons.ttf    "$ROOT/apps/android/app/src/main/res/font/sanvya_icons.ttf"
install -m 644 InterVariable.ttf   "$ROOT/apps/ios/App/Resources/Fonts/InterVariable.ttf"
install -m 644 sanvya-icons.ttf    "$ROOT/apps/ios/App/Resources/Fonts/SanvyaIcons.ttf"
install -m 644 sanvya-icons.woff2  "$ROOT/apps/web/public/fonts/pocketcare-icons.woff2"

echo "Fonts rebuilt and installed."
