#!/usr/bin/env node
/**
 * tools/parity/generate-feedback.mjs
 *
 * apps/web/src/ui/BugReport.tsx's AREAS and SEVERITIES -> Feedback.kt / .swift.
 *
 * WHY GENERATED. These two lists are the vocabulary a triage queue is sorted
 * by. The VALUES are stored in `bug_reports.area` and `.severity` and read by
 * whoever works the queue, so a phone that spells an area differently from the
 * browser silently splits one bucket into two — and nobody notices, because
 * both spellings look right in isolation.
 *
 * The values stay web's ENGLISH strings on purpose. They are identifiers that
 * happen to be readable, not copy: translating what goes into the column would
 * make the queue unsortable the moment a Hindi user files something. What IS
 * translated is the label shown on screen, and that lives in the `feedback`
 * i18n namespace keyed by the slug emitted here.
 *
 * (Web renders the raw English in its own picker, because BugReportModal is
 * hardcoded English end to end — recorded as a web defect in PARITY_AUDIT.)
 *
 * Usage: node tools/parity/generate-feedback.mjs
 */

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = process.env.SANVYA_REPO_ROOT
  ? path.resolve(process.env.SANVYA_REPO_ROOT)
  : path.resolve(__dirname, "../..");

const SRC = path.join(REPO_ROOT, "apps/web/src/ui/BugReport.tsx");
const KT_OUT = path.join(
  REPO_ROOT,
  "apps/android/domain/src/main/kotlin/com/sanvya/app/domain/feedback/Feedback.kt",
);
const SWIFT_OUT = path.join(REPO_ROOT, "apps/ios/Domain/Sources/Domain/Feedback.swift");

const src = readFileSync(SRC, "utf8");

/** Read an array literal out of the source and evaluate it. Same approach, and
 *  same justification, as generate-assistant-tools.mjs: a slice of our own repo
 *  in a build script, where the alternative is a regex over nested literals. */
function literal(name) {
  const start = src.indexOf(name);
  if (start < 0) throw new Error(`${name} not found in BugReport.tsx`);
  // From the `=`, not from `name`: SEVERITIES carries a TYPE annotation whose
  // own `[]` comes first, and starting at the name matched that instead — an
  // empty array, silently, with no error. It cost one run to notice.
  const eq = src.indexOf("=", start);
  const open = src.indexOf("[", eq);
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === "[") depth++;
    else if (src[i] === "]" && --depth === 0) {
      // eslint-disable-next-line no-eval
      return eval(src.slice(open, i + 1));
    }
  }
  throw new Error(`Unterminated ${name}`);
}

const areas = literal("const AREAS =");
// SEVERITIES carries a CSS colour per row. The colour is web's and stays web's:
// three of the four are design tokens the native palettes already have under
// their own names, and the fourth is a raw hex. Only the ids travel.
const severities = literal("const SEVERITIES:").map((s) => s.id);

const APP_VERSION = (src.match(/const APP_VERSION = "([^"]+)"/) || [])[1];
if (!APP_VERSION) throw new Error("APP_VERSION not found in BugReport.tsx");

// Anchored on `exportLog(...)`: an unanchored `.slice(0, N)` matches the
// user-agent truncation first, which is a different cap on a different field.
const CAP = Number((src.match(/exportLog\([^)]*\)\.slice\(0,\s*(\d+)\)/) || [])[1]);
if (!CAP) throw new Error("diagnostics slice cap not found in BugReport.tsx");

const UA_CAP = Number((src.match(/userAgent\.slice\(0,\s*(\d+)\)/) || [])[1]);
if (!UA_CAP) throw new Error("user-agent slice cap not found in BugReport.tsx");

/** "Accounts & Cards" -> "accountsCards". The i18n key, and nothing else. */
const slug = (s) =>
  s
    .replace(/[^A-Za-z0-9]+(.)?/g, (_, c) => (c ? c.toUpperCase() : ""))
    .replace(/^(.)/, (c) => c.toLowerCase());

const header = (regen) => `// GENERATED FILE — do not hand-edit.
// Source: apps/web/src/ui/BugReport.tsx (AREAS, SEVERITIES, APP_VERSION)
// Regenerate with: node tools/parity/${regen}`;

const DOC = `/**
 * The feedback form's vocabulary.
 *
 * [FEEDBACK_AREAS] and [FEEDBACK_SEVERITIES] are the values WRITTEN to
 * \`bug_reports\`, and they are web's English strings on purpose: they are
 * identifiers that happen to be readable, and a translated column is an
 * unsortable one. The label shown on screen is looked up in the \`feedback\`
 * i18n namespace by [feedbackAreaKey] / [feedbackSeverityKey].
 */`;

