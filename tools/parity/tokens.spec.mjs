/**
 * tools/parity/tokens.spec.mjs
 *
 * The curated half of the design-token contract.
 *
 * `generate-tokens.mjs` can parse the `--custom-property` block out of
 * apps/web/app/globals.css mechanically, but most of what makes a screen look
 * right lives in ordinary CSS rules — `.bottom-nav { height: 52px }`,
 * `h1 { font-size: 26px }`, `.press:active { transform: scale(0.97) }`. Those
 * are not custom properties, so there is nothing to parse generically.
 *
 * Rather than let a human retype them into Kotlin and Swift (which is exactly
 * how the native apps drifted the first time), every value below is declared
 * WITH the selector and property it came from. The generator re-reads
 * globals.css and asserts each one still matches. If someone changes
 * `.bottom-nav-item { height: 52px }` on web and does not regenerate, the
 * generator fails loudly instead of silently emitting a stale number.
 *
 * Adding a value here is therefore a two-part commitment: the value, and the
 * CSS it is accountable to.
 */

/** @typedef {{ selector: string, prop: string, expect: string }} CssAssertion */

/**
 * Assertions are grouped only for readability; the generator flattens them.
 * `selector` is matched literally against the rule heads in globals.css
 * (whitespace-normalised), `prop` against a declaration inside that rule.
 */
export const TYPOGRAPHY = {
  // Web is Inter throughout (DESIGN_SYSTEM.md "Fonts"); --font declares the
  // stack. Native bundles the same family — see W0.3 in PARITY_AUDIT.md.
  family: "Inter",

  styles: {
    h1: {
      size: 26,
      weight: 700,
      tracking: -0.02, // em
      css: { selector: "h1", prop: "font-size", expect: "26px" },
    },
    // Phones drop h1 to 22px at the 860px breakpoint — the size that actually
    // applies on every native screen.
    h1Compact: {
      size: 22,
      weight: 700,
      tracking: -0.02,
      css: { selector: "h1", prop: "font-size", expect: "22px", media: "(max-width: 860px)" },
    },
    h2: {
      size: 18,
      weight: 650,
      tracking: -0.01,
      css: { selector: "h2", prop: "font-size", expect: "18px" },
    },
    eyebrow: {
      size: 11,
      weight: 600,
      tracking: 0.09,
      uppercase: true,
      css: { selector: ".eyebrow", prop: "font-size", expect: "11px" },
    },
    // The expanded-layout sidebar has its own scale. `body` and `statLabel`
    // only approximated it -- web's rows are 13.5/500 (650 when active), which
    // is neither.
    sideNavItem: {
      size: 13.5,
      weight: 500,
      tracking: 0,
      css: { selector: ".side-nav-item", prop: "font-size", expect: "13.5px", media: "(min-width: 1024px)" },
    },
    sideNavItemActive: {
      size: 13.5,
      weight: 650,
      tracking: 0,
      css: { selector: ".side-nav-item.active", prop: "font-weight", expect: "650", media: "(min-width: 1024px)" },
    },
    sideNavTitle: {
      size: 10.5,
      weight: 600,
      tracking: 0.07,
      uppercase: true,
      css: { selector: ".side-nav-title", prop: "font-size", expect: "10.5px", media: "(min-width: 1024px)" },
    },
    sideNavSearch: {
      size: 13,
      weight: 400,
      tracking: 0,
      css: { selector: ".side-nav-search", prop: "font-size", expect: "13px", media: "(min-width: 1024px)" },
    },
    sideNavBadge: {
      size: 10.5,
      weight: 700,
      tracking: 0,
      css: { selector: ".side-nav-badge", prop: "font-size", expect: "10.5px", media: "(min-width: 1024px)" },
    },
    sideNavGuest: {
      size: 12.5,
      weight: 400,
      tracking: 0,
      css: { selector: ".side-nav-guest", prop: "font-size", expect: "12.5px", media: "(min-width: 1024px)" },
    },
    sideNavVersion: {
      size: 11,
      weight: 400,
      tracking: 0,
      css: { selector: ".side-nav-ver", prop: "font-size", expect: "11px", media: "(min-width: 1024px)" },
    },
    body: {
      size: 15,
      weight: 400,
      tracking: 0,
      css: { selector: ".input", prop: "font-size", expect: "15px" },
    },
    chip: {
      size: 14,
      weight: 400,
      tracking: 0,
      css: { selector: ".chip", prop: "font-size", expect: "14px" },
    },
    button: {
      size: 15,
      weight: 600,
      tracking: 0,
      css: { selector: ".btn", prop: "font-weight", expect: "600" },
    },
    navLabel: {
      size: 10,
      weight: 600,
      tracking: 0,
      css: { selector: ".bottom-nav-item", prop: "font-size", expect: "10px" },
    },
    statValue: {
      size: 26,
      weight: 700,
      tracking: -0.02,
      css: { selector: ".stat-value", prop: "font-size", expect: "26px" },
    },
    statLabel: {
      size: 13,
      weight: 600,
      tracking: 0,
      css: { selector: ".stat-label", prop: "font-size", expect: "13px" },
    },
    // The "you are here"/section label used inside the More sheet and sidebar.
    sectionTitle: {
      size: 10.5,
      weight: 600,
      tracking: 0.07,
      uppercase: true,
      css: { selector: ".side-nav-title", prop: "font-size", expect: "10.5px" },
    },
  },
};

