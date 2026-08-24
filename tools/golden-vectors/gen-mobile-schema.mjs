#!/usr/bin/env node
/**
 * Renders tools/golden-vectors/vectors/mobile-schema.json into:
 *   - apps/android/domain/src/main/kotlin/care/pocket/domain/db/PocketCareSchema.kt
 *   - apps/ios/Domain/Sources/Domain/PocketCareSchema.swift
 *
 * This IS the schema-parity check (docs/mobile/TODO.md P2.1): after changing
 * packages/db/src/index.ts, run
 *   node tools/golden-vectors/export-mobile-schema.mjs
 *   node tools/golden-vectors/gen-mobile-schema.mjs
 * and `git diff` the two generated files. A clean diff means the TS schema
 * and both native mirrors already agree; any diff shows exactly which
 * tables/columns drifted. Both generated files carry a header saying not to
 * hand-edit them, for the same reason.
 *
 * Run: node tools/golden-vectors/gen-mobile-schema.mjs
 */
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const jsonPath = path.join(repoRoot, "tools", "golden-vectors", "vectors", "mobile-schema.json");
// The Kotlin package, in one place, because the path on disk and the `package`
// declaration in the generated file must agree and previously did not.
//
// This script wrote to care/pocket/domain/db/ with `package care.pocket.domain.db`
// long after the Android sources moved to com.sanvya.app. Running it therefore
// created a SECOND, orphaned schema file and left the real one -- the one both
// PowerSync and every repository actually read -- untouched and stale. Nothing
// failed; the generator reported success. That is how `recurring_items` stayed
// missing from the native schema across four migrations.
const KOTLIN_PACKAGE = "com.sanvya.app.domain.db";

const kotlinPath = path.join(
  repoRoot,
  "apps",
  "android",
  "domain",
  "src",
  "main",
  "kotlin",
  ...KOTLIN_PACKAGE.split("."),
  "PocketCareSchema.kt",
);
const swiftPath = path.join(repoRoot, "apps", "ios", "Domain", "Sources", "Domain", "PocketCareSchema.swift");

const { tables } = JSON.parse(readFileSync(jsonPath, "utf8"));

const HEADER = `Mirrors packages/db/src/index.ts's `+"`AppSchema`"+` (the PowerSync client
schema / local SQLite mirror), generated from
tools/golden-vectors/vectors/mobile-schema.json by
tools/golden-vectors/gen-mobile-schema.mjs. DO NOT HAND-EDIT — see that
script's header for how to regenerate after packages/db/src/index.ts
changes, and how this doubles as the schema-parity check across all three
platforms.

Every table has an implicit `+"`id: TEXT`"+` primary key managed by PowerSync
itself; it is intentionally omitted from `+"`columns`"+` below (present on every
table, so listing it 63 times would be noise, not information) and is
assumed by any code consuming this schema.

This is a data-driven schema DESCRIPTOR (table/column names, SQLite
storage type, indexes, local-only flags) — not per-table row model
classes. Strongly-typed row models are P2.5 (repositories) territory,
once the local SQLite driver is chosen for each platform.`;

function kotlinString(s) {
  return JSON.stringify(s);
}

function kotlinColumns(columns) {
  if (columns.length === 0) return "emptyList()";
  const items = columns.map((c) => `ColumnDef(${kotlinString(c.name)}, ColumnType.${c.type})`);
  return `listOf(\n${items.map((i) => `                ${i},`).join("\n")}\n            )`;
}

function kotlinIndexes(indexes) {
  if (indexes.length === 0) return "emptyList()";
  const items = indexes.map((idx) => {
    const cols = idx.columns
      .map((c) => `IndexColumnDef(${kotlinString(c.name)}, ${c.ascending}, ColumnType.${c.type})`)
      .join(", ");
    return `IndexDef(${kotlinString(idx.name)}, listOf(${cols}))`;
  });
  return `listOf(\n${items.map((i) => `                ${i},`).join("\n")}\n            )`;
}

