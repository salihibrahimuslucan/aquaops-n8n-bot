-- n8n_ro rolunu tamamen kaldirir (geri alma)
drop policy if exists items_n8n_ro_read on items;
drop policy if exists production_orders_n8n_ro_read on production_orders;
drop policy if exists stock_moves_n8n_ro_read on stock_moves;
revoke select on items, production_orders, stock_moves from n8n_ro;
revoke usage on schema public from n8n_ro;
drop role if exists n8n_ro;
select 'n8n_ro kaldirildi' as durum;
