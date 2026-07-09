-- PocketCare — record which exchange a holding trades on (from the instruments picker).
set search_path to pocketcare, public;

alter table pocketcare.holdings add column if not exists exchange text;
