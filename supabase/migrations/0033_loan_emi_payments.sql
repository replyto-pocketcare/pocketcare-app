-- PocketCare — per-EMI paid tracking.
-- `emi_payments` is a JSON map of EMI number → the date it was marked paid, e.g.
-- {"1":"2026-01-05","2":"2026-02-05"}. `emis_paid` stays as a fast count.
set search_path to pocketcare, public;

alter table loans
  add column if not exists emi_payments text;