function renderKotlinTable(t) {
  return `        TableDef(
            name = ${kotlinString(t.name)},
            viewName = ${kotlinString(t.view_name)},
            columns = ${kotlinColumns(t.columns)},
            indexes = ${kotlinIndexes(t.indexes)},
            localOnly = ${t.local_only},
            insertOnly = ${t.insert_only},
        ),`;
}

const kotlin = `package ${KOTLIN_PACKAGE}

/**
 * ${HEADER.split("\n").join("\n * ")}
 */

enum class ColumnType { TEXT, INTEGER, REAL }

data class ColumnDef(val name: String, val type: ColumnType)

data class IndexColumnDef(val name: String, val ascending: Boolean, val type: ColumnType)

data class IndexDef(val name: String, val columns: List<IndexColumnDef>)

data class TableDef(
    val name: String,
    val viewName: String,
    val columns: List<ColumnDef>,
    val indexes: List<IndexDef>,
    val localOnly: Boolean,
    val insertOnly: Boolean,
)

object PocketCareSchema {
    val tables: List<TableDef> = listOf(
${tables.map(renderKotlinTable).join("\n")}
    )

    val byName: Map<String, TableDef> = tables.associateBy { it.name }
}
`;

function swiftString(s) {
  return JSON.stringify(s);
}

function swiftColumns(columns) {
  if (columns.length === 0) return "[]";
  const items = columns.map((c) => `ColumnDef(name: ${swiftString(c.name)}, type: .${c.type.toLowerCase()})`);
  return `[\n${items.map((i) => `                ${i},`).join("\n")}\n            ]`;
}

function swiftIndexes(indexes) {
  if (indexes.length === 0) return "[]";
  const items = indexes.map((idx) => {
    const cols = idx.columns
      .map(
        (c) =>
          `IndexColumnDef(name: ${swiftString(c.name)}, ascending: ${c.ascending}, type: .${c.type.toLowerCase()})`,
      )
      .join(", ");
    return `IndexDef(name: ${swiftString(idx.name)}, columns: [${cols}])`;
  });
  return `[\n${items.map((i) => `                ${i},`).join("\n")}\n            ]`;
}

function renderSwiftTable(t) {
  return `        TableDef(
            name: ${swiftString(t.name)},
            viewName: ${swiftString(t.view_name)},
            columns: ${swiftColumns(t.columns)},
            indexes: ${swiftIndexes(t.indexes)},
            localOnly: ${t.local_only},
            insertOnly: ${t.insert_only}
        ),`;
}

const swift = `/**
 * ${HEADER.split("\n").join("\n * ")}
 */

public enum ColumnType: String, Sendable {
    case text = "TEXT"
    case integer = "INTEGER"
    case real = "REAL"
}

public struct ColumnDef: Sendable {
    public let name: String
    public let type: ColumnType
}

public struct IndexColumnDef: Sendable {
    public let name: String
    public let ascending: Bool
    public let type: ColumnType
}

public struct IndexDef: Sendable {
    public let name: String
    public let columns: [IndexColumnDef]
}

public struct TableDef: Sendable {
    public let name: String
    public let viewName: String
    public let columns: [ColumnDef]
    public let indexes: [IndexDef]
    public let localOnly: Bool
    public let insertOnly: Bool
}

public enum PocketCareSchema {
    public static let tables: [TableDef] = [
${tables.map(renderSwiftTable).join("\n")}
    ]

    public static let byName: [String: TableDef] = Dictionary(uniqueKeysWithValues: tables.map { ($0.name, $0) })
}
`;

writeFileSync(kotlinPath, kotlin, "utf8");
writeFileSync(swiftPath, swift, "utf8");
console.log(`Wrote ${tables.length} tables to:`);
console.log(`  ${path.relative(repoRoot, kotlinPath)}`);
console.log(`  ${path.relative(repoRoot, swiftPath)}`);
