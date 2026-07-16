# Ask PocketCare (AI Assistant)

## Overview
A conversational assistant with a "conscious-decision" persona that answers finance questions grounded in the user's data snapshot, renders **visual/actionable responses** (stat cards, progress, action chips), and can perform **confirm-gated actions** (record a transaction, create a subscription, create a group). Native-messenger chat UX with persistent threads.

## User flow
```mermaid
flowchart TD
    A([Ask PocketCare]) --> Land[Landing: new chat / continue]
    Land --> Chat[Chat thread]
    Chat --> Ask[User asks / requests action]
    Ask --> Resp[Prose + <ui> cards/actions]
    Resp --> ActChip{Action chip}
    ActChip -->|send| Follow[Sends a follow-up message]
    ActChip -->|href| Nav[Navigates to a page]
    Resp --> DoAction{Tool action?}
    DoAction -->|confirm| Exec[Execute (record txn / create sub / group)]
```

## Technical flow
```mermaid
sequenceDiagram
    actor U
    participant UI as Chat UI
    participant Sum as summary.ts
    participant EF as assistant edge fn
    participant LLM
    U->>UI: message
    UI->>Sum: build data snapshot (balances, budgets, splits — aggregated)
    UI->>EF: prompt + snapshot (quota checked/decremented)
    EF->>LLM: persona + tools
    LLM-->>EF: prose + <ui> JSON (+ optional tool call)
    EF-->>UI: response
    UI->>UI: richMessage parse → cards/actions; tool actions are confirm-gated
```

## Data touched
`assistant_threads`, `assistant_messages`, `assistant_memory` (persisted, synced). Reads an aggregated snapshot (never raw PII beyond what's needed). Actions write `transactions` / `subscriptions` / `split_groups` on confirm.

## Key files
`app/assistant/`, `src/assistant/summary.ts` (snapshot), `src/assistant/richMessage.tsx` (parse/render), `supabase/functions` assistant.

## Gating
Quota-based (trial grants prompts; premium/credit packs add more). Enforced server-side.

## Edge cases
- Responses persist the `<ui>` block so reopened threads re-render visuals.
- Malformed `<ui>` degrades gracefully to plain text.
- Chat view is a fixed frame sized to the visual viewport so the composer stays visible when the keyboard opens.
- Actions never execute silently — always confirm-gated ("suggest, don't decide").
