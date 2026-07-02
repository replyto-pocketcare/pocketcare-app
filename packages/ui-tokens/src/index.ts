/**
 * @pocketcare/ui-tokens — earthy, minimal design tokens shared by mobile + web.
 * Platform layers map these to StyleSheet (RN) or CSS variables (web).
 */

/** Earthy palette: warm clays, sage/olive greens, sand, muted terracotta. */
export const palette = {
  clay50: "#FAF6F1",
  clay100: "#F1E8DE",
  clay200: "#E4D3C1",
  clay300: "#D2B79C",
  sand: "#C9B79C",
  olive400: "#8A8F6B",
  olive600: "#5F6647",
  sage: "#9CAE8E",
  forest: "#3E4A38",
  terracotta: "#B06A4F",
  terracottaSoft: "#C98A72",
  ink: "#2B2723",
  inkSoft: "#6B6459",
  cream: "#FFFDF9",
  // Semantic
  positive: "#5F7A52",
  negative: "#A8503A",
  warning: "#C08A3E",
} as const;

export const lightTheme = {
  background: palette.clay50,
  surface: palette.cream,
  surfaceAltBorder: palette.clay200,
  textPrimary: palette.ink,
  textSecondary: palette.inkSoft,
  accent: palette.terracotta,
  accentMuted: palette.terracottaSoft,
  positive: palette.positive,
  negative: palette.negative,
  warning: palette.warning,
} as const;

export const darkTheme = {
  background: "#211E1A",
  surface: "#2B2723",
  surfaceAltBorder: "#3A342D",
  textPrimary: palette.clay50,
  textSecondary: palette.sand,
  accent: palette.terracottaSoft,
  accentMuted: palette.terracotta,
  positive: palette.sage,
  negative: "#C98A72",
  warning: palette.warning,
} as const;

/** 4pt spacing scale. */
export const spacing = { xs: 4, sm: 8, md: 12, lg: 16, xl: 24, xxl: 32, xxxl: 48 } as const;

export const radius = { sm: 6, md: 12, lg: 20, pill: 999 } as const;

export const typography = {
  fontFamily: {
    // Warm humanist sans; swap for a licensed face at integration time.
    sans: "Inter",
    serif: "Fraunces",
  },
  size: { xs: 12, sm: 14, md: 16, lg: 20, xl: 28, xxl: 36 },
  weight: { regular: "400", medium: "500", semibold: "600", bold: "700" },
} as const;

/** Motion tokens for elegant, restrained animation. */
export const motion = {
  duration: { fast: 150, base: 250, slow: 400 },
  easing: {
    standard: "cubic-bezier(0.2, 0, 0, 1)",
    emphasized: "cubic-bezier(0.3, 0, 0, 1)",
  },
} as const;

export type Theme = typeof lightTheme;
