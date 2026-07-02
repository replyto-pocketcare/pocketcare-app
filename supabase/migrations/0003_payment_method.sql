-- PocketCare — record how a transaction was paid (UPI, Debit Card, Net Banking,
-- Cash, Credit Card). Idempotent so it's safe on fresh or existing databases.

alter table transactions add column if not exists payment_method text;
