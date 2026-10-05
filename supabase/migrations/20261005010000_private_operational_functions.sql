-- Urbana Café: isolate privileged operational functions from the exposed public schema.
-- Public RPC names are preserved as SECURITY INVOKER wrappers.
-- The privileged implementation remains in private and keeps its transaction semantics.

create schema if not exists private;

alter function public.close_cash_session(uuid,numeric,text) set schema private;
alter function public.create_purchase_transaction(uuid,uuid,text,public.payment_method,jsonb) set schema private;
alter function public.create_reservation_transaction(uuid,uuid,uuid,timestamptz,integer,text) set schema private;
alter function public.create_sale_transaction(uuid,uuid,uuid,uuid,text,public.payment_method,jsonb,numeric) set schema private;
alter function public.finalize_sale(uuid,uuid) set schema private;
alter function public.open_cash_session(uuid,numeric) set schema private;
alter function public.post_purchase(uuid) set schema private;
alter function public.record_cash_movement(uuid,uuid,public.cash_movement_type,numeric,text) set schema private;
alter function public.record_expense(uuid,text,text,numeric,date,public.payment_method) set schema private;
alter function public.refund_sale_transaction(uuid,text) set schema private;
alter function public.setup_business(text,text,text) set schema private;
alter function public.update_reservation_status(uuid,text) set schema private;

-- Empty search_path prevents accidental object shadowing inside privileged code.
alter function private.close_cash_session(uuid,numeric,text) set search_path='';
alter function private.create_purchase_transaction(uuid,uuid,text,public.payment_method,jsonb) set search_path='';
alter function private.create_reservation_transaction(uuid,uuid,uuid,timestamptz,integer,text) set search_path='';
alter function private.create_sale_transaction(uuid,uuid,uuid,uuid,text,public.payment_method,jsonb,numeric) set search_path='';
alter function private.finalize_sale(uuid,uuid) set search_path='';
alter function private.open_cash_session(uuid,numeric) set search_path='';
alter function private.post_purchase(uuid) set search_path='';
alter function private.record_cash_movement(uuid,uuid,public.cash_movement_type,numeric,text) set search_path='';
alter function private.record_expense(uuid,text,text,numeric,date,public.payment_method) set search_path='';
alter function private.refund_sale_transaction(uuid,text) set search_path='';
alter function private.setup_business(text,text,text) set search_path='';
alter function private.update_reservation_status(uuid,text) set search_path='';

revoke all on schema private from public;
revoke all on schema private from anon;
grant usage on schema private to authenticated;

revoke all on function private.close_cash_session(uuid,numeric,text) from public;
revoke all on function private.close_cash_session(uuid,numeric,text) from anon;
grant execute on function private.close_cash_session(uuid,numeric,text) to authenticated;

revoke all on function private.create_purchase_transaction(uuid,uuid,text,public.payment_method,jsonb) from public;
revoke all on function private.create_purchase_transaction(uuid,uuid,text,public.payment_method,jsonb) from anon;
grant execute on function private.create_purchase_transaction(uuid,uuid,text,public.payment_method,jsonb) to authenticated;

revoke all on function private.create_reservation_transaction(uuid,uuid,uuid,timestamptz,integer,text) from public;
revoke all on function private.create_reservation_transaction(uuid,uuid,uuid,timestamptz,integer,text) from anon;
grant execute on function private.create_reservation_transaction(uuid,uuid,uuid,timestamptz,integer,text) to authenticated;

revoke all on function private.create_sale_transaction(uuid,uuid,uuid,uuid,text,public.payment_method,jsonb,numeric) from public;
revoke all on function private.create_sale_transaction(uuid,uuid,uuid,uuid,text,public.payment_method,jsonb,numeric) from anon;
grant execute on function private.create_sale_transaction(uuid,uuid,uuid,uuid,text,public.payment_method,jsonb,numeric) to authenticated;

revoke all on function private.finalize_sale(uuid,uuid) from public;
revoke all on function private.finalize_sale(uuid,uuid) from anon;
grant execute on function private.finalize_sale(uuid,uuid) to authenticated;

revoke all on function private.open_cash_session(uuid,numeric) from public;
revoke all on function private.open_cash_session(uuid,numeric) from anon;
grant execute on function private.open_cash_session(uuid,numeric) to authenticated;

