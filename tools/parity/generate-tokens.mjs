#!/usr/bin/env node
/**
 * tools/parity/generate-tokens.mjs
 *
 * Design-token generator — the mechanism described in
 * docs/plans/mobile-pixel-parity-plan.md Phase B and
 * docs/mobile/PARITY_AUDIT.md §1.2.
 *
 * Source of truth: apps/web/app/globals.css. Two halves:
 *
 *   1. The `--custom-property` blocks (`:root`, `:root[data-theme="dark"]`) are
 *      parsed mechanically — colours, radii, shadows, the font stack.
 *   2. Everything that lives in ordinary CSS rules (`h1 { font-size: 26px }`,
 *      `.bottom-nav-item { height: 52px }`, `.press:active { scale(0.97) }`)
 *      is declared in `tokens.spec.mjs` alongside the selector it came from,
 *      and every one of those declarations is re-checked against globals.css
 *      before anything is emitted. Change the CSS without regenerating and
 *      this script fails; it cannot quietly emit a stale number.
 *
 * Emits (all GENERATED — never hand-edit, edit globals.css/tokens.spec.mjs):
 *   apps/android/app/src/main/java/com/sanvya/app/theme/{Color,Shape,Type,Elevation,Motion,Metrics,Theme}.kt
 *   apps/ios/App/Theme/{Colors,Shape,Typography,Elevation,Motion,Metrics}.swift
 *
 * Usage: node tools/parity/generate-tokens.mjs [--check]
 *   --check  verify assertions and report, write nothing.
 */

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { readDeclarations, checkAssertion, collectAssertions } from "./css-assert.mjs";
import * as SPEC from "./tokens.spec.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = process.env.SANVYA_REPO_ROOT
  ? path.resolve(process.env.SANVYA_REPO_ROOT)
  : path.resolve(__dirname, "../..");

const CSS_PATH = path.join(REPO_ROOT, "apps/web/app/globals.css");
const ANDROID_THEME_DIR = path.join(
  REPO_ROOT,
  "apps/android/app/src/main/java/com/sanvya/app/theme",
);
const IOS_THEME_DIR = path.join(REPO_ROOT, "apps/ios/App/Theme");

const CHECK_ONLY = process.argv.includes("--check");
const GENERATED_BANNER_LINES = [
  "GENERATED FILE — do not hand-edit.",
  "Source: apps/web/app/globals.css + tools/parity/tokens.spec.mjs",
  "Regenerate with: node tools/parity/generate-tokens.mjs",
];

// ---------------------------------------------------------------------------
// 1. Custom properties
// ---------------------------------------------------------------------------

function extractBlock(css, selectorRegex) {
  const m = selectorRegex.exec(css);
  if (!m) throw new Error(`Selector not found: ${selectorRegex}`);
  const start = m.index + m[0].length;
  const end = css.indexOf("}", start);
  return css.slice(start, end);
}

function parseVars(block) {
  const vars = {};
  const re = /--([a-z0-9-]+)\s*:\s*([^;]+);/gi;
  let m;
  while ((m = re.exec(block))) vars[m[1]] = m[2].trim();
  return vars;
}

