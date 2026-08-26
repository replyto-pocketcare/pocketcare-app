#!/usr/bin/env node
/**
 * tools/parity/generate-help.mjs
 *
 * The Help FAQ, generated from the single place it is written:
 * `SECTIONS` in apps/web/app/help/page.tsx.
 *
 * The FAQ is ~35 question/answer pairs across 11 sections, and it is the sort
 * of content that goes stale the moment it exists in three places. Generating
 * it means a change to web's copy reaches both native apps the next time this
 * runs, and the parity job fails if it has not.
 *
 * **The copy is English on all three platforms**, because it is English on web:
 * every question and answer is a string literal in that component, not a key in
 * `packages/core/i18n`. Translating it means moving it into the i18n package
 * and having web read it from there, which is a change to the live client and
 * therefore Akhilesh's call. Until then, generating from web is what keeps the
 * three copies identical rather than merely similar. Recorded in PARITY_AUDIT.
 *
 * Each section's icon is validated against the generated `SanvyaIcons`, so a
 * new icon on web fails here rather than painting nothing on a phone.
 *
 * Emits:
 *   apps/android/domain/src/main/kotlin/com/sanvya/app/domain/help/HelpContent.kt
 *   apps/ios/Domain/Sources/Domain/HelpContent.swift
 *
 * Usage: node tools/parity/generate-help.mjs
 */

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = process.env.SANVYA_REPO_ROOT
  ? path.resolve(process.env.SANVYA_REPO_ROOT)
  : path.resolve(__dirname, "../..");

const SRC = path.join(REPO_ROOT, "apps/web/app/help/page.tsx");
const ICONS_SRC = path.join(REPO_ROOT, "apps/web/src/ui/MaterialIcon.tsx");
const ANDROID_OUT = path.join(
  REPO_ROOT,
  "apps/android/domain/src/main/kotlin/com/sanvya/app/domain/help/HelpContent.kt",
);
const IOS_OUT = path.join(REPO_ROOT, "apps/ios/Domain/Sources/Domain/HelpContent.swift");

const src = readFileSync(SRC, "utf8");
const start = src.indexOf("const SECTIONS: Section[] = [");
if (start === -1) {
  console.error("generate-help: could not find `const SECTIONS: Section[] = [` in help/page.tsx — the source shape changed. Fix this script rather than committing stale content.");
  process.exit(1);
}
// The `[` after the `=`, NOT `indexOf("[", start)` — that finds the one in the
// `Section[]` type annotation and the matcher then closes on it immediately.
const open = src.indexOf("[", src.indexOf("=", start));
// Brace/bracket matching rather than a regex: the answers contain brackets and
// quotes of their own, and a lazy `[\s\S]*?\];` would stop at the first one.
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
  console.error("generate-help: the SECTIONS array is unterminated. Fix this script rather than committing stale content.");
  process.exit(1);
}

// eslint-disable-next-line no-new-func
const sections = new Function(`return ${src.slice(open, end)};`)();

if (!Array.isArray(sections) || sections.length === 0) {
  console.error("generate-help: parsed 0 sections. Fix this script rather than committing an empty FAQ.");
  process.exit(1);
}

// Icons must exist in the generated map, or the phone paints nothing.
const iconSrc = readFileSync(ICONS_SRC, "utf8");
const known = new Set(
  [...iconSrc.matchAll(/^\s*([a-z0-9_]+):\s*"\\u[0-9a-fA-F]{4}",/gm)].map((m) => m[1]),
);
const missing = sections.map((s) => s.icon).filter((i) => !known.has(i));
if (missing.length) {
  console.error(`generate-help: help/page.tsx uses icons the shared map does not have: ${missing.join(", ")}. Add them to MaterialIcon.tsx and rebuild the font.`);
  process.exit(1);
}

const items = sections.reduce((n, s) => n + s.items.length, 0);
console.log(`help: ${sections.length} sections, ${items} question/answer pairs`);

/** Kotlin and Swift agree on these escapes; `$` only matters in Kotlin. */
const esc = (s, kotlin) => {
  const out = String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"');
  return kotlin ? out.replace(/\$/g, "\\$") : out;
};

const BANNER = [
  "// GENERATED FILE — do not hand-edit.",
  "// Source: apps/web/app/help/page.tsx (SECTIONS)",
  "// Regenerate with: node tools/parity/generate-help.mjs",
].join("\n");

const DOC = [
  " * The Help FAQ, exactly as web writes it.",
  " *",
  " * English on all three platforms because it is English on web: every string",
  " * here is a literal in that component rather than a key in the i18n package.",
  " * Generating it is what keeps the three copies identical rather than merely",
  " * similar — see tools/parity/generate-help.mjs.",
];

const kt = `package com.sanvya.app.domain.help

${BANNER}

/** One question and its answer. */
data class HelpItem(val question: String, val answer: String)

/** One FAQ section: an icon, its accent colour, a title, and its questions. */
data class HelpSection(
    /** Web's own icon name -- look it up in \`SanvyaIcons.byWebName\`. */
    val icon: String,
    /** \`#RRGGBB\`, straight from web. */
    val color: String,
    val title: String,
    val items: List<HelpItem>,
)

/**
${DOC.join("\n")}
 */
val HELP_SECTIONS: List<HelpSection> = listOf(
${sections
  .map(
    (s) => `    HelpSection(
        icon = "${esc(s.icon, true)}",
        color = "${esc(s.color, true)}",
        title = "${esc(s.title, true)}",
        items = listOf(
${s.items
  .map((it) => `            HelpItem("${esc(it.q, true)}", "${esc(it.a, true)}"),`)
  .join("\n")}
        ),
    ),`,
  )
  .join("\n")}
)
`;

const swift = `${BANNER}

/// One question and its answer.
public struct HelpItem: Equatable, Sendable, Identifiable {
    public let question: String
    public let answer: String
    public var id: String { question }

    public init(_ question: String, _ answer: String) {
        self.question = question
        self.answer = answer
    }
}

/// One FAQ section: an icon, its accent colour, a title, and its questions.
public struct HelpSection: Equatable, Sendable, Identifiable {
    /// Web's own icon name — look it up in \`SanvyaIcons.byWebName\`.
    public let icon: String
    /// \`#RRGGBB\`, straight from web.
    public let color: String
    public let title: String
    public let items: [HelpItem]
    public var id: String { title }

    public init(icon: String, color: String, title: String, items: [HelpItem]) {
        self.icon = icon
        self.color = color
        self.title = title
        self.items = items
    }
}

/**
${DOC.join("\n")}
 */
public let helpSectionsAll: [HelpSection] = [
${sections
  .map(
    (s) => `    HelpSection(
        icon: "${esc(s.icon, false)}",
        color: "${esc(s.color, false)}",
        title: "${esc(s.title, false)}",
        items: [
${s.items
  .map((it) => `            HelpItem("${esc(it.q, false)}", "${esc(it.a, false)}"),`)
  .join("\n")}
        ]
    ),`,
  )
  .join("\n")}
]
`;

mkdirSync(path.dirname(ANDROID_OUT), { recursive: true });
mkdirSync(path.dirname(IOS_OUT), { recursive: true });
writeFileSync(ANDROID_OUT, kt);
writeFileSync(IOS_OUT, swift);
console.log("Wrote:");
console.log(` - ${path.relative(REPO_ROOT, ANDROID_OUT)}`);
console.log(` - ${path.relative(REPO_ROOT, IOS_OUT)}`);
