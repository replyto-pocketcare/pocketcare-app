#!/usr/bin/env node
/**
 * tools/parity/generate-onboarding-slides.mjs
 *
 * The pre-auth onboarding deck's visual identity, generated from the single
 * place it is written: `SLIDES` in apps/web/app/onboarding/page.tsx.
 *
 * Only the glyph and the two gradient stops live there — the title and body of
 * every slide are already i18n keys (`onboarding:slides.N.title/body`) and
 * reach both platforms through generate-i18n.mjs. What is left is seven pairs
 * of hex colours and seven characters, and hand-copying those into two native
 * files is exactly the sort of drift the parity job exists to prevent: nobody
 * would notice slide 4 being the wrong shade of amber on Android for a year.
 *
 * The COUNT is load-bearing too. Both native decks read `slides.size` for the
 * page dots and for "is this the last one", so adding an eighth slide on web
 * and a matching pair of i18n keys is the whole change.
 *
 * Emits:
 *   apps/android/app/src/main/java/com/sanvya/app/ui/onboarding/OnboardingSlides.kt
 *   apps/ios/App/OnboardingSlides.swift
 *
 * Usage: node tools/parity/generate-onboarding-slides.mjs
 */

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = process.env.SANVYA_REPO_ROOT
  ? path.resolve(process.env.SANVYA_REPO_ROOT)
  : path.resolve(__dirname, "../..");

const SRC = path.join(REPO_ROOT, "apps/web/app/onboarding/page.tsx");
const I18N_EN = path.join(REPO_ROOT, "packages/core/i18n/src/locales/onboarding/en.json");
const ANDROID_OUT = path.join(
  REPO_ROOT,
  "apps/android/app/src/main/java/com/sanvya/app/ui/onboarding/OnboardingSlides.kt",
);
const IOS_OUT = path.join(REPO_ROOT, "apps/ios/App/OnboardingSlides.swift");

const src = readFileSync(SRC, "utf8");
const marker = "const SLIDES:";
const start = src.indexOf(marker);
if (start === -1) {
  console.error(
    "generate-onboarding-slides: could not find `const SLIDES:` in onboarding/page.tsx — the source shape changed. Fix this script rather than committing stale content.",
  );
  process.exit(1);
}
// The `[` after the `=`, not after `start` — that would find the one in the
// `{ ... }[]` type annotation and the matcher would close on it immediately.
// Same trap generate-help.mjs documents.
const open = src.indexOf("[", src.indexOf("=", start));
let depth = 0;
let end = -1;
let inString = null;
for (let i = open; i < src.length; i++) {
  const ch = src[i];
  if (inString) {
    if (ch === "\\") { i++; continue; }
    if (ch === inString) inString = null;
    continue;
  }
  if (ch === '"' || ch === "'" || ch === "`") { inString = ch; continue; }
  if (ch === "[") depth++;
  else if (ch === "]") {
    depth--;
    if (depth === 0) { end = i + 1; break; }
  }
}
if (end === -1) {
  console.error("generate-onboarding-slides: the SLIDES array is unterminated. Fix this script.");
  process.exit(1);
}

// eslint-disable-next-line no-new-func
const slides = new Function(`return ${src.slice(open, end)};`)();

if (!Array.isArray(slides) || slides.length === 0) {
  console.error("generate-onboarding-slides: parsed 0 slides. Fix this script rather than committing an empty deck.");
  process.exit(1);
}

const HEX = /^#[0-9a-fA-F]{6}$/;
slides.forEach((s, i) => {
  if (typeof s.glyph !== "string" || s.glyph.length === 0) {
    console.error(`generate-onboarding-slides: slide ${i} has no glyph.`);
    process.exit(1);
  }
  if (!Array.isArray(s.grad) || s.grad.length !== 2 || !s.grad.every((c) => HEX.test(c))) {
    console.error(
      `generate-onboarding-slides: slide ${i}'s gradient is not two #rrggbb stops (got ${JSON.stringify(s.grad)}). Native reads them as ARGB ints; a shorthand or named colour would silently paint black.`,
    );
    process.exit(1);
  }
});

// Every slide needs copy on both platforms, and the copy is i18n, not source.
// A slide added to SLIDES without its two keys renders a blank card on web and
// a crash-or-blank on native, so fail here where it is cheap to see.
const strings = JSON.parse(readFileSync(I18N_EN, "utf8"));
const missingKeys = [];
slides.forEach((_, i) => {
  const slide = strings?.slides?.[String(i)];
  if (!slide?.title) missingKeys.push(`slides.${i}.title`);
  if (!slide?.body) missingKeys.push(`slides.${i}.body`);
});
if (missingKeys.length) {
  console.error(
    `generate-onboarding-slides: onboarding/en.json is missing ${missingKeys.join(", ")}. Every slide needs a title and a body.`,
  );
  process.exit(1);
}

console.log(`onboarding-slides: ${slides.length} slides`);

