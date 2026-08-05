#!/usr/bin/env node
/**
 * tools/parity/generate-tokens.mjs
 *
 * Design-token generator — the mechanism described in
 * docs/plans/mobile-pixel-parity-plan.md Phase B.
 *
 * Source of truth: apps/web/app/globals.css `:root` (light) and
 * `:root[data-theme="dark"]` (dark overrides) blocks — this is the ACTUAL
 * production CSS, not the stale packages/ui-tokens package (verified
 * 2026-08-05 to have drifted from production; not used as input here).
 *
 * Emits:
 *   apps/android/app/src/main/java/com/sanvya/app/theme/Color.kt
 *   apps/android/app/src/main/java/com/sanvya/app/theme/Theme.kt
 *   apps/ios/App/Theme.swift
 *
 * Only tokens that exist in globals.css are emitted — colors and the
 * `--radius*` scale. `--font` (Inter) and `--shadow*` are NOT emitted:
 * font bundling and native shadow/elevation are separate tasks, not
 * something this generator should fabricate. Re-run this script whenever
 * globals.css changes; the emitted files are generated output — hand edits
 * to them will be overwritten, edit globals.css instead.
 *
 * Usage: node tools/parity/generate-tokens.mjs
 */

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "../..");

const CSS_PATH = path.join(REPO_ROOT, "apps/web/app/globals.css");
const ANDROID_THEME_DIR = path.join(
  REPO_ROOT,
  "apps/android/app/src/main/java/com/sanvya/app/theme"
);
const IOS_THEME_PATH = path.join(REPO_ROOT, "apps/ios/App/Theme.swift");

// ---- 1. Parse globals.css --------------------------------------------------

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
  while ((m = re.exec(block))) {
    vars[m[1]] = m[2].trim();
  }
  return vars;
}

