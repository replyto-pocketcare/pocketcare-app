-- PocketCare — AI assistant persistence (chat history + per-user memory).
-- Incremental migration to run on top of 0001_init.sql. All objects live in the
-- `pocketcare` schema and are user-owned (RLS), synced like the rest of the app.

set search_path to pocketcare, public;

-- ============================ chat threads ============================
create table assistant_threads (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  title      text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index assistant_threads_user_idx on assistant_threads(user_id, updated_at desc) where deleted_at is null;

-- ============================ chat messages ============================
-- Stores the human-readable transcript (role: user | assistant | action).
create table assistant_messages (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  thread_id  uuid not null references assistant_threads(id) on delete cascade,
  role       text not null,
  content    text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index assistant_messages_thread_idx on assistant_messages(thread_id, created_at);

-- ============================ per-user memory ============================
-- Durable facts the assistant learns about the user (short, plain text).
-- `id` is required for PowerSync; `user_id` is unique (one row per user).
create table assistant_memory (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null unique references auth.users(id) on delete cascade,
  notes      text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- updated_at triggers (set_updated_at defined in 0001).
create trigger trg_assistant_threads_updated_at before update on assistant_threads for each row execute function set_updated_at();
create trigger trg_assistant_memory_updated_at  before update on assistant_memory  for each row execute function set_updated_at();

-- RLS: owner-only.
do $$
declare t text;
begin
  foreach t in array array['assistant_threads','assistant_messages','assistant_memory'] loop
    execute format('alter table %I enable row level security;', t);
    execute format($f$create policy %1$s_owner on %1$s using (user_id = auth.uid()) with check (user_id = auth.uid());$f$, t);
  end loop;
end $$;

-- Grants for the API roles (RLS still governs row access).
grant all on table assistant_threads, assistant_messages, assistant_memory to anon, authenticated, service_role;
