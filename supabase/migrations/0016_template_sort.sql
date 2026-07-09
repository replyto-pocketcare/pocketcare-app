-- PocketCare — manual ordering for transaction templates.
set search_path to pocketcare, public;

alter table pocketcare.transaction_templates add column if not exists sort int not null default 0;
