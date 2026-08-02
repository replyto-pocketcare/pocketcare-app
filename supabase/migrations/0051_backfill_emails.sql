-- 0051_backfill_emails.sql
-- Backfill the email column in pocketcare.profiles from auth.users

set search_path = pocketcare, public;

update pocketcare.profiles p
set email = u.email
from auth.users u
where p.id = u.id and p.email is null;
