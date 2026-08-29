package com.sanvya.app.domain.goals

/**
 * What to do about a goal that may or may not have just been fully funded.
 *
 * [celebrated] is the NEW set to persist, so the caller never has to reason
 * about which branch mutates it -- it either writes what comes back or writes
 * nothing.
 */
data class CelebrationDecision(val celebrate: Boolean, val celebrated: Set<String>)

/**
 * Whether reaching a goal earns its one-time celebration, ported from the
 * `useEffect` in apps/web/app/goals/page.tsx's `GoalCard`.
 *
 * Three rules, all of them load-bearing and all of them easy to get wrong:
 *
 * 1. **Only the transition counts.** [wasFunded] is null on the first
 *    observation of a goal, and a null seeds the state without celebrating.
 *    Without that, every goal already at its target throws a party the moment
 *    the screen opens -- once per app launch, forever.
 * 2. **Once per goal.** [celebrated] is persisted across launches (web keeps it
 *    in `localStorage` under `pc_goals_celebrated`), so a goal that is funded,
 *    scrolled away from and come back to does not celebrate twice.
 * 3. **Dropping below the target re-arms it.** A goal that loses its funded
 *    status is REMOVED from the set, so genuinely reaching it again is worth
 *    another moment. This is the branch that makes the persisted set behave
 *    like a latch rather than a tombstone.
 *
 * Pure, and vector-pinned (tools/golden-vectors/vectors/goal-celebration.json)
 * because the null-seeding rule is exactly the kind of thing two hand-written
 * ports drift apart on.
 */
fun goalCelebration(
    goalId: String,
    wasFunded: Boolean?,
    funded: Boolean,
    celebrated: Set<String>,
): CelebrationDecision = when {
    wasFunded == false && funded && !celebrated.contains(goalId) ->
        CelebrationDecision(celebrate = true, celebrated = celebrated + goalId)
    !funded && celebrated.contains(goalId) ->
        CelebrationDecision(celebrate = false, celebrated = celebrated - goalId)
    else -> CelebrationDecision(celebrate = false, celebrated = celebrated)
}
