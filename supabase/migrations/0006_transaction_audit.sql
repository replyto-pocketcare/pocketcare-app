-- PocketCare — transaction edit audit trail.
-- Editing a transaction updates the row (balances are derived live, so they
-- recompute) AND appends an immutable audit record of what changed, so history
-- is never lost. `changes` is a JSON string of { field: { from, to } }.

create table transaction_audit (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  transaction_id uuid not null,
  action         text not null default 'update',
  changes        text,
  created_at     timestamptz not null default now()
);
create index transaction_audit_txn_idx on transaction_audit(transaction_id, created_at desc);
alter table transaction_audit enable row level security;
create policy transaction_audit_owner on transaction_audit
  using (user_id = auth.uid()) with check (user_id = auth.uid());
