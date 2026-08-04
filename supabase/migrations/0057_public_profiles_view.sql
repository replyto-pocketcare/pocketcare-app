-- Create a redacted view of profiles for sharing names/emails in split groups
-- without leaking private fields like gender, country, or base_currency.

CREATE OR REPLACE VIEW pocketcare.public_profiles AS
SELECT id, display_name, email, created_at, updated_at
FROM pocketcare.profiles;

-- Grant permissions to PostgREST roles (and by extension PowerSync)
GRANT SELECT ON pocketcare.public_profiles TO anon, authenticated, service_role;

-- Add the view to the powersync publication so it can be streamed
ALTER PUBLICATION powersync ADD TABLE pocketcare.public_profiles;
