-- 0025_admin_console.sql

CREATE SCHEMA IF NOT EXISTS pocketcare_admin;

-- Table to store authorized admin users
CREATE TABLE IF NOT EXISTS pocketcare_admin.admins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE pocketcare_admin.admins ENABLE ROW LEVEL SECURITY;

-- Grant usage to authenticated users if needed for self-check (optional, but standard for custom schemas)
GRANT USAGE ON SCHEMA pocketcare_admin TO authenticated;
GRANT USAGE ON SCHEMA pocketcare_admin TO service_role;

-- Allow authenticated users to read their own admin status
CREATE POLICY "Admins can read their own row" ON pocketcare_admin.admins
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

GRANT SELECT ON pocketcare_admin.admins TO authenticated;
GRANT ALL ON pocketcare_admin.admins TO service_role;
