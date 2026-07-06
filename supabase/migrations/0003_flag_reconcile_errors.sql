-- Add a column to flag transactions with mismatched items
alter table transactions add column if not exists sync_error text;

-- Replace the trigger function to flag instead of raise exception
create or replace function check_items_reconcile() returns trigger
language plpgsql set search_path = pocketcare, public as $$
declare txn_id uuid; txn_amount bigint; items_sum bigint;
begin
  txn_id := coalesce(new.transaction_id, old.transaction_id);
  select amount into txn_amount from transactions where id = txn_id;
  if txn_amount is null then return null; end if;
  select coalesce(sum(amount),0) into items_sum from transaction_items where transaction_id = txn_id and deleted_at is null;
  
  if items_sum <> 0 and items_sum <> txn_amount then
    update transactions set sync_error = format('Breakdown items (%s) must sum to transaction amount (%s)', items_sum, txn_amount) where id = txn_id;
  else
    update transactions set sync_error = null where id = txn_id;
  end if;
  return null;
end;
$$;
