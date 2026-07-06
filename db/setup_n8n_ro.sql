-- n8n icin salt-okunur rol. Idempotent. Geri alma: rollback_n8n_ro.sql
-- __PASSWORD__ kosum aninda .secrets.env'deki N8N_RO_PASSWORD ile degistirilir.
do $$ begin
  if not exists (select from pg_roles where rolname = 'n8n_ro') then
    create role n8n_ro login password '__PASSWORD__';
  else
    alter role n8n_ro with login password '__PASSWORD__';
  end if;
end $$;
alter role n8n_ro set default_transaction_read_only = on;
grant usage on schema public to n8n_ro;
grant select on items, production_orders, stock_moves to n8n_ro;
-- RLS: mevcut politikalar auth.uid() ister; n8n_ro icin acik SELECT politikasi sart.
drop policy if exists items_n8n_ro_read on items;
create policy items_n8n_ro_read on items for select to n8n_ro using (true);
drop policy if exists production_orders_n8n_ro_read on production_orders;
create policy production_orders_n8n_ro_read on production_orders for select to n8n_ro using (true);
drop policy if exists stock_moves_n8n_ro_read on stock_moves;
create policy stock_moves_n8n_ro_read on stock_moves for select to n8n_ro using (true);
select 'n8n_ro hazir' as durum;
