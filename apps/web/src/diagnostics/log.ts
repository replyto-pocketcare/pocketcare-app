"use client";

/**
 * On-device support log.
 *
 * The problem this solves: on a laptop you can ask someone to open the console.
 * On a phone you cannot, so every useful detail of a failure — the PostgREST
 * code, the table, the operation — is written to a place nobody can read. The
 * user reports "syncing isn't working" and that is genuinely all anyone knows.
 *
 * So: a small in-memory ring buffer, mirrored to localStorage so it survives a
 * reload or a crash, fed by console.error/warn, window errors, unhandled
 * rejections, and explicit structured calls from the sync layer.
 *
 * EVERY entry is redacted on the way in (see @pocketcare/diagnostics). Nothing
 * unscrubbed is ever stored, so there is no path by which a support log leaks
 * someone's spending — not even if it's later attached to a bug report.
 */
import { formatLog, makeEntry, type LogEntry, type LogLevel } from "@pocketcare/diagnostics";

/** Enough to cover a session's worth of trouble without bloating localStorage. */
const MAX_ENTRIES = 150;
const STORAGE_KEY = "pc_diag_log";

let buffer: LogEntry[] = [];
let installed = false;
let currentRoute: string | undefined;
const listeners = new Set<() => void>();

function persist(): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(buffer));
  } catch {
    // Quota or private mode — the in-memory buffer still works for this session.
  }
}

function emit(): void {
  for (const fn of listeners) fn();
}

/** Record an event. Message and detail are redacted before they are stored. */
export function logEvent(
  level: LogLevel,
  scope: string,
  message: string,
  detail?: Record<string, unknown>,
): void {
  try {
    const entry = makeEntry(level, scope, message, {
      route: currentRoute,
      ...(detail ? { detail } : {}),
    });
    buffer.push(entry);
    if (buffer.length > MAX_ENTRIES) buffer = buffer.slice(-MAX_ENTRIES);
    persist();
    emit();
  } catch {
    // Logging must never be the thing that breaks the app.
  }
}

/** Called by the app shell so entries carry the page they happened on. */
export function setDiagnosticsRoute(route: string): void {
  currentRoute = route;
}

export function getEntries(): LogEntry[] {
  return [...buffer];
}

export function clearEntries(): void {
  buffer = [];
  persist();
  emit();
}

export function subscribe(fn: () => void): () => void {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

/** Device/app context that goes at the top of a shared log. */
export function captureContext(extra: Record<string, unknown> = {}): Record<string, unknown> {
  if (typeof navigator === "undefined") return extra;
  const ua = navigator.userAgent;
  const platform = /iPhone|iPad|iPod/.test(ua) ? "iOS" : /Android/.test(ua) ? "Android" : "desktop";
  return {
    when: new Date().toISOString(),
    platform,
    standalone: typeof window !== "undefined" && window.matchMedia("(display-mode: standalone)").matches,
    viewport: typeof window !== "undefined" ? `${window.innerWidth}x${window.innerHeight}` : "—",
    online: navigator.onLine,
    language: navigator.language,
    // Trimmed: the full UA is long and the useful part is at the end.
    userAgent: ua.slice(0, 200),
    ...extra,
  };
}

/** The whole log as pasteable plain text. */
export function exportLog(extra: Record<string, unknown> = {}): string {
  return formatLog(getEntries(), captureContext(extra));
}

/**
 * Patch the console and window error hooks. Idempotent, browser-only.
 *
 * console.error/warn are wrapped rather than replaced: the originals are still
 * called, so devtools behaves exactly as before for anyone who does have it.
 */
export function installDiagnostics(): void {
  if (installed || typeof window === "undefined") return;
  installed = true;

  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored) {
      const parsed = JSON.parse(stored) as LogEntry[];
      if (Array.isArray(parsed)) buffer = parsed.slice(-MAX_ENTRIES);
    }
  } catch {
    /* corrupt or unavailable — start fresh */
  }

  const wrap = (level: LogLevel, original: (...a: unknown[]) => void) =>
    (...args: unknown[]) => {
      original(...args);
      try {
        // Skip our own output, or a failure inside logging loops forever.
        const text = args.map(stringifyArg).join(" ");
        if (!text.startsWith("[diagnostics]")) logEvent(level, "console", text);
      } catch {
        /* never let logging break the caller */
      }
    };

  /* eslint-disable no-console */
  console.error = wrap("error", console.error.bind(console));
  console.warn = wrap("warn", console.warn.bind(console));
  /* eslint-enable no-console */

  window.addEventListener("error", (e) => {
    logEvent("error", "window", e.message || "Script error", {
      source: e.filename ? String(e.filename).split("/").pop() : undefined,
      line: e.lineno,
    });
  });

  window.addEventListener("unhandledrejection", (e) => {
    const reason = (e as PromiseRejectionEvent).reason;
    logEvent("error", "promise", reason instanceof Error ? reason.message : String(reason));
  });

  window.addEventListener("online", () => logEvent("info", "network", "back online"));
  window.addEventListener("offline", () => logEvent("warn", "network", "went offline"));

  logEvent("info", "app", "diagnostics started");
}

/** Errors stringify to "[object Object]" otherwise, which helps nobody. */
function stringifyArg(a: unknown): string {
  if (a instanceof Error) return `${a.name}: ${a.message}`;
  if (typeof a === "string") return a;
  try {
    return JSON.stringify(a);
  } catch {
    return String(a);
  }
}
