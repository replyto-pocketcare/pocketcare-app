#!/usr/bin/env bash
# Regenerate the shareable technical-overview PDF from docs/pdf-src.
# Requires: graphviz (dot), pandoc, xelatex, DejaVu fonts.
# Usage: scripts/build-docs-pdf.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/docs/pdf-src"
OUT="$ROOT/docs/exports"
mkdir -p "$SRC/img" "$OUT"

echo "Rendering diagrams (graphviz)…"
for d in arch data sync; do
  dot -Tpng -Gdpi=140 "$SRC/$d.dot" -o "$SRC/img/$d.png"
done

echo "Building PDF (pandoc + xelatex)…"
( cd "$SRC" && pandoc technical-overview.md \
    -o "$OUT/PocketCare-Technical-Overview.pdf" \
    --pdf-engine=xelatex )

echo "Done → docs/exports/PocketCare-Technical-Overview.pdf"