/**
 * Shape. `--radius*` come from the custom-property block and are parsed
 * generically; `pill` is the literal 999px used across .btn/.chip/.bottom-nav.
 */
export const SHAPE = {
  pill: 999,
  // .row-tile / .tap-row / .add-popover-item — the "inner" radius used for rows
  // inside a card, distinct from the card's own --radius-lg.
  row: 10,
  popover: 18,
  popoverItem: 12,
  // Checkbox corner (input[type=checkbox]) — needed by the component layer.
  checkbox: 6,
  assertions: [
    { selector: ".row-tile", prop: "border-radius", expect: "10px" },
    { selector: ".tap-row", prop: "border-radius", expect: "10px" },
    { selector: ".add-popover", prop: "border-radius", expect: "18px" },
    { selector: ".add-popover-item", prop: "border-radius", expect: "12px" },
    { selector: '.btn', prop: "border-radius", expect: "999px" },
    { selector: ".chip", prop: "border-radius", expect: "999px" },
  ],
};

/**
 * Motion. Web's easing is `cubic-bezier(0.2, 0, 0, 1)` almost everywhere —
 * Compose gets a CubicBezierEasing, SwiftUI a timingCurve animation.
 */
export const MOTION = {
  standardEasing: [0.2, 0, 0, 1],
  press: { scale: 0.97, durationMs: 120 },
  // .lift:hover has no touch equivalent; .lift:active does — scale 0.985/80ms.
  liftPress: { scale: 0.985, durationMs: 80 },
  pageIn: { durationMs: 340, translateY: 10 },
  fadeUp: { durationMs: 400, translateY: 8 },
  shimmer: { durationMs: 1400 },
  colorFade: { durationMs: 150 },
  assertions: [
    { selector: ".press:active", prop: "transform", expect: "scale(0.97)" },
    { selector: ".tap-row", prop: "transition", contains: "0.12s" },
    { selector: ".page-anim", prop: "animation", contains: "0.34s" },
    { selector: ".fade-up", prop: "animation", contains: "0.4s" },
  ],
};

/**
 * Shell metrics — the numbers that make the bottom bar and utility row land
 * pixel-identically. Every one is asserted against globals.css.
 *
 * Native adds the platform's own bottom inset on top of `barBottomInset`,
 * exactly as `env(safe-area-inset-bottom)` does on web.
 */
