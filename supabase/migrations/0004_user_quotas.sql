-- Add quota and premium tracking to entitlements table
set search_path to pocketcare, public;

alter table entitlements
  add column monthly_quota_total int,
  add column monthly_quota_used int not null default 0,
  add column purchased_quota_remaining int,
  add column quota_reset_date timestamptz,
  add column additional_purchased_quota int,
  add column premium_trial_start_date timestamptz;
