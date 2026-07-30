"use client";

/**
 * When to show the first-run walkthrough.
 *
 * Replaces the dashboard `GettingStarted` checklist, which explained each step's
 * *why* but linked AWAY to `/accounts/new` — so the explanation stayed behind
 * exactly when the user met a form headed "New account" offering Savings /
 * Current / Credit card. A real 60+ user read that as "link my bank" and
 * stopped. See docs/plans/first-run-walkthrough.md.
 */

import { useCallback, useEffect, useState } from "react";
import { useQuery } from "@powersync/react";
import { useInitialSyncPending } from "../sync";
import { useSession } from "../account";
import { trialWelcomeSeenKey } from "../ui/TrialNotice";

const DONE_KEY = "pocketcare:walkthroughDone";
const SKIP_KEY = "pocketcare:walkthroughSkipped"; // sessionStorage — this session only

const readLocal = (k: string) => {
  try { return localStorage.getItem(k) === "1"; } catch { return false; }
};
const readSession = (k: string) => {
  try { return sessionStorage.getItem(k) === "1"; } catch { return false; }
};

export interface WalkthroughState {
  open: boolean;
  /** Close for this session only; it returns next visit while there's no account. */
  skip: () => void;
  /** Close for good. */
  finish: () => void;
}

export function useWalkthrough(): WalkthroughState {
  const syncPending = useInitialSyncPending();
  const session = useSession();

  // Read the done flag synchronously so a returning user never gets a frame of
  // the dialog. `GettingStarted` had exactly this bug: counts start empty, so
  // it rendered, then vanished a beat later.
  const [done, setDone] = useState(() => readLocal(DONE_KEY));
  const [skipped, setSkipped] = useState(() => readSession(SKIP_KEY));

  const { data: acc = [], isLoading } = useQuery<{ c: number }>(
    "SELECT COUNT(*) AS c FROM accounts WHERE deleted_at IS NULL AND IFNULL(kind,'real')='real'",
  );
  const hasAccount = (acc[0]?.c ?? 0) > 0;

  // Judge only on a definitive answer: never while the first sync is in flight
  // (a returning user's accounts haven't arrived yet — telling them to set up
  // from scratch would be alarming) and never on a still-loading count.
  const open = !done && !skipped && !syncPending && !isLoading && !hasAccount && !!session;

  /**
   * The walkthrough ABSORBS the trial welcome dialog. `TrialNotice` shows its
   * own one-time "your 14-day trial is live" modal; without this a new user
   * gets both, stacked, saying overlapping things. Step 7 covers the trial.
   */
  useEffect(() => {
    if (!open || !session) return;
    try { localStorage.setItem(trialWelcomeSeenKey(session.email), "true"); } catch { /* ignore */ }
  }, [open, session]);

  const skip = useCallback(() => {
    try { sessionStorage.setItem(SKIP_KEY, "1"); } catch { /* ignore */ }
    setSkipped(true);
  }, []);

  const finish = useCallback(() => {
    try { localStorage.setItem(DONE_KEY, "1"); } catch { /* ignore */ }
    setDone(true);
  }, []);

  return { open, skip, finish };
}
