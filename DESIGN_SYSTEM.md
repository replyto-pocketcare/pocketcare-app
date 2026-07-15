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

## Responsive list grid (shared)
`.list-grid` (in `globals.css`) replaces full-width stacked lists with space-efficient tiles: `repeat(auto-fill, minmax(min(320px,100%),1fr))` → 1 col mobile, 2 laptop, 3+ wide. Each child must be a self-contained card/tile. Applied to Cashflow sections, Search, Transactions, Goals, Budgets, Investments, Templates, and Friends/Splits (Accounts already used this pattern at 260px). Dense `TransactionRow` gets a `tile` prop that renders `.tx-tile` (bordered card w/ hover lift) instead of the divider row. On Friends/Splits the Groups & Direct lists moved out of the summary card into tiled sections; an **expanded group tile spans the full row** (`gridColumn: 1 / -1`) so the per-person breakdown stays readable.

## Planned Cashflow (BETA) additions
Added in `globals.css` (tokens only, theme-aware): `.beta-badge` (+`.sm`) accent-ghost pill for experimental features; `.pc-segment` / `.pc-seg-btn` sliding segmented control (timeframe tabs); `.pc-hero` auto-fit summary grid; `.pc-template` dashed quick-add pill (fills accent-ghost on hover); `.pc-row-icon` rounded accent icon chip; `.pc-glass` glassmorphism panel (backdrop-blur + accent radial glow, uses `color-mix`); `.pc-range` themed slider with accent thumb + `--shadow-accent`. Reuses `.card`, `.lift`, `.eyebrow`, `.chip`, `.btn`. Charts use recharts with CSS-var fills so they track light/dark.

## Applying to a page
Use `.card` for panels, `h1/h2/h3` for headings (already serif), `.eyebrow` for section labels, `.stat`/`.serif` for large figures, `--positive`/`--negative` for money direction. Prefer tokens over hardcoded hex.
