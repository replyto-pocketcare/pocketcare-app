-- PocketCare — expense splitting (Phase 2): settlements.
-- Records a payment that clears a balance with a contact. account_id null = the
-- balance was settled outside the app ("None"). offset_transaction_id links the
-- real ledger posting (transfer) when an account was used.
set search_path to pocketcare, public;

create table if not exists settlements (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null references auth.users(id) on delete cascade,
  contact_id            uuid not null,
  group_id              uuid,
  amount                int  not null,             -- minor units, positive
  direction             text not null,             -- 'received' (they paid you) | 'paid' (you paid them)
  account_id            uuid,                       -- null = "None" (no ledger movement)
  offset_transaction_id uuid,
  note                  text,
  settled_at            timestamptz not null default now(),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  deleted_at            timestamptz
);

create index if not exists settlements_contact_idx on settlements(contact_id);
create index if not exists settlements_user_idx on settlements(user_id);

alter table settlements enable row level security;
create policy settlements_owner on settlements using (user_id = auth.uid()) with check (user_id = auth.uid());
grant all on table settlements to anon, authenticated, service_role;