/** The glyphs are single BMP characters; emit them as escapes so the generated
 *  files stay pure ASCII and no editor's encoding can quietly rewrite one.
 *  Swift wants `\u{XXXX}`, Kotlin wants `\uXXXX`. */
const esc = (ch, swift) =>
  [...ch]
    .map((c) => {
      const hex = c.codePointAt(0).toString(16).toUpperCase().padStart(4, "0");
      return swift ? `\\u{${hex}}` : `\\u${hex}`;
    })
    .join("");

const BANNER = [
  "// GENERATED FILE - do not hand-edit.",
  "// Source: apps/web/app/onboarding/page.tsx (SLIDES)",
  "// Regenerate with: node tools/parity/generate-onboarding-slides.mjs",
].join("\n");

const DOC_LINES = [
  "The pre-auth onboarding deck's visual identity, exactly as web writes it.",
  "",
  "Glyph and gradient only: each slide's title and body are i18n keys",
  "(onboarding:slides.N.title / .body) and arrive through the generated",
  "strings, so this file has no copy in it and needs no translation.",
  "",
  "The gradient stops are stored as the #rrggbb strings web writes and",
  "converted by the platform's own hex parser -- the one every account and",
  "chart colour already goes through. A second colour constructor here would",
  "be a second place for #RGB shorthand or a bad digit to behave differently.",
];

const kt = `package com.sanvya.app.ui.onboarding

${BANNER}

import android.content.res.Resources
import androidx.compose.ui.graphics.Color
import com.sanvya.app.i18n.S
import com.sanvya.app.ui.parseHexColor

/**
 * ${DOC_LINES.join("\n * ")}
 */
data class OnboardingSlide(
    val glyph: String,
    val gradientStartHex: String,
    val gradientEndHex: String,
) {
    val gradientStart: Color get() = parseHexColor(gradientStartHex)
    val gradientEnd: Color get() = parseHexColor(gradientEndHex)
}

object OnboardingSlides {
    /**
     * Every slide's title, in order, resolved through the generated strings.
     *
     * Emitted rather than hand-written because S.Onboarding's accessors are
     * flat (slides0Title, slides1Title, ...) with no way to index them: a
     * hand-written when-expression would be the one place an eighth slide gets
     * forgotten. The generator has already failed if a key is missing.
     */
    fun titles(res: Resources): List<String> = listOf(
${slides.map((_, i) => `        S.Onboarding.slides${i}Title(res),`).join("\n")}
    )

    fun bodies(res: Resources): List<String> = listOf(
${slides.map((_, i) => `        S.Onboarding.slides${i}Body(res),`).join("\n")}
    )

    val slides: List<OnboardingSlide> = listOf(
${slides
  .map(
    (s) =>
      `        OnboardingSlide("${esc(s.glyph, false)}", "${s.grad[0]}", "${s.grad[1]}"),`,
  )
  .join("\n")}
    )
}
`;

const swift = `import SwiftUI

${BANNER}

/// ${DOC_LINES.join("\n/// ")}
public struct OnboardingSlide: Identifiable, Equatable, Sendable {
    public let id: Int
    public let glyph: String
    public let gradientStartHex: String
    public let gradientEndHex: String

    /// A gray fallback on a malformed stop rather than a crash -- the same rule
    /// accountColor(explicit:id:) uses, reading a free-form database column.
    public var gradientStart: Color { Color(hex: gradientStartHex) ?? .gray }
    public var gradientEnd: Color { Color(hex: gradientEndHex) ?? .gray }
}

public enum OnboardingSlides {
    /// Every slide's title, in order, resolved through the generated strings.
    ///
    /// Emitted rather than hand-written because S.Onboarding's accessors are
    /// flat (slides0Title, slides1Title, ...) with no way to index them: a
    /// hand-written switch would be the one place an eighth slide gets
    /// forgotten. The generator has already failed if a key is missing.
    public static var titles: [String] {
        [
${slides.map((_, i) => `            S.Onboarding.slides${i}Title,`).join("\n")}
        ]
    }

    public static var bodies: [String] {
        [
${slides.map((_, i) => `            S.Onboarding.slides${i}Body,`).join("\n")}
        ]
    }

    public static let slides: [OnboardingSlide] = [
${slides
  .map(
    (s, i) =>
      `        OnboardingSlide(id: ${i}, glyph: "${esc(s.glyph, true)}", gradientStartHex: "${s.grad[0]}", gradientEndHex: "${s.grad[1]}"),`,
  )
  .join("\n")}
    ]
}
`;

mkdirSync(path.dirname(ANDROID_OUT), { recursive: true });
mkdirSync(path.dirname(IOS_OUT), { recursive: true });
writeFileSync(ANDROID_OUT, kt);
writeFileSync(IOS_OUT, swift);
console.log(` - ${path.relative(REPO_ROOT, ANDROID_OUT)}`);
console.log(` - ${path.relative(REPO_ROOT, IOS_OUT)}`);