const css = readFileSync(CSS_PATH, "utf8");
const lightVars = parseVars(extractBlock(css, /:root\s*\{/));
// Dark = light overridden by the dark block (the CSS custom-property cascade).
// e.g. dark never redefines --text-3, so dark's --text-3 IS light's.
const darkVars = { ...lightVars, ...parseVars(extractBlock(css, /:root\[data-theme="dark"\]\s*\{/)) };

const isHex = (v) => /^#[0-9a-fA-F]{3,8}$/.test(v);
const isPx = (v) => /^-?\d+(\.\d+)?px$/.test(v);
const isShadow = (v) => /\d+px .*rgba?\(/.test(v);

const colorKeys = Object.keys(lightVars).filter((k) => isHex(lightVars[k]));
const radiusKeys = Object.keys(lightVars).filter((k) => isPx(lightVars[k]));
const shadowKeys = Object.keys(lightVars).filter((k) => isShadow(lightVars[k]));

const toCamel = (k) => k.replace(/-([a-z0-9])/g, (_, c) => c.toUpperCase());

// ---------------------------------------------------------------------------
// 2. Hold tokens.spec.mjs accountable to the stylesheet
// ---------------------------------------------------------------------------

const decls = readDeclarations(css);
const assertions = collectAssertions(SPEC);
const failures = [];
for (const a of assertions) {
  const r = checkAssertion(decls, a);
  if (!r.ok) failures.push(`  ${a.path}: ${r.reason}`);
}
if (failures.length) {
  console.error(
    `tokens.spec.mjs has drifted from apps/web/app/globals.css — ${failures.length} of ${assertions.length} assertions failed:\n` +
      failures.join("\n") +
      "\n\nFix tokens.spec.mjs to match the CSS (or revert the CSS). Do NOT edit the generated native files.",
  );
  process.exit(1);
}
console.log(
  `globals.css: ${colorKeys.length} colours, ${radiusKeys.length} radii, ${shadowKeys.length} shadows; ` +
    `${assertions.length}/${assertions.length} spec assertions match.`,
);
if (CHECK_ONLY) process.exit(0);

// ---------------------------------------------------------------------------
// 3. Shadow decomposition
// ---------------------------------------------------------------------------

/**
 * Split a CSS box-shadow into its layers. Compose and SwiftUI both take a
 * single (colour, radius, offset) triple per shadow, so a two-layer CSS shadow
 * becomes two stacked native shadows rather than an averaged approximation.
 *
 * Negative spread has no native equivalent on either platform; it is recorded
 * so the component layer can compensate by shrinking the blur, and is not
 * silently dropped.
 */
function parseShadow(value) {
  const layers = [];
  // Split on commas that are not inside rgba(...).
  let depth = 0;
  let buf = "";
  for (const ch of value) {
    if (ch === "(") depth++;
    if (ch === ")") depth--;
    if (ch === "," && depth === 0) {
      layers.push(buf.trim());
      buf = "";
      continue;
    }
    buf += ch;
  }
  if (buf.trim()) layers.push(buf.trim());

  return layers.map((layer) => {
    const colorMatch = layer.match(/rgba?\([^)]*\)/);
    const color = colorMatch ? colorMatch[0] : "rgba(0,0,0,0.2)";
    const nums = layer
      .replace(color, "")
      .trim()
      .split(/\s+/)
      .filter(Boolean)
      .map((n) => parseFloat(n));
    const [x = 0, y = 0, blur = 0, spread = 0] = nums;
    return { x, y, blur, spread, ...parseRgba(color) };
  });
}

function parseRgba(s) {
  const m = s.match(/rgba?\(([^)]+)\)/);
  if (!m) return { r: 0, g: 0, b: 0, a: 0.2 };
  const parts = m[1].split(",").map((p) => parseFloat(p.trim()));
  return { r: parts[0] || 0, g: parts[1] || 0, b: parts[2] || 0, a: parts[3] == null ? 1 : parts[3] };
}

const shadows = {};
for (const k of shadowKeys) {
  shadows[k] = { light: parseShadow(lightVars[k]), dark: parseShadow(darkVars[k]) };
}

// ---------------------------------------------------------------------------
// 4. Emit helpers
// ---------------------------------------------------------------------------

const ktBanner = (extra = []) =>
  ["// " + GENERATED_BANNER_LINES.join("\n// "), ...extra].join("\n");
const swiftBanner = (extra = []) =>
  ["// " + GENERATED_BANNER_LINES.join("\n// "), ...extra].join("\n");

function hexToKotlinColor(hex) {
  let h = hex.replace("#", "");
  if (h.length === 3) h = h.split("").map((c) => c + c).join("");
  if (h.length === 6) h = "FF" + h;
  return `Color(0x${h.toUpperCase()})`;
}

function hexToRgbFractions(hex) {
  let h = hex.replace("#", "");
  if (h.length === 3) h = h.split("").map((c) => c + c).join("");
  return {
    r: parseInt(h.slice(0, 2), 16) / 255,
    g: parseInt(h.slice(2, 4), 16) / 255,
    b: parseInt(h.slice(4, 6), 16) / 255,
  };
}

function hexToUIColor(hex) {
  const { r, g, b } = hexToRgbFractions(hex);
  return `UIColor(red: ${r.toFixed(4)}, green: ${g.toFixed(4)}, blue: ${b.toFixed(4)}, alpha: 1)`;
}

const num = (n) => (Number.isInteger(n) ? `${n}` : `${n}`);

// ---------------------------------------------------------------------------
// 5. Android emitters
// ---------------------------------------------------------------------------

const colorNames = colorKeys.map((k) => [k, toCamel(k)]);

const androidColorKt = `package com.sanvya.app.theme

import androidx.compose.ui.graphics.Color

${ktBanner()}

object SanvyaLightColors {
${colorNames.map(([k, n]) => `    val ${n} = ${hexToKotlinColor(lightVars[k])}`).join("\n")}
}

object SanvyaDarkColors {
${colorNames.map(([k, n]) => `    val ${n} = ${hexToKotlinColor(darkVars[k])}`).join("\n")}
}
`;

const androidShapeKt = `package com.sanvya.app.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.unit.dp

${ktBanner()}

/**
 * Corner radii. \`pill\` is CSS's 999px idiom — a capsule — and is expressed as
 * a 50% shape so it stays a capsule at any height, which a literal 999.dp
 * would not on a short element.
 */
object SanvyaRadius {
${radiusKeys.map((k) => `    val ${toCamel(k)} = ${parseFloat(lightVars[k])}.dp`).join("\n")}
    val row = ${SPEC.SHAPE.row}.dp
    val popover = ${SPEC.SHAPE.popover}.dp
    val popoverItem = ${SPEC.SHAPE.popoverItem}.dp
    val checkbox = ${SPEC.SHAPE.checkbox}.dp
}

object SanvyaShape {
${radiusKeys.map((k) => `    val ${toCamel(k)} = RoundedCornerShape(SanvyaRadius.${toCamel(k)})`).join("\n")}
    val row = RoundedCornerShape(SanvyaRadius.row)
    val popover = RoundedCornerShape(SanvyaRadius.popover)
    val popoverItem = RoundedCornerShape(SanvyaRadius.popoverItem)
    val checkbox = RoundedCornerShape(SanvyaRadius.checkbox)
    val pill = RoundedCornerShape(percent = 50)
}
`;

const styleEntries = Object.entries(SPEC.TYPOGRAPHY.styles);

const androidTypeKt = `package com.sanvya.app.theme

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextGeometricTransform
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

${ktBanner()}

/**
 * Type scale. Sizes are \`sp\` so system font scaling works (an accessibility
 * requirement web gets for free from browser zoom); tracking is expressed in
 * \`em\` exactly as CSS \`letter-spacing\` is, so it scales with the size.
 *
 * \`SanvyaFont.family\` is wired in Theme.kt — Inter, bundled in res/font.
 */
object SanvyaType {
${styleEntries
  .map(
    ([name, s]) => `    val ${name} = TextStyle(
        fontFamily = SanvyaFont.family,
        fontSize = ${s.size}.sp,
        fontWeight = FontWeight(${s.weight}),
        letterSpacing = ${s.tracking}.em,
    )`,
  )
  .join("\n\n")}
}

/** Which styles render uppercase on web (\`text-transform: uppercase\`). */
object SanvyaTypeUppercase {
${styleEntries.map(([name, s]) => `    const val ${name} = ${s.uppercase === true}`).join("\n")}
}
`;

function ktShadowLayer(l) {
  return `SanvyaShadowLayer(x = ${num(l.x)}.dp, y = ${num(l.y)}.dp, blur = ${num(l.blur)}.dp, spread = ${num(
    l.spread,
  )}.dp, color = Color(red = ${(l.r / 255).toFixed(4)}f, green = ${(l.g / 255).toFixed(4)}f, blue = ${(
    l.b / 255
  ).toFixed(4)}f, alpha = ${l.a.toFixed(4)}f))`;
}

const androidElevationKt = `package com.sanvya.app.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Dp

${ktBanner()}

/**
 * One layer of a CSS box-shadow. Compose has no spread parameter, so
 * \`spread\` is carried through for the component layer to compensate with
 * (web's shadows use large negative spreads to keep a wide blur tight) rather
 * than being silently dropped here.
 */
data class SanvyaShadowLayer(
    val x: Dp,
    val y: Dp,
    val blur: Dp,
    val spread: Dp,
    val color: Color,
)

data class SanvyaShadow(val layers: List<SanvyaShadowLayer>)

object SanvyaLightShadows {
${shadowKeys
  .map(
    (k) =>
      `    val ${toCamel(k)} = SanvyaShadow(listOf(\n${shadows[k].light
        .map((l) => `        ${ktShadowLayer(l)},`)
        .join("\n")}\n    ))`,
  )
  .join("\n")}
}

object SanvyaDarkShadows {
${shadowKeys
  .map(
    (k) =>
      `    val ${toCamel(k)} = SanvyaShadow(listOf(\n${shadows[k].dark
        .map((l) => `        ${ktShadowLayer(l)},`)
        .join("\n")}\n    ))`,
  )
  .join("\n")}
}
`;

const androidMotionKt = `package com.sanvya.app.theme

import androidx.compose.animation.core.CubicBezierEasing

${ktBanner()}

/**
 * Motion. Web uses \`cubic-bezier(0.2, 0, 0, 1)\` for essentially every
 * meaningful transition; that curve is \`standard\` here.
 */
object SanvyaMotion {
    val standard = CubicBezierEasing(${SPEC.MOTION.standardEasing.map((n) => `${n}f`).join(", ")})

    const val pressScale = ${SPEC.MOTION.press.scale}f
    const val pressDurationMs = ${SPEC.MOTION.press.durationMs}

    const val liftPressScale = ${SPEC.MOTION.liftPress.scale}f
    const val liftPressDurationMs = ${SPEC.MOTION.liftPress.durationMs}

    const val pageInDurationMs = ${SPEC.MOTION.pageIn.durationMs}
    const val pageInTranslateY = ${SPEC.MOTION.pageIn.translateY}

    const val fadeUpDurationMs = ${SPEC.MOTION.fadeUp.durationMs}
    const val fadeUpTranslateY = ${SPEC.MOTION.fadeUp.translateY}

    const val shimmerDurationMs = ${SPEC.MOTION.shimmer.durationMs}
    const val colorFadeDurationMs = ${SPEC.MOTION.colorFade.durationMs}
}
`;

const S = SPEC.SHELL;
const androidMetricsKt = `package com.sanvya.app.theme

import androidx.compose.ui.unit.dp

${ktBanner()}

/**
 * Shell metrics — the numbers that make the bottom bar, utility row and page
 * padding land where web puts them. \`bottomInset\` is web's literal offset;
 * the platform safe-area inset is added on top, exactly as
 * \`env(safe-area-inset-bottom)\` does.
 *
 * Phones are always below web's 640px breakpoint, so \`*Compact\` values are
 * the ones a phone actually renders. A large tablet in landscape crosses it —
 * the shell picks per WindowSizeClass.
 */
object SanvyaMetrics {
    object BottomNav {
        val sideInset = ${S.bottomNav.sideInset}.dp
        val bottomInset = ${S.bottomNav.bottomInset}.dp
        val maxWidth = ${S.bottomNav.maxWidth}.dp
        val paddingV = ${S.bottomNav.paddingV}.dp
        val paddingH = ${S.bottomNav.paddingH}.dp
        val itemGap = ${S.bottomNav.itemGap}.dp
        val itemHeight = ${S.bottomNav.itemHeight}.dp
        val itemHeightCompact = ${S.bottomNav.itemHeightCompact}.dp
        val addSize = ${S.bottomNav.addSize}.dp
        val addSizeCompact = ${S.bottomNav.addSizeCompact}.dp
        val addRingWidth = ${S.bottomNav.addRingWidth}.dp
        val addOverhang = ${S.bottomNav.addOverhang}.dp
        val addSideMargin = ${S.bottomNav.addSideMargin}.dp
        val labelHiddenBelow = ${S.bottomNav.labelHiddenBelow}.dp
    }

    object UtilRow {
        val minHeight = ${S.utilRow.minHeight}.dp
        val gap = ${S.utilRow.gap}.dp
        val marginBottom = ${S.utilRow.marginBottom}.dp
        val buttonSize = ${S.utilRow.buttonSize}.dp
        val backPaddingStart = ${S.utilRow.backPaddingStart}.dp
        val backPaddingEnd = ${S.utilRow.backPaddingEnd}.dp
        val backGap = ${S.utilRow.backGap}.dp
    }

    object Page {
        val paddingTop = ${S.page.paddingTop}.dp
        val paddingHorizontal = ${S.page.paddingHorizontal}.dp
        val paddingBottom = ${S.page.paddingBottom}.dp
        val maxWidth = ${S.page.maxWidth}.dp
    }

    object ListGrid {
        val minColumnWidth = ${S.listGrid.minColumnWidth}.dp
        val gap = ${S.listGrid.gap}.dp
    }

    object AddPopover {
        val minWidth = ${S.addPopover.minWidth}.dp
        val bottomOffset = ${S.addPopover.bottomOffset}.dp
        val padding = ${S.addPopover.padding}.dp
        val gap = ${S.addPopover.gap}.dp
        val itemPaddingV = ${S.addPopover.itemPaddingV}.dp
        val itemPaddingH = ${S.addPopover.itemPaddingH}.dp
    }

    object Banner {
        val paddingV = ${S.banner.paddingV}.dp
        val paddingH = ${S.banner.paddingH}.dp
        val gap = ${S.banner.gap}.dp
    }
}
`;

const androidThemeKt = `package com.sanvya.app.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

${ktBanner()}

/**
 * Semantic token holder — the same names and values as the CSS custom
 * properties, so \`LocalSanvyaColors.current.accent\` and web's \`var(--accent)\`
 * are the same number from the same source.
 */
data class SanvyaColors(
${colorNames.map(([, n]) => `    val ${n}: Color`).join(",\n")}
)

private val lightTokens = SanvyaColors(
${colorNames.map(([, n]) => `    ${n} = SanvyaLightColors.${n}`).join(",\n")}
)

private val darkTokens = SanvyaColors(
${colorNames.map(([, n]) => `    ${n} = SanvyaDarkColors.${n}`).join(",\n")}
)

data class SanvyaShadows(
${shadowKeys.map((k) => `    val ${toCamel(k)}: SanvyaShadow`).join(",\n")}
)

private val lightShadows = SanvyaShadows(
${shadowKeys.map((k) => `    ${toCamel(k)} = SanvyaLightShadows.${toCamel(k)}`).join(",\n")}
)

private val darkShadows = SanvyaShadows(
${shadowKeys.map((k) => `    ${toCamel(k)} = SanvyaDarkShadows.${toCamel(k)}`).join(",\n")}
)

val LocalSanvyaColors = staticCompositionLocalOf { lightTokens }
val LocalSanvyaShadows = staticCompositionLocalOf { lightShadows }

@Composable
fun SanvyaTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val tokens = if (darkTheme) darkTokens else lightTokens
    val shadows = if (darkTheme) darkShadows else lightShadows

    // Material 3 wiring so stock components (ripples, dialogs, text fields the
    // app has not replaced yet) land close to the design system. Screens still
    // prefer LocalSanvyaColors.current for anything that must match web
    // exactly — the same relationship globals.css's vars have to .card/.btn.
    val colorScheme = if (darkTheme) {
        darkColorScheme(
            background = tokens.bg,
            surface = tokens.surface,
            surfaceVariant = tokens.surface2,
            primary = tokens.accent,
            onPrimary = Color.White,
            onBackground = tokens.text,
            onSurface = tokens.text,
            onSurfaceVariant = tokens.text2,
            outline = tokens.border,
            error = tokens.negative,
        )
    } else {
        lightColorScheme(
            background = tokens.bg,
            surface = tokens.surface,
            surfaceVariant = tokens.surface2,
            primary = tokens.accent,
            onPrimary = Color.White,
            onBackground = tokens.text,
            onSurface = tokens.text,
            onSurfaceVariant = tokens.text2,
            outline = tokens.border,
            error = tokens.negative,
        )
    }

    CompositionLocalProvider(
        LocalSanvyaColors provides tokens,
        LocalSanvyaShadows provides shadows,
    ) {
        MaterialTheme(
            colorScheme = colorScheme,
            typography = sanvyaMaterialTypography(),
            content = content,
        )
    }
}
`;

// ---------------------------------------------------------------------------
// 6. iOS emitters
// ---------------------------------------------------------------------------

const iosColorsSwift = `import SwiftUI

${swiftBanner()}

public extension Color {
${colorNames
  .map(
    ([k, n]) =>
      `    static let ${n} = Color(UIColor { tc in\n        tc.userInterfaceStyle == .dark\n            ? ${hexToUIColor(
        darkVars[k],
      )}\n            : ${hexToUIColor(lightVars[k])}\n    })`,
  )
  .join("\n")}
}
`;

const iosShapeSwift = `import SwiftUI

${swiftBanner()}

public enum SanvyaRadius {
${radiusKeys.map((k) => `    public static let ${toCamel(k)}: CGFloat = ${parseFloat(lightVars[k])}`).join("\n")}
    public static let row: CGFloat = ${SPEC.SHAPE.row}
    public static let popover: CGFloat = ${SPEC.SHAPE.popover}
    public static let popoverItem: CGFloat = ${SPEC.SHAPE.popoverItem}
    public static let checkbox: CGFloat = ${SPEC.SHAPE.checkbox}
}

public extension View {
    /// CSS \`border-radius: 999px\` — a capsule, not a very large radius.
    func sanvyaPill() -> some View { clipShape(Capsule()) }
}
`;

const iosTypographySwift = `import SwiftUI

${swiftBanner()}

/**
 Type scale. Sizes go through \`relativeTo:\` so Dynamic Type scales them (the
 accessibility behaviour web gets from browser zoom); tracking is converted
 from CSS \`em\` to points at the style's own size, which is what \`em\` means.

 Weight is carried as the raw CSS number, not a \`Font.Weight\`: the design uses
 550 and 650, which have no SwiftUI constant. \`SanvyaFont\` resolves them on
 Inter's variable \`wght\` axis instead of rounding to the nearest constant.
 */
public enum SanvyaType {
${styleEntries
  .map(
    ([name, s]) => `    public static let ${name} = SanvyaTextStyle(
        size: ${s.size},
        cssWeight: ${s.weight},
        trackingEm: ${s.tracking},
        uppercase: ${s.uppercase === true},
        relativeTo: ${swiftTextStyleFor(s.size)}
    )`,
  )
  .join("\n\n")}
}

public struct SanvyaTextStyle: Sendable {
    public let size: CGFloat
    public let cssWeight: Int
    public let trackingEm: CGFloat
    public let uppercase: Bool
    public let relativeTo: Font.TextStyle

    public var font: Font {
        SanvyaFont.font(size: size, cssWeight: cssWeight, relativeTo: relativeTo)
    }

    /// CSS letter-spacing is in \`em\` — a fraction of the font size.
    public var tracking: CGFloat { trackingEm * size }
}

public extension Text {
    func sanvyaStyle(_ s: SanvyaTextStyle) -> Text {
        font(s.font).tracking(s.tracking)
    }
}

public extension View {
    func sanvyaStyle(_ s: SanvyaTextStyle) -> some View {
        font(s.font).tracking(s.tracking)
    }
}
`;

/** Pick the Dynamic Type style a size should scale relative to. */
function swiftTextStyleFor(size) {
  if (size >= 26) return ".largeTitle";
  if (size >= 20) return ".title";
  if (size >= 17) return ".title3";
  if (size >= 15) return ".body";
  if (size >= 13) return ".subheadline";
  if (size >= 12) return ".footnote";
  return ".caption2";
}

function swiftShadowLayer(l) {
  return `SanvyaShadowLayer(x: ${num(l.x)}, y: ${num(l.y)}, blur: ${num(l.blur)}, spread: ${num(
    l.spread,
  )}, color: Color(.sRGB, red: ${(l.r / 255).toFixed(4)}, green: ${(l.g / 255).toFixed(4)}, blue: ${(
    l.b / 255
  ).toFixed(4)}, opacity: ${l.a.toFixed(4)}))`;
}

const iosElevationSwift = `import SwiftUI

${swiftBanner()}

/**
 One layer of a CSS box-shadow. SwiftUI's \`.shadow\` takes radius, not blur:
 CSS blur is roughly 2x SwiftUI's radius, so \`swiftUIRadius\` does that
 conversion in one place rather than at every call site. \`spread\` has no
 SwiftUI equivalent and is carried through for the component layer.
 */
public struct SanvyaShadowLayer: Sendable {
    public let x: CGFloat
    public let y: CGFloat
    public let blur: CGFloat
    public let spread: CGFloat
    public let color: Color

    public var swiftUIRadius: CGFloat { blur / 2 }
}

public struct SanvyaShadow: Sendable {
    public let layers: [SanvyaShadowLayer]
}

public enum SanvyaShadows {
${shadowKeys
  .map(
    (k) => `    public static func ${toCamel(k)}(dark: Bool) -> SanvyaShadow {
        dark
            ? SanvyaShadow(layers: [
${shadows[k].dark.map((l) => `                ${swiftShadowLayer(l)},`).join("\n")}
            ])
            : SanvyaShadow(layers: [
${shadows[k].light.map((l) => `                ${swiftShadowLayer(l)},`).join("\n")}
            ])
    }`,
  )
  .join("\n\n")}
}

public extension View {
    /// Applies every layer of a CSS shadow, outermost last — the same paint
    /// order the browser uses.
    func sanvyaShadow(_ shadow: SanvyaShadow) -> some View {
        shadow.layers.reduce(AnyView(self)) { view, layer in
            AnyView(view.shadow(color: layer.color, radius: layer.swiftUIRadius, x: layer.x, y: layer.y))
        }
    }
}
`;

const iosMotionSwift = `import SwiftUI

${swiftBanner()}

public enum SanvyaMotion {
    /// Web's \`cubic-bezier(0.2, 0, 0, 1)\`, used for essentially every
    /// meaningful transition in globals.css.
    public static func standard(_ duration: Double) -> Animation {
        .timingCurve(${SPEC.MOTION.standardEasing.join(", ")}, duration: duration)
    }

    public static let pressScale: CGFloat = ${SPEC.MOTION.press.scale}
    public static let pressDuration: Double = ${SPEC.MOTION.press.durationMs / 1000}

    public static let liftPressScale: CGFloat = ${SPEC.MOTION.liftPress.scale}
    public static let liftPressDuration: Double = ${SPEC.MOTION.liftPress.durationMs / 1000}

    public static let pageInDuration: Double = ${SPEC.MOTION.pageIn.durationMs / 1000}
    public static let pageInTranslateY: CGFloat = ${SPEC.MOTION.pageIn.translateY}

    public static let fadeUpDuration: Double = ${SPEC.MOTION.fadeUp.durationMs / 1000}
    public static let fadeUpTranslateY: CGFloat = ${SPEC.MOTION.fadeUp.translateY}

    public static let shimmerDuration: Double = ${SPEC.MOTION.shimmer.durationMs / 1000}
    public static let colorFadeDuration: Double = ${SPEC.MOTION.colorFade.durationMs / 1000}
}
`;

const iosMetricsSwift = `import SwiftUI

${swiftBanner()}

/**
 Shell metrics. \`bottomInset\` is web's literal offset; the safe-area inset is
 added on top, exactly as \`env(safe-area-inset-bottom)\` does on web.

 iPhones are always below web's 640px breakpoint, so the \`Compact\` values are
 what a phone renders; iPad and landscape-regular cross it.
 */
public enum SanvyaMetrics {
    public enum BottomNav {
        public static let sideInset: CGFloat = ${S.bottomNav.sideInset}
        public static let bottomInset: CGFloat = ${S.bottomNav.bottomInset}
        public static let maxWidth: CGFloat = ${S.bottomNav.maxWidth}
        public static let paddingV: CGFloat = ${S.bottomNav.paddingV}
        public static let paddingH: CGFloat = ${S.bottomNav.paddingH}
        public static let itemGap: CGFloat = ${S.bottomNav.itemGap}
        public static let itemHeight: CGFloat = ${S.bottomNav.itemHeight}
        public static let itemHeightCompact: CGFloat = ${S.bottomNav.itemHeightCompact}
        public static let addSize: CGFloat = ${S.bottomNav.addSize}
        public static let addSizeCompact: CGFloat = ${S.bottomNav.addSizeCompact}
        public static let addRingWidth: CGFloat = ${S.bottomNav.addRingWidth}
        public static let addOverhang: CGFloat = ${S.bottomNav.addOverhang}
        public static let addSideMargin: CGFloat = ${S.bottomNav.addSideMargin}
        public static let labelHiddenBelow: CGFloat = ${S.bottomNav.labelHiddenBelow}
    }

    public enum UtilRow {
        public static let minHeight: CGFloat = ${S.utilRow.minHeight}
        public static let gap: CGFloat = ${S.utilRow.gap}
        public static let marginBottom: CGFloat = ${S.utilRow.marginBottom}
        public static let buttonSize: CGFloat = ${S.utilRow.buttonSize}
        public static let backPaddingStart: CGFloat = ${S.utilRow.backPaddingStart}
        public static let backPaddingEnd: CGFloat = ${S.utilRow.backPaddingEnd}
        public static let backGap: CGFloat = ${S.utilRow.backGap}
    }

    public enum Page {
        public static let paddingTop: CGFloat = ${S.page.paddingTop}
        public static let paddingHorizontal: CGFloat = ${S.page.paddingHorizontal}
        public static let paddingBottom: CGFloat = ${S.page.paddingBottom}
        public static let maxWidth: CGFloat = ${S.page.maxWidth}
    }

    public enum ListGrid {
        public static let minColumnWidth: CGFloat = ${S.listGrid.minColumnWidth}
        public static let gap: CGFloat = ${S.listGrid.gap}
    }

    public enum AddPopover {
        public static let minWidth: CGFloat = ${S.addPopover.minWidth}
        public static let bottomOffset: CGFloat = ${S.addPopover.bottomOffset}
        public static let padding: CGFloat = ${S.addPopover.padding}
        public static let gap: CGFloat = ${S.addPopover.gap}
        public static let itemPaddingV: CGFloat = ${S.addPopover.itemPaddingV}
        public static let itemPaddingH: CGFloat = ${S.addPopover.itemPaddingH}
    }

    public enum Banner {
        public static let paddingV: CGFloat = ${S.banner.paddingV}
        public static let paddingH: CGFloat = ${S.banner.paddingH}
        public static let gap: CGFloat = ${S.banner.gap}
    }
}
`;

// ---------------------------------------------------------------------------
// 7. Write
// ---------------------------------------------------------------------------

mkdirSync(ANDROID_THEME_DIR, { recursive: true });
mkdirSync(IOS_THEME_DIR, { recursive: true });

const outputs = [
  [path.join(ANDROID_THEME_DIR, "Color.kt"), androidColorKt],
  [path.join(ANDROID_THEME_DIR, "Shape.kt"), androidShapeKt],
  [path.join(ANDROID_THEME_DIR, "Type.kt"), androidTypeKt],
  [path.join(ANDROID_THEME_DIR, "Elevation.kt"), androidElevationKt],
  [path.join(ANDROID_THEME_DIR, "Motion.kt"), androidMotionKt],
  [path.join(ANDROID_THEME_DIR, "Metrics.kt"), androidMetricsKt],
  [path.join(ANDROID_THEME_DIR, "Theme.kt"), androidThemeKt],
  [path.join(IOS_THEME_DIR, "Colors.swift"), iosColorsSwift],
  [path.join(IOS_THEME_DIR, "Shape.swift"), iosShapeSwift],
  [path.join(IOS_THEME_DIR, "Typography.swift"), iosTypographySwift],
  [path.join(IOS_THEME_DIR, "Elevation.swift"), iosElevationSwift],
  [path.join(IOS_THEME_DIR, "Motion.swift"), iosMotionSwift],
  [path.join(IOS_THEME_DIR, "Metrics.swift"), iosMetricsSwift],
];

for (const [file, body] of outputs) writeFileSync(file, body);

console.log("Wrote:");
for (const [file] of outputs) console.log(" -", path.relative(REPO_ROOT, file));
