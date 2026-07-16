# Splits — Friends, Groups & Trips

## Overview
A **multi-user shared ledger** for splitting expenses. Users form **groups/trips**, add shared expenses split among members, settle up, and see net balances. Unlike the rest of the app, splits data is visible by **group membership**, not single ownership.

## User flow
```mermaid
flowchart TD
    F([Friends / Groups]) --> Grp[Create group or trip]
    Grp --> Invite[Invite people by email / connection]
    Invite --> Join[Invitee joins → split_group_members]
    Join --> Exp[Add shared expense\n(amount, split mode, participants)]
    Exp --> Bal[Net balances per person]
    Bal --> Settle[Settle up → settlement + optional transfer]
    Bal --> Remind[Remind (share/copy message)]
```

## Technical flow — visibility & reconciliation
```mermaid
flowchart LR
    Members["split_group_members"] --> Stream["split_shared sync stream\n(JOIN membership)"]
    Stream --> Local[("member's local SQLite")]
    Expenses["expenses + expense_participants"] --> Recon["@pocketcare/reconcile\nnet balances"]
    Settlements["settlements"] --> Recon
    Recon --> UI["Owed / owe per person + net position"]
```

## Data touched
`split_groups`, `split_group_members`, `expenses`, `expense_participants`, `settlements`, `split_invitations`, `connections`, `expense_postings` (private per-user projection into personal budget). Shared visibility via the `split_shared` stream + membership RLS.

## Key files
`app/friends/`, `app/groups/`, `app/groups/[id]`, `src/splits/hooks.ts`, `src/splits/write.ts` (`settleUp`), `@pocketcare/reconcile`.

## Gating
Free.

## Edge cases
- **Deletion:** splits FKs to `auth.users` are **not** all `ON DELETE CASCADE`; account deletion clears them explicitly first (migration `0031`).
- Direct 1:1 splits use an auto-created `is_direct` container group.
- `expense_postings` mirror a user's share into their personal budget without exposing it to the group.
- Friends/Groups lists tile responsively; an expanded group spans the full row.
