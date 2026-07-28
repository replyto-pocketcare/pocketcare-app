import { test } from "node:test";
import assert from "node:assert/strict";

import {
  backoffMs,
  classifyFailure,
  explainForUser,
  MAX_PERMANENT_ATTEMPTS,
  shouldQuarantine,
} from "./index.ts";

// ---------------------------------------------------------------------------
// The real incidents. These are the cases that actually cost a user data.
// ---------------------------------------------------------------------------

test("the RLS denial that wedged an account is permanent", () => {
  const c = classifyFailure({
    status: 403,
    code: "42501",
    message: 'new row violates row-level security policy for table "split_group_members"',
  });
  assert.equal(c.cls, "permanent");
});

test("the check-constraint failure from the 0040 sum trigger is permanent", () => {
  const c = classifyFailure({
    status: 400,
    code: "23514",
    message: "expense_items for <id> sum to 20000 but the expense total is 1258784",
  });
  assert.equal(c.cls, "permanent");
});

test("an orphaned child row (foreign key) is permanent", () => {
  assert.equal(classifyFailure({ status: 409, code: "23503" }).cls, "permanent");
});

// ---------------------------------------------------------------------------
// Transient — must NEVER be quarantined
// ---------------------------------------------------------------------------

test("being offline is transient", () => {
  assert.equal(classifyFailure({ message: "TypeError: Failed to fetch" }).cls, "transient");
  assert.equal(classifyFailure({ message: "network request timed out" }).cls, "transient");
});

test("server errors are transient", () => {
  for (const status of [500, 502, 503, 504]) {
    assert.equal(classifyFailure({ status }).cls, "transient", `http ${status}`);
  }
});

test("timeout and rate-limit are transient despite being 4xx", () => {
  assert.equal(classifyFailure({ status: 408 }).cls, "transient");
  assert.equal(classifyFailure({ status: 429 }).cls, "transient");
});

test("an expired token is transient — a refresh fixes it", () => {
  // Quarantining a user's writes because a JWT lapsed would be terrible.
  assert.equal(classifyFailure({ status: 401 }).cls, "transient");
});

test("deadlock and serialization failures are transient", () => {
  assert.equal(classifyFailure({ status: 500, code: "40001" }).cls, "transient");
  assert.equal(classifyFailure({ status: 500, code: "40P01" }).cls, "transient");
});

// ---------------------------------------------------------------------------
// The safe default
// ---------------------------------------------------------------------------

test("an unrecognised failure defaults to transient", () => {
  // Retrying forever is recoverable; quarantining good data is not.
  assert.equal(classifyFailure({}).cls, "transient");
  assert.equal(classifyFailure({ message: "something strange" }).cls, "transient");
  assert.equal(classifyFailure({ code: "99999" }).cls, "transient");
});

test("a known SQLSTATE beats the HTTP status", () => {
  // PostgREST reports genuinely different conditions as 400, so the code wins.
  assert.equal(classifyFailure({ status: 400, code: "40001" }).cls, "transient");
  assert.equal(classifyFailure({ status: 500, code: "23503" }).cls, "permanent");
});

test("an RLS denial with no code is still caught from the message", () => {
  assert.equal(
    classifyFailure({ message: 'new row violates row-level security policy for table "x"' }).cls,
    "permanent",
  );
});

test("every classification carries a reason", () => {
  for (const input of [{ status: 500 }, { code: "23503" }, {}, { status: 429 }]) {
    assert.ok(classifyFailure(input).reason.length > 0);
  }
});

// ---------------------------------------------------------------------------
// Quarantine policy
// ---------------------------------------------------------------------------

test("a transient failure is never quarantined, however many attempts", () => {
  const c = classifyFailure({ status: 503 });
  for (const attempts of [1, 5, 100, 10_000]) {
    assert.equal(shouldQuarantine(c, attempts), false, `attempts=${attempts}`);
  }
});

test("a permanent failure quarantines only after the attempt threshold", () => {
  const c = classifyFailure({ code: "23503" });
  assert.equal(shouldQuarantine(c, 1), false);
  assert.equal(shouldQuarantine(c, MAX_PERMANENT_ATTEMPTS - 1), false);
  assert.equal(shouldQuarantine(c, MAX_PERMANENT_ATTEMPTS), true);
});

test("permanent failures get retries — a parent may be just behind in the queue", () => {
  assert.ok(MAX_PERMANENT_ATTEMPTS >= 2, "one attempt is too eager to give up");
});

// ---------------------------------------------------------------------------
// Backoff
// ---------------------------------------------------------------------------

test("backoff grows and then stops growing", () => {
  assert.equal(backoffMs(1), 1000);
  assert.equal(backoffMs(2), 2000);
  assert.equal(backoffMs(3), 4000);
  assert.equal(backoffMs(50), 60_000);
});

test("backoff is never negative or zero", () => {
  for (const a of [0, -1, 1]) assert.ok(backoffMs(a) > 0);
});

// ---------------------------------------------------------------------------
// User-facing copy — this is what someone reads when their data didn't save
// ---------------------------------------------------------------------------

test("explanations never leak a SQLSTATE to the user", () => {
  for (const code of ["23503", "23505", "23514", "42501", "23502", "P0001"]) {
    const text = explainForUser({ code });
    assert.equal(/\d{5}|[A-Z]\d{4}/.test(text), false, `leaked a code: ${text}`);
    assert.ok(text.length > 10, `unhelpfully short: ${text}`);
  }
});

test("a missing parent is explained in terms of what the user deleted", () => {
  assert.match(explainForUser({ code: "23503" }), /no longer exists/i);
});

test("an RLS denial is explained as a permission problem", () => {
  assert.match(explainForUser({ code: "42501" }), /permission/i);
});

test("a still-retrying failure reassures rather than alarms", () => {
  assert.match(explainForUser({ status: 503 }), /keep trying/i);
});
