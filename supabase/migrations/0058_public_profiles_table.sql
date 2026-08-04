-- PowerSync does not currently support syncing from Postgres views,
-- so we must use a physical table maintained by a trigger.

-- Drop the view created in 0057
DROP VIEW IF EXISTS pocketcare.public_profiles;

-- Create the physical table
CREATE TABLE pocketcare.public_profiles (
    id UUID PRIMARY KEY REFERENCES pocketcare.profiles(id) ON DELETE CASCADE,
    display_name TEXT,
    email TEXT,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
);

-- RLS: Read-only for authenticated users
ALTER TABLE pocketcare.public_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public profiles are viewable by everyone" ON pocketcare.public_profiles FOR SELECT USING (auth.role() = 'authenticated');

-- Populate existing data
INSERT INTO pocketcare.public_profiles (id, display_name, email, created_at, updated_at)
SELECT id, display_name, email, created_at, updated_at FROM pocketcare.profiles;

-- Create the trigger function
CREATE OR REPLACE FUNCTION pocketcare.sync_public_profile()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO pocketcare.public_profiles (id, display_name, email, created_at, updated_at)
        VALUES (NEW.id, NEW.display_name, NEW.email, NEW.created_at, NEW.updated_at);
    ELSIF TG_OP = 'UPDATE' THEN
        UPDATE pocketcare.public_profiles
        SET display_name = NEW.display_name,
            email = NEW.email,
            updated_at = NEW.updated_at
        WHERE id = NEW.id;
    ELSIF TG_OP = 'DELETE' THEN
        DELETE FROM pocketcare.public_profiles WHERE id = OLD.id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach trigger to the source table
CREATE TRIGGER on_profile_change
AFTER INSERT OR UPDATE OR DELETE ON pocketcare.profiles
FOR EACH ROW EXECUTE FUNCTION pocketcare.sync_public_profile();
