-- 0040_receipts_and_expense_items.sql
--
-- Receipt / bill scanning + itemized splitting.
--
-- Three new tables:
--   receipt_scans        — PRIVATE per-user record of a scan (no image bytes).
--   expense_items        — the individual lines of a shared bill.
--   expense_item_shares  — who is on the hook for each line.
--
-- Design notes:
--   * The itemized layer is ADDITIVE. Per-item shares are rolled up by the
--     client into `expense_participants`, which stays the single source of
--     truth for balances and settle-up — so nothing downstream changes.
--   * Receipt IMAGES ARE NEVER STORED (see docs/features/receipt-scanning.md).
--     `image_path` exists only as a forward-compatible seam should we later add
--     a private Storage bucket; today the client always writes NULL.
--   * Money is integer minor units. Quantities are integer MILLI-units
--     (1000 = "1") so 0.5 kg is exact without floats.
--
-- Apply: supabase db push  → then redeploy packages/db/sync-streams.yaml in the
-- PowerSync dashboard (otherwise group members will not see each other's items).

-- ---------------------------------------------------------------------------
-- receipt_scans (private to the scanning user)
-- ---------------------------------------------------------------------------
create table if not exists pocketcare.receipt_scans (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references pocketcare.profiles(id) on delete cascade,
  source         text not null default 'upload',   -- camera | upload
  engine         text not null default 'tesseract',-- tesseract | claude | pdf_text | manual
  merchant       text,
  occurred_at    timestamptz,
  currency       text not null,
  subtotal       int,
  tax            int,
  service_charge int,
  tip            int,
  discount       int,
  total          int,
  confidence     int  not null default 0,          -- 0..100
  raw_text       text,                             -- OCR text, for re-parse/debug
  parsed_json    text,                             -- the full ReceiptDraft
  transaction_id uuid,                             -- set once recorded
  expense_id     uuid,                             -- set once split
  image_path     text,                             -- always NULL today (see above)
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  constraint receipt_scans_confidence_range check (confidence between 0 and 100)
);

create index if not exists receipt_scans_user_idx on pocketcare.receipt_scans(user_id, created_at desc);
create index if not exists receipt_scans_txn_idx  on pocketcare.receipt_scans(transaction_id);

alter table pocketcare.receipt_scans enable row level security;
create policy receipt_scans_owner on pocketcare.receipt_scans for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
grant all on table pocketcare.receipt_scans to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- expense_items — the lines of a shared bill
-- ---------------------------------------------------------------------------
create table if not exists pocketcare.expense_items (
  id          uuid primary key default gen_random_uuid(),
  expense_id  uuid not null references pocketcare.expenses(id) on delete cascade,
  group_id    uuid not null references pocketcare.split_groups(id) on delete cascade, -- denormalized for RLS
  kind        text not null default 'item',   -- item | tax | service_charge | tip | discount
  description text,
  quantity    int,                            -- MILLI-units (1000 = 1). NULL when unprinted.
  unit        text,                           -- free text as printed: kg, pcs, L
  unit_price  int,                            -- minor units per single unit
  amount      int  not null,                  -- minor units; line total (negative for discount)
  split_mode  text not null default 'equal',  -- equal | quantity | percent | exact | proportional
  sort        int  not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  constraint expense_items_kind_valid
    check (kind in ('item', 'tax', 'service_charge', 'tip', 'discount')),
  constraint expense_items_mode_valid
    check (split_mode in ('equal', 'quantity', 'percent', 'exact', 'proportional')),
  -- Only charge lines may be proportional; an item has no subtotal to lean on.
  constraint expense_items_proportional_is_charge
    check (split_mode <> 'proportional' or kind <> 'item')
);

create index if not exists expense_items_expense_idx on pocketcare.expense_items(expense_id, sort);
create index if not exists expense_items_group_idx   on pocketcare.expense_items(group_id);

alter table pocketcare.expense_items enable row level security;
create policy ei_all on pocketcare.expense_items for all
  using (is_group_member(group_id, auth.uid()))
  with check (is_group_member(group_id, auth.uid()));
grant all on table pocketcare.expense_items to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- expense_item_shares — who owes what on each line
-- ---------------------------------------------------------------------------
create table if not exists pocketcare.expense_item_shares (
  id           uuid primary key default gen_random_uuid(),
  item_id      uuid not null references pocketcare.expense_items(id) on delete cascade,
  expense_id   uuid not null references pocketcare.expenses(id) on delete cascade,     -- denormalized
  group_id     uuid not null references pocketcare.split_groups(id) on delete cascade, -- denormalized for RLS
  -- NOTE: unlike expense_participants (0011), this FK cascades. Without it,
  -- `delete from auth.users` fails for anyone who ever appeared on a line item,
  -- which is exactly the class of bug 0031 had to retrofit a cleanup for.
  user_id      uuid not null references auth.users(id) on delete cascade,
  -- Mode-dependent input: milli-quantity, percent x100, or exact minor units.
  -- Ignored for equal/proportional (those derive their own weights).
  weight       int  not null default 0,
  -- Resolved minor units. Σ per item == expense_items.amount.
  share_amount int  not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  unique (item_id, user_id)
);

create index if not exists eis_item_idx    on pocketcare.expense_item_shares(item_id);
create index if not exists eis_expense_idx on pocketcare.expense_item_shares(expense_id);
create index if not exists eis_group_idx   on pocketcare.expense_item_shares(group_id);
create index if not exists eis_user_idx    on pocketcare.expense_item_shares(user_id);

alter table pocketcare.expense_item_shares enable row level security;
create policy eis_all on pocketcare.expense_item_shares for all
  using (is_group_member(group_id, auth.uid()))
  with check (is_group_member(group_id, auth.uid()));
grant all on table pocketcare.expense_item_shares to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- expenses.has_items — cheap flag so readers know to fetch the breakdown
-- ---------------------------------------------------------------------------
alter table pocketcare.expenses
  add column if not exists has_items boolean not null default false;

-- ---------------------------------------------------------------------------
-- Integrity: the lines must add up to the expense total.
--
-- Enforced as a DEFERRED constraint trigger so the client can insert the
-- expense and its items in any order within one transaction and only be judged
-- at commit. A drifting sum here would silently corrupt every balance derived
-- from the expense, so this is worth the trigger.
-- ---------------------------------------------------------------------------
create or replace function pocketcare.check_expense_items_sum()
returns trigger language plpgsql security definer
set search_path = pocketcare, public as $$
declare
  v_expense uuid;
  v_total   int;
  v_sum     int;
  v_has     boolean;
begin
  v_expense := coalesce(new.expense_id, old.expense_id);

  select amount, has_items into v_total, v_has
    from pocketcare.expenses where id = v_expense and deleted_at is null;

  -- Expense gone (cascade delete) or not itemized: nothing to enforce.
  if v_total is null or v_has is not true then
    return null;
  end if;

  select coalesce(sum(amount), 0) into v_sum
    from pocketcare.expense_items
   where expense_id = v_expense and deleted_at is null;

  if v_sum <> v_total then
    raise exception
      'expense_items for % sum to % but the expense total is %', v_expense, v_sum, v_total
      using errcode = 'check_violation';
  end if;

  return null;
end;
$$;

create constraint trigger expense_items_sum_check
  after insert or update or delete on pocketcare.expense_items
  deferrable initially deferred
  for each row execute function pocketcare.check_expense_items_sum();

revoke all on function pocketcare.check_expense_items_sum() from public;
grant execute on function pocketcare.check_expense_items_sum() to authenticated, anon, service_role;