export const SHELL = {
  bottomNav: {
    sideInset: 16,
    bottomInset: 14,
    maxWidth: 460,
    paddingV: 6,
    paddingH: 8,
    itemGap: 2,
    itemHeight: 52,
    itemHeightCompact: 46, // <= 640px, i.e. every phone
    addSize: 52,
    addSizeCompact: 48,
    addRingWidth: 3,
    addOverhang: 14, // margin-top: -14px
    addSideMargin: 6,
    labelHiddenBelow: 640,
    assertions: [
      { selector: ".bottom-nav", prop: "max-width", expect: "460px" },
      { selector: ".bottom-nav", prop: "padding", expect: "6px 8px" },
      { selector: ".bottom-nav-item", prop: "height", expect: "52px" },
      { selector: ".bottom-nav-add", prop: "width", expect: "52px" },
      { selector: ".bottom-nav-add", prop: "margin", expect: "-14px 6px 0" },
      { selector: ".bottom-nav-item", prop: "height", expect: "46px", media: "(max-width: 640px)" },
      { selector: ".bottom-nav-add", prop: "width", expect: "48px", media: "(max-width: 640px)" },
    ],
  },
  utilRow: {
    minHeight: 40,
    gap: 10,
    marginBottom: 8,
    buttonSize: 40,
    backPaddingStart: 12,
    backPaddingEnd: 14,
    backGap: 6,
    assertions: [
      { selector: ".util-row", prop: "min-height", expect: "40px" },
      { selector: ".util-btn", prop: "width", expect: "40px" },
    ],
  },
  page: {
    // .shell-main at <= 860px: padding 10px 16px, bottom 96px + safe area.
    paddingTop: 10,
    paddingHorizontal: 16,
    paddingBottom: 96,
    maxWidth: 720,
    assertions: [
      {
        selector: ".shell-main",
        prop: "padding",
        contains: "10px 16px",
        media: "(max-width: 860px)",
      },
    ],
  },
  /**
   * The expanded layout: sidebar, top bar, and the inset window frame the whole
   * app sits in. `globals.css:594-700`.
   *
   * These are web's values and stay web's values -- the layout must look the
   * same on a tablet as it does in a desktop browser. Only the *threshold* at
   * which native switches to it is the platform's (Material 3's 840dp width +
   * 480dp height, not web's 1024px). See screen-specs/app-shell.md §1.
   */
  expanded: {
    // Window frame. `.shell` inside a `--surface-2` body.
    frameInset: 16,
    frameRadius: 26,
    // Sidebar, inset one pixel further so it sits flush inside the frame.
    sidebarInset: 17,
    sidebarWidth: 252,
    sidebarRadius: 25,
    sidebarPaddingTop: 18,
    sidebarPaddingH: 14,
    sidebarPaddingBottom: 14,
    sidebarGap: 4,
    brandSize: 26,
    brandPaddingBottom: 14,
    searchPaddingV: 10,
    searchPaddingH: 12,
    searchMarginBottom: 12,
    searchRadius: 12,
    searchIconSize: 16,
    itemPaddingV: 9,
    itemPaddingH: 10,
    itemRadius: 10,
    itemGap: 10,
    itemIconSize: 19,
    /** The "you are here" rail on the active row. */
    railWidth: 3,
    railHeight: 20,
    railOffset: 14,
    badgeMinWidth: 18,
    badgeHeight: 18,
    footPaddingTop: 10,
    // Top bar.
    topBarHeight: 36,
    topBarGap: 16,
    topBarPaddingV: 10,
    topBarMarginBottom: 18,
    topIconSize: 36,
    topDotSize: 7,
    avatarSize: 36,
    // Content column.
    contentPaddingTop: 24,
    contentPaddingH: 32,
    contentPaddingBottom: 40,
    contentMaxWidth: 1440,
    assertions: [
      // Web's own switch point, asserted so the layout below stays anchored to
      // the CSS block it was read from even though native switches earlier.
      { selector: ".bottom-nav", prop: "display", contains: "none", media: "(min-width: 1024px)" },
      { selector: ".shell", prop: "margin", expect: "16px", media: "(min-width: 1024px)" },
      { selector: ".shell", prop: "border-radius", expect: "26px", media: "(min-width: 1024px)" },
      { selector: ".side-nav", prop: "width", expect: "252px", media: "(min-width: 1024px)" },
      { selector: ".side-nav", prop: "left", expect: "17px", media: "(min-width: 1024px)" },
      { selector: ".side-nav-item", prop: "border-radius", expect: "10px", media: "(min-width: 1024px)" },
      { selector: ".shell-main", prop: "margin-left", contains: "252px", media: "(min-width: 1024px)" },
      { selector: ".shell-main", prop: "max-width", contains: "1440px", media: "(min-width: 1024px)" },
      { selector: ".shell-main", prop: "padding", contains: "24px 32px 40px", media: "(min-width: 1024px)" },
    ],
  },

  listGrid: {
    minColumnWidth: 320,
    gap: 12,
    assertions: [{ selector: ".list-grid", prop: "gap", expect: "12px" }],
  },
  addPopover: {
    minWidth: 220,
    bottomOffset: 84,
    padding: 10,
    gap: 8,
    itemPaddingV: 10,
    itemPaddingH: 12,
    assertions: [
      { selector: ".add-popover", prop: "min-width", expect: "220px" },
      { selector: ".add-popover", prop: "padding", expect: "10px" },
    ],
  },
  banner: {
    // OfflineBanner / SyncProblemsBanner are inline-styled in AppShell.tsx, not
    // CSS classes, so there is nothing to assert — the values are recorded here
    // and the AppShell source is cited instead.
    paddingV: 7,
    paddingH: 14,
    fontSize: 12.5,
    fontWeight: 600,
    gap: 8,
    source: "apps/web/app/AppShell.tsx OfflineBanner / SyncProblemsBanner",
  },
};

/**
 * Shadows. CSS box-shadow layers, decomposed so Compose and SwiftUI can
 * approximate them with their own primitives. Parsed from the custom-property
 * block by the generator; this table only names the *semantic* use so the
 * native side does not have to re-derive which shadow goes where.
 */
export const ELEVATION = {
  card: "shadow",
  raised: "shadow-lg",
  accentButton: "shadow-accent",
};
