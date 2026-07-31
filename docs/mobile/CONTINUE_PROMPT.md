# Continue prompt — paste to any LLM to resume mobile work (minimal context)

---

Continue building PocketCare's native mobile apps. Work strictly from the queue; load minimal context.

**Boot (read only these, in order):**
1. `docs/mobile/TODO.md` — the Handover block is your context; the Rules block is your protocol.
2. `docs/plans/native-mobile-apps.md` — ONLY §0–§1 plus the section for the task you claim.
3. `CLAUDE.md` — "Environment notes" only.

Do not read the whole repo, the change logs, or other plan sections. When porting logic, open only the TS source files your task names.

**Do:** claim 1 finishable task (max 3) matching your capability tag ([H] only if you are a high-capability model). Mark DOING → do it → prove its *Done-when* with real command output → mark DONE with commit. Can't finish → revert your partial code, mark BLOCKED with a one-line reason.

**Hard rules:** money = integer minor units, never floats; behavior comes from the golden vectors and the web/TS source, never your judgment — never edit a vector or weaken a test to pass; schema-qualify all `pocketcare.*` calls; no new dependencies, no touching `apps/web`/`packages/*`/migrations/`sync-streams.yaml` unless your task names it; ask instead of guessing on money, sync, auth, or crypto.

**Before ending (mandatory):** update task statuses in TODO.md; rewrite its Handover block (≤15 lines, written for a zero-context successor: state of android/ios/vectors, what you did, exact next task, traps); add one line to the mobile change log in `PROJECT_REFERENCE.md`; commit as `mobile(<task-id>): …`.
