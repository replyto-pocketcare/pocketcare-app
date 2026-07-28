/**
 * @pocketcare/sync-policy — is this upload failure worth retrying?
 *
 * THE DISTINCTION THAT MATTERS: PowerSync retries the upload queue forever, in
 * order. That is exactly right for a transient failure (offline, 5xx, timeout)
 * and exactly wrong for a permanent one (RLS denial, foreign key violation,
 * check constraint). A permanently-failing op can never succeed, so retrying it
 * forever means the user's queue is **head-of-line blocked** indefinitely, and
 * every unrelated write behind it is frozen too.
 *
 * Getting this classification wrong is expensive in both directions:
 *  - Treating a transient failure as permanent quarantines good data for a
 *    network blip.
 *  - Treating a permanent failure as transient is what wedged a user's account
 *    and ultimately cost them data.
 *
 * So: **default to transient.** An unknown failure keeps retrying, which is the
 * recoverable mistake. Only a recognised, unambiguous permanent signal
 * quarantines.
 *
 * Erasable TS only, so `node --experimental-strip-types` runs the tests.
 */

export const FAILURE_CLASSES = {
  /** Will plausibly succeed later. Keep retrying, forever if need be. */
  transient: "transient",
  /** Can never succeed as-is. Quarantine after a few attempts. */
  permanent: "permanent",
} as const;
export type FailureClass = (typeof FAILURE_CLASSES)[keyof typeof FAILURE_CLASSES];

/**
 * Postgres SQLSTATEs that mean "this write is invalid", not "try again".
 * Deliberately a short allow-list of codes we understand.
 */
const PERMANENT_PG_CODES = new Set([
  "23502", // not_null_violation
  "23503", // foreign_key_violation   ← the orphaned-child case
  "23505", // unique_violation
  "23514", // check_violation
  "22001", // string_data_right_truncation
  "22003", // numeric_value_out_of_range
  "22P02", // invalid_text_representation
  "42501", // insufficient_privilege  ← RLS denial
  "42703", // undefined_column
  "42P01", // undefined_table
  "P0001", // raise_exception (our own triggers)
]);

/**
 * SQLSTATEs that look alarming but genuinely resolve on retry.
 * Listed explicitly so they can't be swept up by a broader rule later.
 */
const TRANSIENT_PG_CODES = new Set([
  "40001", // serialization_failure
  "40P01", // deadlock_detected
  "53300", // too_many_connections
  "57014", // query_canceled
  "08006", // connection_failure
]);

export interface FailureInput {
  /** HTTP status, when the transport gave us one. */
  readonly status?: number | undefined;
  /** Postgres SQLSTATE from PostgREST. */
  readonly code?: string | undefined;
  readonly message?: string | undefined;
}

export interface Classification {
  readonly cls: FailureClass;
  /** Why, in terms a maintainer can act on. */
  readonly reason: string;
}

/**
 * Classify one upload failure.
 *
 * Order is deliberate: an explicit SQLSTATE beats an HTTP status, because
 * PostgREST reports several genuinely different conditions as 400.
 */
export function classifyFailure(input: FailureInput): Classification {
  const code = (input.code ?? "").trim();

  if (code && TRANSIENT_PG_CODES.has(code)) {
    return { cls: "transient", reason: `postgres ${code} resolves on retry` };
  }
  if (code && PERMANENT_PG_CODES.has(code)) {
    return { cls: "permanent", reason: `postgres ${code} is a rejected write` };
  }

  const status = input.status;
  if (typeof status === "number") {
    // 408 timeout and 429 rate-limit are retryable despite being 4xx.
    if (status === 408 || status === 429) {
      return { cls: "transient", reason: `http ${status} is retryable` };
    }
    // 401 is retryable: the token refreshes and the next attempt succeeds.
    // Quarantining a user's writes because a JWT expired would be terrible.
    if (status === 401) {
      return { cls: "transient", reason: "http 401 — token refresh should fix it" };
    }
    if (status >= 400 && status < 500) {
      return { cls: "permanent", reason: `http ${status} — the server rejected this` };
    }
    if (status >= 500) {
      return { cls: "transient", reason: `http ${status} — server-side, try again` };
    }
  }

  const message = (input.message ?? "").toLowerCase();
  // Fetch failures surface as a TypeError with no status at all.
  if (/failed to fetch|network|timeout|aborted|offline|econn/.test(message)) {
    return { cls: "transient", reason: "network error" };
  }
  // RLS sometimes arrives as prose without a code.
  if (/row-level security|violates .*policy/.test(message)) {
    return { cls: "permanent", reason: "row-level security denial" };
  }

  // Unknown: keep retrying. The recoverable mistake.
  return { cls: "transient", reason: "unrecognised failure — retrying is the safe default" };
}

/** Attempts before a permanent failure is quarantined. */
export const MAX_PERMANENT_ATTEMPTS = 3;

/**
 * Should this op be moved to the dead-letter queue?
 *
 * Even a permanent-looking failure gets a few attempts: a foreign key can
 * genuinely resolve if the parent is a little way behind it in the same queue,
 * and a deploy racing a migration can produce a transient 42P01.
 */
export function shouldQuarantine(c: Classification, attempts: number): boolean {
  return c.cls === "permanent" && attempts >= MAX_PERMANENT_ATTEMPTS;
}

/** Exponential backoff with a ceiling, for transient retries. */
export function backoffMs(attempts: number, base = 1000, ceiling = 60_000): number {
  return Math.min(ceiling, base * 2 ** Math.max(0, attempts - 1));
}

/**
 * Plain-language explanation for the recovery screen.
 *
 * Users see this, so it says what happened and what they can do — never
 * `23503`. The maintainer-facing detail is in the diagnostics log.
 */
export function explainForUser(input: FailureInput): string {
  const code = (input.code ?? "").trim();
  switch (code) {
    case "23503":
      return "It refers to something that no longer exists — the group or account it belonged to may have been deleted.";
    case "23505":
      return "It looks like this was already saved once.";
    case "23514":
    case "P0001":
      return "Some of the numbers didn't add up, so the server wouldn't accept it.";
    case "42501":
      // Deliberately does NOT assert "you were removed from the group": the
      // same code is raised when the parent row (e.g. the group itself) never
      // reached the server, in which case the user is still very much a member
      // and telling them otherwise sends them looking in the wrong place.
      return "You don't have permission to save this yet. If it belongs to a group, try Settings → Check for unsynced data — the group itself may not have uploaded.";
    case "23502":
      return "Something required was missing from it.";
    default:
      return classifyFailure(input).cls === "permanent"
        ? "The server wouldn't accept it."
        : "It hasn't uploaded yet. We'll keep trying.";
  }
}