const css = readFileSync(CSS_PATH, "utf8");
const lightBlock = extractBlock(css, /:root\s*\{/);
const darkBlock = extractBlock(css, /:root\[data-theme="dark"\]\s*\{/);

const lightVars = parseVars(lightBlock);
// Dark theme = light theme, overridden by whatever the dark block redefines
// (CSS custom-property cascade — verified against the source: e.g. dark
// doesn't redefine --text-3, so dark --text-3 IS light's --text-3).
const darkVars = { ...lightVars, ...parseVars(darkBlock) };

function isHexColor(v) {
  return /^#[0-9a-fA-F]{3,8}$/.test(v);
}
function isPx(v) {
  return /^-?\d+(\.\d+)?px$/.test(v);
}

const colorKeys = Object.keys(lightVars).filter((k) => isHexColor(lightVars[k]));
const radiusKeys = Object.keys(lightVars).filter((k) => isPx(lightVars[k]));
const skipped = Object.keys(lightVars).filter(
  (k) => !colorKeys.includes(k) && !radiusKeys.includes(k)
);

console.log(`Parsed ${colorKeys.length} colors, ${radiusKeys.length} radii from globals.css`);
console.log(`Skipped (not a plain hex/px value — not portable as-is): ${skipped.join(", ")}`);

// ---- 2. Name mapping (CSS kebab-case -> camelCase identifier) -------------

function toCamel(k) {
  return k.replace(/-([a-z0-9])/g, (_, c) => c.toUpperCase());
}

const colorNames = colorKeys.map((k) => [k, toCamel(k)]);
const radiusNames = radiusKeys.map((k) => [k, toCamel(k)]);

// ---- 3. Android: Color.kt --------------------------------------------------

function hexToKotlinColor(hex) {
  let h = hex.replace("#", "");
  if (h.length === 3) h = h.split("").map((c) => c + c).join("");
  if (h.length === 6) h = "FF" + h; // opaque alpha
  return `Color(0x${h.toUpperCase()})`;
}

const androidColorKt = `package com.sanvya.app.theme

import androidx.compose.ui.graphics.Color

// GENERATED FILE — do not hand-edit.
// Source: apps/web/app/globals.css :root / :root[data-theme="dark"]
// Regenerate with: node tools/parity/generate-tokens.mjs

object SanvyaLightColors {
${colorNames.map(([k, name]) => `    val ${name} = ${hexToKotlinColor(lightVars[k])}`).join("\n")}
}

object SanvyaDarkColors {
${colorNames.map(([k, name]) => `    val ${name} = ${hexToKotlinColor(darkVars[k])}`).join("\n")}
}
`;

// ---- 4. Android: Theme.kt --------------------------------------------------

const androidThemeKt = `package com.sanvya.app.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf

// GENERATED FILE — do not hand-edit.
// Source: apps/web/app/globals.css :root / :root[data-theme="dark"]
// Regenerate with: node tools/parity/generate-tokens.mjs

/**
 * Semantic token holder — mirrors the CSS custom properties exactly (same
 * names, same values) so a screen reading \`LocalSanvyaColors.current.accent\`
 * is reading the same source-derived value web reads from \`var(--accent)\`.
 */
data class SanvyaColors(
${colorNames.map(([, name]) => `    val ${name}: androidx.compose.ui.graphics.Color`).join(",\n")}
)

private val lightTokens = SanvyaColors(
${colorNames.map(([, name]) => `    ${name} = SanvyaLightColors.${name}`).join(",\n")}
)

private val darkTokens = SanvyaColors(
${colorNames.map(([, name]) => `    ${name} = SanvyaDarkColors.${name}`).join(",\n")}
)

val LocalSanvyaColors = staticCompositionLocalOf { lightTokens }

@Composable
fun SanvyaTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val tokens = if (darkTheme) darkTokens else lightTokens

    // MaterialTheme wiring so standard Material 3 components (ripples, default
    // surfaces) land close to the design system too — screens should still
    // prefer LocalSanvyaColors.current for anything that needs to match web
    // exactly (this is the same relationship web's globals.css vars have to
    // its .card/.btn/.chip classes vs raw browser defaults).
    val colorScheme = if (darkTheme) {
        darkColorScheme(
            background = tokens.bg,
            surface = tokens.surface,
            primary = tokens.accent,
            onBackground = tokens.text,
            onSurface = tokens.text,
            error = tokens.negative,
        )
    } else {
        lightColorScheme(
            background = tokens.bg,
            surface = tokens.surface,
            primary = tokens.accent,
            onBackground = tokens.text,
            onSurface = tokens.text,
            error = tokens.negative,
        )
    }

    CompositionLocalProvider(LocalSanvyaColors provides tokens) {
        MaterialTheme(colorScheme = colorScheme, content = content)
    }
}
`;

// ---- 5. Android: Radius.kt --------------------------------------------------

const androidRadiusKt = `package com.sanvya.app.theme

import androidx.compose.ui.unit.dp

// GENERATED FILE — do not hand-edit.
// Source: apps/web/app/globals.css :root (--radius*)
// Regenerate with: node tools/parity/generate-tokens.mjs

object SanvyaRadius {
${radiusNames
  .map(([k, name]) => `    val ${name} = ${parseFloat(lightVars[k])}.dp`)
  .join("\n")}
}
`;

// ---- 6. iOS: Theme.swift ---------------------------------------------------

function hexToSwiftUIColor(hex) {
  let h = hex.replace("#", "");
  if (h.length === 3) h = h.split("").map((c) => c + c).join("");
  const r = parseInt(h.slice(0, 2), 16) / 255;
  const g = parseInt(h.slice(2, 4), 16) / 255;
  const b = parseInt(h.slice(4, 6), 16) / 255;
  return `UIColor(red: ${r.toFixed(4)}, green: ${g.toFixed(4)}, blue: ${b.toFixed(4)}, alpha: 1)`;
}

const iosThemeSwift = `import SwiftUI

// GENERATED FILE — do not hand-edit.
// Source: apps/web/app/globals.css :root / :root[data-theme="dark"]
// Regenerate with: node tools/parity/generate-tokens.mjs

extension Color {
${colorNames
  .map(
    ([k, name]) =>
      `    public static let ${name} = Color(UIColor { tc in tc.userInterfaceStyle == .dark ? ${hexToSwiftUIColor(
        darkVars[k]
      )} : ${hexToSwiftUIColor(lightVars[k])} })`
  )
  .join("\n")}
}

enum SanvyaRadius {
${radiusNames.map(([k, name]) => `    static let ${name}: CGFloat = ${parseFloat(lightVars[k])}`).join("\n")}
}
`;

// ---- 7. Write files ---------------------------------------------------------

mkdirSync(ANDROID_THEME_DIR, { recursive: true });
writeFileSync(path.join(ANDROID_THEME_DIR, "Color.kt"), androidColorKt);
writeFileSync(path.join(ANDROID_THEME_DIR, "Theme.kt"), androidThemeKt);
writeFileSync(path.join(ANDROID_THEME_DIR, "Radius.kt"), androidRadiusKt);
writeFileSync(IOS_THEME_PATH, iosThemeSwift);

console.log("Wrote:");
console.log(" -", path.relative(REPO_ROOT, path.join(ANDROID_THEME_DIR, "Color.kt")));
console.log(" -", path.relative(REPO_ROOT, path.join(ANDROID_THEME_DIR, "Theme.kt")));
console.log(" -", path.relative(REPO_ROOT, path.join(ANDROID_THEME_DIR, "Radius.kt")));
console.log(" -", path.relative(REPO_ROOT, IOS_THEME_PATH));
