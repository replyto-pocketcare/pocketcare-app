import Foundation

/**
 What to do about a goal that may or may not have just been fully funded.

 `celebrated` is the NEW set to persist, so the caller never has to reason about
 which branch mutates it — it either writes what comes back or writes nothing.
 */
public struct CelebrationDecision: Sendable, Equatable {
    public let celebrate: Bool
    public let celebrated: Set<String>

    public init(celebrate: Bool, celebrated: Set<String>) {
        self.celebrate = celebrate
        self.celebrated = celebrated
    }
}

/**
 Whether reaching a goal earns its one-time celebration, ported from the
 `useEffect` in apps/web/app/goals/page.tsx's `GoalCard`.

 Three rules, all of them load-bearing and all of them easy to get wrong:

 1. **Only the transition counts.** `wasFunded` is nil on the first observation
    of a goal, and a nil seeds the state without celebrating. Without that,
    every goal already at its target throws a party the moment the screen opens
    — once per app launch, forever.
 2. **Once per goal.** `celebrated` is persisted across launches (web keeps it
    in `localStorage` under `pc_goals_celebrated`), so a goal that is funded,
    scrolled away from and come back to does not celebrate twice.
 3. **Dropping below the target re-arms it.** A goal that loses its funded
    status is REMOVED from the set, so genuinely reaching it again is worth
    another moment. This is the branch that makes the persisted set behave like
    a latch rather than a tombstone.

 Pure, and vector-pinned (tools/golden-vectors/vectors/goal-celebration.json)
 because the nil-seeding rule is exactly the kind of thing two hand-written
 ports drift apart on.

 Mirrors `apps/android/.../domain/goals/Celebration.kt`.
 */
public func goalCelebration(
    goalId: String,
    wasFunded: Bool?,
    funded: Bool,
    celebrated: Set<String>
) -> CelebrationDecision {
    if wasFunded == false, funded, !celebrated.contains(goalId) {
        return CelebrationDecision(celebrate: true, celebrated: celebrated.union([goalId]))
    }
    if !funded, celebrated.contains(goalId) {
        return CelebrationDecision(celebrate: false, celebrated: celebrated.subtracting([goalId]))
    }
    return CelebrationDecision(celebrate: false, celebrated: celebrated)
}