revoke all on function private.post_purchase(uuid) from public;
revoke all on function private.post_purchase(uuid) from anon;
grant execute on function private.post_purchase(uuid) to authenticated;

revoke all on function private.record_cash_movement(uuid,uuid,public.cash_movement_type,numeric,text) from public;
revoke all on function private.record_cash_movement(uuid,uuid,public.cash_movement_type,numeric,text) from anon;
grant execute on function private.record_cash_movement(uuid,uuid,public.cash_movement_type,numeric,text) to authenticated;

revoke all on function private.record_expense(uuid,text,text,numeric,date,public.payment_method) from public;
revoke all on function private.record_expense(uuid,text,text,numeric,date,public.payment_method) from anon;
grant execute on function private.record_expense(uuid,text,text,numeric,date,public.payment_method) to authenticated;

revoke all on function private.refund_sale_transaction(uuid,text) from public;
revoke all on function private.refund_sale_transaction(uuid,text) from anon;
grant execute on function private.refund_sale_transaction(uuid,text) to authenticated;

revoke all on function private.setup_business(text,text,text) from public;
revoke all on function private.setup_business(text,text,text) from anon;
grant execute on function private.setup_business(text,text,text) to authenticated;

revoke all on function private.update_reservation_status(uuid,text) from public;
revoke all on function private.update_reservation_status(uuid,text) from anon;
grant execute on function private.update_reservation_status(uuid,text) to authenticated;

create or replace function public.close_cash_session(
  p_session_id uuid,
  p_counted_amount numeric,
  p_note text default null
)
returns public.cash_sessions
language sql
security invoker
set search_path=public
as $$
  select private.close_cash_session(p_session_id,p_counted_amount,p_note);
$$;

create or replace function public.create_purchase_transaction(
  p_business_id uuid,
  p_supplier_id uuid default null,
  p_invoice_number text default null,
  p_payment_method public.payment_method default 'cash',
  p_items jsonb default '[]'::jsonb
)
returns public.purchases
language sql
security invoker
set search_path=public
as $$
  select private.create_purchase_transaction(
    p_business_id,p_supplier_id,p_invoice_number,p_payment_method,p_items
  );
$$;

create or replace function public.create_reservation_transaction(
  p_business_id uuid,
  p_customer_id uuid default null,
  p_table_id uuid default null,
  p_reservation_at timestamptz default null,
  p_party_size integer default 2,
  p_notes text default null
)
returns public.reservations
language sql
security invoker
set search_path=public
as $$
  select private.create_reservation_transaction(
    p_business_id,p_customer_id,p_table_id,p_reservation_at,p_party_size,p_notes
  );
$$;

create or replace function public.create_sale_transaction(
  p_business_id uuid,
  p_cash_session_id uuid,
  p_customer_id uuid default null,
  p_table_id uuid default null,
  p_notes text default null,
  p_payment_method public.payment_method default 'cash',
  p_items jsonb default '[]'::jsonb,
  p_discount numeric default 0
)
returns public.sales
language sql
security invoker
set search_path=public
as $$
  select private.create_sale_transaction(
    p_business_id,p_cash_session_id,p_customer_id,p_table_id,
    p_notes,p_payment_method,p_items,p_discount
  );
$$;

create or replace function public.finalize_sale(
  p_sale_id uuid,
  p_cash_session_id uuid
)
returns public.sales
language sql
security invoker
set search_path=public
as $$
  select private.finalize_sale(p_sale_id,p_cash_session_id);
$$;

create or replace function public.open_cash_session(
  p_business_id uuid,
  p_opening_amount numeric
)
returns public.cash_sessions
language sql
security invoker
set search_path=public
as $$
  select private.open_cash_session(p_business_id,p_opening_amount);
$$;

create or replace function public.post_purchase(
  p_purchase_id uuid
)
returns public.purchases
language sql
security invoker
set search_path=public
as $$
  select private.post_purchase(p_purchase_id);
$$;

create or replace function public.record_cash_movement(
  p_business_id uuid,
  p_cash_session_id uuid,
  p_movement_type public.cash_movement_type,
  p_amount numeric,
  p_description text default null
)
returns public.cash_movements
language sql
security invoker
set search_path=public
as $$
  select private.record_cash_movement(
    p_business_id,p_cash_session_id,p_movement_type,p_amount,p_description
  );
$$;

