-- PocketCare — web feature additions
-- 1) Sub-categories: categories can nest under a parent.
-- 2) Per-account inclusion in net worth.
-- 3) Colors already exist (accounts.color); labels get an optional color via a
--    lightweight labels table so a label can carry a colour across transactions.

alter table categories add column parent_id uuid references categories(id) on delete set null;

alter table accounts add column include_in_net_worth boolean not null default true;

-- Optional colour per label (feature: "labels will have color").
create table labels (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  name       text not null,
  color      text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, name)
);
create index labels_user_idx on labels(user_id);
alter table labels enable row level security;
create policy labels_owner on labels using (user_id = auth.uid()) with check (user_id = auth.uid());
create trigger trg_labels_updated_at before update on labels
  for each row execute function set_updated_at();
