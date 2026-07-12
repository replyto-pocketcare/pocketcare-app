# PocketCare Design System

Reference for the visual language (from `design rewamp/Split debt visualization design/PocketCare.dc.html`). Source of truth for tokens is `apps/web/app/globals.css` `:root`.

## Fonts
- **Inter** (sans) — the single app typeface: headings, body, labels, buttons, nav, figures. Loaded via Google Fonts in `apps/web/app/layout.tsx`. Token: `--font`.
- Eyebrow label: `.eyebrow` (11px, 600, uppercase, tracked).
- (The design mockup used Fraunces for display type; we intentionally keep Inter throughout.)

## Palette (tokens)
| Token | Value | Use |
|---|---|---|
| `--bg` | `#efe9df` | App background |
| `--surface` | `#fffdf9` | Cards / panels |
| `--surface-2` | `#f3ebdd` | Inset / secondary fills |
| sidebar | `#f6f0e7` | Left nav background |
| `--border` | `#e7dccd` | Default hairline |
| `--border-strong` | `#e4d8c7` | Emphasized dividers |
| `--text` | `#2b2723` | Primary text |
| `--text-2` | `#8a7d6c` | Muted text |
| `--text-3` | `#a79a88` | Eyebrow / faint |
| `--accent` | `#b06a4f` | Terracotta primary |
| `--accent-hover` | `#8f533c` | Hover / pressed |
| `--accent-soft` | `#c98a72` | Focus ring / soft accent |
| `--accent-ghost` | `#f0d8c9` | Accent tint fills |
| `--positive` | `#5f7a52` | Money in / owed to you |
| `--negative` | `#a8503a` | Money out / you owe |
| `--warning` | `#c08a3e` | Amber |
| `--teal` | `#2f6f6a` | Secondary accent |
| `--forest` | `#3e4a38` | Deep green |

## Shape & elevation
- Radius: cards `--radius-lg` (24px), default `--radius` (22px), inputs `--radius-sm` (12px), pills `999px`.
- Card shadow `--shadow`: `0 1px 2px rgba(43,39,35,.04), 0 12px 30px -20px rgba(43,39,35,.16)`.
- Hover lift `--shadow-lg`: `0 22px 48px -22px rgba(43,39,35,.32)`.
- Accent button shadow `--shadow-accent`: `0 10px 24px -12px rgba(176,106,79,.9)`.

## Components (`globals.css`)
- `.card` — surface + `--border` + 24px radius + `--shadow`.
- `.btn` — terracotta pill, white text, accent shadow, hover→`--accent-hover`, active scale 0.97. `.btn.ghost` = surface + strong border, no shadow.
- `.chip` — pill; `[data-active="true"]` fills accent.
- `.input` — 12px radius, accent-soft focus ring.
- Micro-interactions: `.press` (active scale), `.lift` (hover raise), `.page-anim` (pageIn entrance).

## Applying to a page
Use `.card` for panels, `h1/h2/h3` for headings (already serif), `.eyebrow` for section labels, `.stat`/`.serif` for large figures, `--positive`/`--negative` for money direction. Prefer tokens over hardcoded hex.