create or replace function public.record_expense(
  p_business_id uuid,
  p_description text,
  p_category text,
  p_amount numeric,
  p_expense_date date,
  p_payment_method public.payment_method
)
returns public.expenses
language sql
security invoker
set search_path=public
as $$
  select private.record_expense(
    p_business_id,p_description,p_category,p_amount,p_expense_date,p_payment_method
  );
$$;

create or replace function public.refund_sale_transaction(
  p_sale_id uuid,
  p_reason text default null
)
returns public.sales
language sql
security invoker
set search_path=public
as $$
  select private.refund_sale_transaction(p_sale_id,p_reason);
$$;

create or replace function public.setup_business(
  p_name text,
  p_legal_name text default null,
  p_full_name text default null
)
returns public.businesses
language sql
security invoker
set search_path=public
as $$
  select private.setup_business(p_name,p_legal_name,p_full_name);
$$;

create or replace function public.update_reservation_status(
  p_reservation_id uuid,
  p_status text
)
returns public.reservations
language sql
security invoker
set search_path=public
as $$
  select private.update_reservation_status(p_reservation_id,p_status);
$$;

revoke all on function public.close_cash_session(uuid,numeric,text) from public;
revoke all on function public.close_cash_session(uuid,numeric,text) from anon;
grant execute on function public.close_cash_session(uuid,numeric,text) to authenticated;

revoke all on function public.create_purchase_transaction(uuid,uuid,text,public.payment_method,jsonb) from public;
revoke all on function public.create_purchase_transaction(uuid,uuid,text,public.payment_method,jsonb) from anon;
grant execute on function public.create_purchase_transaction(uuid,uuid,text,public.payment_method,jsonb) to authenticated;

revoke all on function public.create_reservation_transaction(uuid,uuid,uuid,timestamptz,integer,text) from public;
revoke all on function public.create_reservation_transaction(uuid,uuid,uuid,timestamptz,integer,text) from anon;
grant execute on function public.create_reservation_transaction(uuid,uuid,uuid,timestamptz,integer,text) to authenticated;

revoke all on function public.create_sale_transaction(uuid,uuid,uuid,uuid,text,public.payment_method,jsonb,numeric) from public;
revoke all on function public.create_sale_transaction(uuid,uuid,uuid,uuid,text,public.payment_method,jsonb,numeric) from anon;
grant execute on function public.create_sale_transaction(uuid,uuid,uuid,uuid,text,public.payment_method,jsonb,numeric) to authenticated;

revoke all on function public.finalize_sale(uuid,uuid) from public;
revoke all on function public.finalize_sale(uuid,uuid) from anon;
grant execute on function public.finalize_sale(uuid,uuid) to authenticated;

revoke all on function public.open_cash_session(uuid,numeric) from public;
revoke all on function public.open_cash_session(uuid,numeric) from anon;
grant execute on function public.open_cash_session(uuid,numeric) to authenticated;

revoke all on function public.post_purchase(uuid) from public;
revoke all on function public.post_purchase(uuid) from anon;
grant execute on function public.post_purchase(uuid) to authenticated;

revoke all on function public.record_cash_movement(uuid,uuid,public.cash_movement_type,numeric,text) from public;
revoke all on function public.record_cash_movement(uuid,uuid,public.cash_movement_type,numeric,text) from anon;
grant execute on function public.record_cash_movement(uuid,uuid,public.cash_movement_type,numeric,text) to authenticated;

revoke all on function public.record_expense(uuid,text,text,numeric,date,public.payment_method) from public;
revoke all on function public.record_expense(uuid,text,text,numeric,date,public.payment_method) from anon;
grant execute on function public.record_expense(uuid,text,text,numeric,date,public.payment_method) to authenticated;

revoke all on function public.refund_sale_transaction(uuid,text) from public;
revoke all on function public.refund_sale_transaction(uuid,text) from anon;
grant execute on function public.refund_sale_transaction(uuid,text) to authenticated;

revoke all on function public.setup_business(text,text,text) from public;
revoke all on function public.setup_business(text,text,text) from anon;
grant execute on function public.setup_business(text,text,text) to authenticated;

revoke all on function public.update_reservation_status(uuid,text) from public;
revoke all on function public.update_reservation_status(uuid,text) from anon;
grant execute on function public.update_reservation_status(uuid,text) to authenticated;
