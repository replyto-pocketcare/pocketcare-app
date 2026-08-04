-- Create a redacted view of profiles for sharing names/emails in split groups
-- without leaking private fields like gender, country, or base_currency.

CREATE OR REPLACE VIEW pocketcare.public_profiles AS
SELECT id, display_name, email, created_at, updated_at
FROM pocketcare.profiles;

-- Grant permissions to PostgREST roles (and by extension PowerSync)
GRANT SELECT ON pocketcare.public_profiles TO anon, authenticated, service_role;

-- The underlying pocketcare.profiles table is already in the powersync publication,
-- so PowerSync will automatically detect changes and stream this view.
