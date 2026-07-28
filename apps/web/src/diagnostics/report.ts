"use client";

/**
 * Automatic error reporting → the admin panel.
 *
 * Most users never file a bug report. They just say "it's not working", or say
 * nothing at all and stop using the app. So errors report themselves.
 *
 * SENT DIRECTLY OVER HTTP, NOT THROUGH POWERSYNC. The failure we most need to
 * see is the sync queue being stuck — routing the report through that same
 * queue would guarantee it never arrives. This calls the RPC directly, which
 * works even when sync is completely wedged.
 *
 * Everything sent is already redacted (see @pocketcare/diagnostics): no
 * amounts, descriptions, merchants, emails or payment handles. Table names,
 * operations, error codes and row ids survive, which is what diagnoses a bug.
 */
import type { LogEntry } from "@pocketcare/diagnostics";

import { getSupabase } from "../powersync";
import { captureContext, subscribe, getEntries } from "./log";

const APP_VERSION = "0.1.0";

/** Per-session caps. The server enforces its own limit too — this just avoids the traffic. */
const MAX_REPORTS_PER_SESSION = 20;

const sentFingerprints = new Set<string>();
let sentCount = 0;
let started = false;
let lastSeenIndex = 0;

/**
 * Group the same bug together across users and sessions.
 *
 * Strips the varying parts — ids, remaining digits, quoted fragments — so
 * "upload failed for expense_items" from 40 devices is ONE row with a count,
 * not 40 rows. Without this the admin panel is unreadable within a day.
 */
export function fingerprint(entry: LogEntry): string {
  const normalized = entry.message
    .replace(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi, "<id>")
    .replace(/\d+/g, "<n>")
    .replace(/["'`].*?["'`]/g, "<s>")
    .trim()
    .slice(0, 160);
  return `${entry.scope}:${normalized}`;
}

async function send(entry: LogEntry): Promise<void> {
  const fp = fingerprint(entry);
  // Once per fingerprint per session: a retry loop is one bug, not 400.
  if (sentFingerprints.has(fp) || sentCount >= MAX_REPORTS_PER_SESSION) return;
  sentFingerprints.add(fp);
  sentCount++;

  const ctx = captureContext() as { platform?: string; userAgent?: string };
  try {
    // Schema-qualified: every PocketCare RPC lives in the `pocketcare` schema
    // and the browser client has no default schema set, so a bare .rpc() call
    // resolves to public.* and 404s (golden rule #3).
    await getSupabase().schema("pocketcare").rpc("report_client_error", {
      p_fingerprint: fp,
      p_message: entry.message,
      p_level: entry.level,
      p_scope: entry.scope,
      p_detail: entry.detail ?? null,
      p_route: entry.route ?? null,
      p_version: APP_VERSION,
      p_platform: ctx.platform ?? null,
      p_user_agent: ctx.userAgent ?? null,
    });
  } catch {
    // Reporting an error must never itself raise one. If it fails, the log is
    // still on the device and still rides along with any bug report.
  }
}

/**
 * Watch the diagnostics buffer and report new errors.
 *
 * Only `error` level: warnings are frequently benign, and a noisy admin panel
 * gets ignored, which is the same as having no admin panel.
 */
export function startErrorReporting(): void {
  if (started || typeof window === "undefined") return;
  started = true;
  lastSeenIndex = getEntries().length;

  subscribe(() => {
    const entries = getEntries();
    const fresh = entries.slice(lastSeenIndex);
    lastSeenIndex = entries.length;
    for (const e of fresh) {
      if (e.level === "error") void send(e);
    }
  });
}