const kt = `package com.sanvya.app.domain.feedback

${header("generate-feedback.mjs")}

${DOC}

/** Web's own picker order, which is not alphabetical and is not incidental. */
val FEEDBACK_AREAS: List<String> = listOf(
${areas.map((a) => `    ${JSON.stringify(a)},`).join("\n")}
)

/** Most severe first, as web lists them. */
val FEEDBACK_SEVERITIES: List<String> = listOf(
${severities.map((s) => `    ${JSON.stringify(s)},`).join("\n")}
)

/** The i18n key for an area's on-screen label. */
fun feedbackAreaKey(area: String): String = "area" + area
    .replace(Regex("[^A-Za-z0-9]+"), " ")
    .trim()
    .split(" ")
    .joinToString("") { it.replaceFirstChar { c -> c.uppercaseChar() } }

/** The i18n key for a severity's on-screen label. */
fun feedbackSeverityKey(severity: String): String =
    "sev" + severity.replaceFirstChar { it.uppercaseChar() }

/**
 * How much of the diagnostics log travels with a report.
 *
 * Web's \`.slice(0, ${CAP})\` — "a report is for diagnosing, not archiving a
 * whole session", in its own words.
 */
const val FEEDBACK_DIAGNOSTICS_CAP = ${CAP}

/** The version stamped on a report. Web's \`APP_VERSION\` constant. */
const val FEEDBACK_APP_VERSION = ${JSON.stringify(APP_VERSION)}

/** Web truncates the user-agent string to this before storing it. */
const val FEEDBACK_USER_AGENT_CAP = ${UA_CAP}
`;

const swift = `import Foundation

${header("generate-feedback.mjs")}

/**
 The feedback form's vocabulary.

 \`feedbackAreas\` and \`feedbackSeverities\` are the values WRITTEN to
 \`bug_reports\`, and they are web's English strings on purpose: they are
 identifiers that happen to be readable, and a translated column is an
 unsortable one. The label shown on screen is looked up in the \`feedback\` i18n
 namespace by \`feedbackAreaKey\` / \`feedbackSeverityKey\`.
 */

/// Web's own picker order, which is not alphabetical and is not incidental.
public let feedbackAreas: [String] = [
${areas.map((a) => `    ${JSON.stringify(a)},`).join("\n")}
]

/// Most severe first, as web lists them.
public let feedbackSeverities: [String] = [
${severities.map((s) => `    ${JSON.stringify(s)},`).join("\n")}
]

/// The i18n key for an area's on-screen label.
///
/// The separator test is ASCII-only, deliberately: Kotlin's side is the regex
/// \`[^A-Za-z0-9]+\`, and Swift's \`isLetter\` is Unicode-aware — \`é\` is a letter
/// to one and a separator to the other. Every area is ASCII today, so this
/// changes nothing now and stops the two ports disagreeing the day one is not.
public func feedbackAreaKey(_ area: String) -> String {
    let words = area.split(whereSeparator: { !$0.isASCII || !($0.isLetter || $0.isNumber) })
    return "area" + words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
}

/// The i18n key for a severity's on-screen label.
public func feedbackSeverityKey(_ severity: String) -> String {
    "sev" + severity.prefix(1).uppercased() + severity.dropFirst()
}

/**
 How much of the diagnostics log travels with a report.

 Web's \`.slice(0, ${CAP})\` — "a report is for diagnosing, not archiving a whole
 session", in its own words.
 */
public let feedbackDiagnosticsCap = ${CAP}

/// The version stamped on a report. Web's \`APP_VERSION\` constant.
public let feedbackAppVersion = ${JSON.stringify(APP_VERSION)}

/// Web truncates the user-agent string to this before storing it.
public let feedbackUserAgentCap = ${UA_CAP}
`;

writeFileSync(KT_OUT, kt);
writeFileSync(SWIFT_OUT, swift);
console.log(
  `feedback: ${areas.length} area(s), ${severities.length} severities, log cap ${CAP}, ua cap ${UA_CAP}, version ${APP_VERSION}`,
);
console.log("Wrote:\n - " + [KT_OUT, SWIFT_OUT].map((f) => path.relative(REPO_ROOT, f)).join("\n - "));
console.log("\ni18n keys expected in packages/core/i18n/src/locales/feedback/:");
console.log("  " + areas.map((a) => "area" + slug(a).replace(/^(.)/, (c) => c.toUpperCase())).join(", "));
