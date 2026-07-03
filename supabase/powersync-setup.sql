-- PocketCare — PowerSync + Supabase setup for the dedicated `pocketcare` schema.
-- Run in the Supabase SQL editor AFTER applying migrations/0001_init.sql.
-- These three things must all be true or cross-device sync fails silently:
--   (1) PowerSync's publication includes the pocketcare tables  (download/replication)
--   (2) the replication role can read the schema                (download/replication)
--   (3) `pocketcare` is an Exposed schema in the Data API        (upload via PostgREST)

-- ============================================================
-- 1) PUBLICATION — what PowerSync replicates to your clients
-- ============================================================
-- Check what you currently have:
--   select pubname, puballtables from pg_publication;
--   select * from pg_publication_tables where pubname = 'powersync';
--
-- CASE A — a "powersync" publication already exists FOR ALL TABLES
--   (puballtables = true): it already covers pocketcare. Nothing to do here.
--
-- CASE B — it exists but only lists public tables → add the whole schema
--   (Postgres 15+, which Supabase uses):
--     alter publication powersync add tables in schema pocketcare;
--
-- CASE C — no publication yet → create one covering the schema:
--     create publication powersync for tables in schema pocketcare;
--
-- (Simplest catch-all, if you don't mind replicating everything:)
--     drop publication if exists powersync;
--     create publication powersync for all tables;

-- ============================================================
-- 2) REPLICATION ROLE — let PowerSync's DB user read the schema
-- ============================================================
-- If you followed PowerSync's Supabase guide you created a role for it
-- (often "powersync_role"). Grant it access to the new schema. Skip if your
-- PowerSync connection uses the built-in postgres/superuser role.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'powersync_role') then
    execute 'grant usage on schema pocketcare to powersync_role';
    execute 'grant select on all tables in schema pocketcare to powersync_role';
    execute 'alter default privileges in schema pocketcare grant select on tables to powersync_role';
  end if;
end $$;

-- ============================================================
-- 3) EXPOSED SCHEMA — required for the app's writes (PostgREST)
-- ============================================================
-- Do this in the Dashboard: Project Settings → API → "Exposed schemas" →
-- add `pocketcare` (keep public, graphql_public). Or from SQL:
--   alter role authenticator set pgrst.db_schemas = 'public, graphql_public, pocketcare';
--   notify pgrst, 'reload config';
