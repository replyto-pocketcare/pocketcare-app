package com.sanvya.app.domain.onboarding

/**
 * When the first-run walkthrough should be on screen.
 * Ported from `useWalkthrough` in apps/web/src/onboarding/useWalkthrough.ts.
 *
 * Five conditions, and four of them exist to stop it appearing at the WRONG
 * moment rather than to make it appear:
 *
 * - `done` is permanent (a preference); `skipped` lasts one session only, so
 *   "I'll look around myself" returns next launch while there is still no
 *   account, and "Finish" never returns.
 * - `syncPending` -- never during the first sync. A RETURNING user's accounts
 *   have not arrived yet, and telling them to set up from scratch would be
 *   alarming.
 * - `accountCountLoaded` -- never on a still-loading count. Web's predecessor
 *   had exactly this bug: counts start empty, so it rendered and then vanished
 *   a beat later.
 * - `signedIn` -- there is nobody to onboard before there is a session.
 *
 * The account count is of REAL accounts only: the virtual split accounts
 * ("Owed to me" / "I owe") are bookkeeping, and a user who has only those has
 * not set anything up.
 *
 * Mirrors apps/ios/Domain/Sources/Domain/Walkthrough.swift.
 */
fun shouldShowWalkthrough(
    done: Boolean,
    skipped: Boolean,
    syncPending: Boolean,
    accountCountLoaded: Boolean,
    realAccountCount: Int,
    signedIn: Boolean,
): Boolean = !done && !skipped && !syncPending && accountCountLoaded && realAccountCount == 0 && signedIn

/**
 * The step numbering the header shows.
 *
 * Part A (1-4) is setup and ends in a real Finish. Part B (5-7) is opt-in --
 * making onboarding LONGER would be the wrong answer to "I found this
 * overwhelming", so the counter restarts rather than reading "step 5 of 7".
 */
data class WalkthroughProgress(val step: Int, val of: Int)

fun walkthroughProgress(step: Int): WalkthroughProgress =
    if (step <= 4) WalkthroughProgress(step, 4) else WalkthroughProgress(step - 4, 3)
