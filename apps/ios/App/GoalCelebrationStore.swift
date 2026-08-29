import Foundation

/**
 Which goals have already had their celebration.

 Web keeps this in `localStorage` under `pc_goals_celebrated`; the key is the
 same here so the two platforms describe the same thing, even though the storage
 is a `UserDefaults` string array rather than a JSON string. Not synced — it is
 a note about what this device has already shown someone, not ledger data, and
 syncing it would silence the moment on a second device that has never seen it.

 Deliberately NOT part of `Prefs`. That type is the mirror of web's `prefs.ts` —
 settings the user chose. This is feature-local bookkeeping with no settings
 screen behind it.

 Mirrors `apps/android/.../ui/goals/GoalCelebrationStore.kt`.
 */
enum GoalCelebrationStore {
    private static let key = "pc_goals_celebrated"

    static func celebrated() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func save(_ ids: Set<String>) {
        // Sorted, so the stored value is stable between writes that changed
        // nothing — a Set's order is not.
        UserDefaults.standard.set(ids.sorted(), forKey: key)
    }
}
