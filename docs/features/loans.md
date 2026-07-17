# Loans (EMI schedule & tracking)

## Overview
A dedicated `/loans` list + `/loans/[id]` detail page for tracking loans: principal, monthly EMI, tenure, interest rate, and a reducing-balance **amortization schedule** (principal vs interest per month via `amortizationSchedule()` in `@pocketcare/finance`). The **monthly EMI is auto-calculated** from principal + rate + tenure (`emiFromPrincipal()`), editable to override. Loans are **fixed** or **variable** rate: fixed loans get the computed EMI + amortization schedule; variable loans (which re-price over time and can't be modelled) instead show a **month-by-month list where the user enters each month's actual EMI**. Each EMI has a **due date** derived from the loan's start date + a configurable **due day of the month**, and can be marked paid either **manually** or **automatically on the due date**.

## Fixed vs variable
```mermaid
flowchart TD
    Add[Add/edit loan] --> Type{Interest type}
    Type -->|Fixed| Calc["EMI = emiFromPrincipal(principal, rate, tenure)\n(editable override)"]
    Calc --> Sched[Amortization schedule: principal vs interest]
    Type -->|Variable| Enter["Month-by-month list\nuser enters each month's EMI (emi_amounts JSON)"]
    Enter --> Track[Paid tracking + total paid so far]
```
`rate_type` = `fixed` | `variable`. Variable EMIs are stored in `emi_amounts` (JSON `{ emiNo: amountMinor }`), edited inline in the schedule (saved on blur). Variable loans show "Varies" for the monthly EMI and a "Paid so far" total instead of an amortization split.

## User flow
```mermaid
flowchart TD
    L([Loans]) --> Add[Add loan: lender, principal, EMI, tenure, rate, start date, EMI due day, auto-mark?]
    L --> Detail[Open a loan]
    Detail --> Sched[Amortization schedule with per-EMI due dates]
    Sched --> Toggle{Auto-mark past-due EMIs?}
    Toggle -->|On| Auto[Past-due EMIs shown paid automatically]
    Toggle -->|Off| Manual[Mark each EMI paid yourself]
    Manual --> Pay[Mark-paid dialog: paid date + optional funding account]
    Pay -->|account chosen| Txn[Posts an EMI expense transaction]
```

## Technical flow
```mermaid
flowchart LR
    Loan["loans row\n(start_date, emi_due_day, auto_mark_paid, emi_payments)"] --> Due["emiDueDate(start, dueDay, n)\n→ per-EMI due date"]
    Loan --> Eff["effectivePaidEmis(manual ∪ auto)\n(auto = past-due when enabled)"]
    Eff --> View["Detail: paid / next / remaining / progress"]
    Eff --> ListView["List: progress bar"]
    Manual["Mark-paid dialog"] --> Map["emi_payments JSON {emiNo: paidOnISO}"]
    Manual -->|optional| Repo["transactions.create (EMI expense)"]
```

## Data touched
`loans` (`principal`, `emi_amount`, `tenure_months`, `interest_rate`, `rate_type`, `start_date`, `emi_due_day`, `auto_mark_paid`, `emi_payments`, `emi_amounts`, `emis_paid`), `transactions` (optional EMI expense on mark-paid).

## Key files
`app/loans/page.tsx` (list + AddLoan), `app/loans/[id]/page.tsx` (detail, fixed schedule + variable EMI list, mark-paid dialog, edit), `@pocketcare/finance` (`emiFromPrincipal`, `amortizationSchedule`, `emiDueDate`, `isDuePassed`, `effectivePaidEmis`). Migrations `0034` (due-day/auto-mark) + `0036` (rate_type/emi_amounts).

## Gating
Free.

## Due-date & auto-mark logic
`emi_due_day` (1–31) is the day of the month each EMI falls on; combined with `start_date` it derives every EMI's due date. The **first** EMI is the first occurrence of the due day on/after the start date; each subsequent EMI is one calendar month later, with the day **clamped** to the month length (a 31 due-day lands on Feb 28/29). If no due day is set, the start date's own day is used.

`auto_mark_paid` (0/1): when on, every EMI whose due date has passed is treated as paid. Auto-marked EMIs are **derived at read time, never written** — so turning the toggle off instantly reverts them. **Manual** marks (in `emi_payments`) always win and persist; they can be undone individually. This keeps the paid count, next-EMI date, remaining count, and progress bar consistent on both the list and detail pages.

## Edge cases
- Legacy loans (created before per-EMI tracking) fall back to the `emis_paid` count → first N EMIs marked.
- Marking an EMI paid can **optionally** post an expense from a funding account (defaults to not recording); only offered when an EMI amount is set.
- Auto-marked rows show an "Auto ✓" chip (non-interactive); to unmark, turn the policy off.
- Loans added from the Planned Cashflow hub redirect to `/loans`; the loan bucket is managed here.
