-- Urbana Café: operational RPC compatibility after private-schema isolation.
-- All fixtures are created before switching to the authenticated role and are
-- rolled back with the transaction.

begin;

do $test$
declare
  v_user uuid;
  v_business uuid;
  v_supplier uuid;
  v_customer uuid;
  v_table uuid;
  v_product uuid;
  v_session uuid;
  v_reservation public.reservations%rowtype;
  v_sale public.sales%rowtype;
  v_purchase public.purchases%rowtype;
  v_stock numeric;
  v_cash numeric;
  v_status text;
  v_wrappers integer;
begin
  select user_id
    into v_user
  from public.business_memberships
  where role='owner' and active
  order by created_at
  limit 1;

  if v_user is null then
    raise exception 'TEST FAILED: no active owner fixture';
  end if;

  insert into public.businesses(name,legal_name)
  values('TEST Private RPCs','TEST Private RPCs')
  returning id into v_business;

  insert into public.business_memberships(business_id,user_id,role,active)
  values(v_business,v_user,'owner',true);

  insert into public.suppliers(business_id,name,active)
  values(v_business,'TEST Private RPC Supplier',true)
  returning id into v_supplier;

  insert into public.customers(business_id,name,active)
  values(v_business,'TEST Private RPC Customer',true)
  returning id into v_customer;

  insert into public.cafe_tables(business_id,name,seats,active)
  values(v_business,'TEST Private RPC Table',4,true)
  returning id into v_table;

  insert into public.products(
    business_id,name,unit,sale_price,average_cost,stock_quantity,min_stock,
    is_stock_item,is_sellable,active
  )
  values(v_business,'TEST Private RPC Product','UN',10,2,10,2,true,true,true)
  returning id into v_product;

  set local role authenticated;
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub',v_user::text,'role','authenticated')::text,
    true
  );

  select id into v_session
  from public.open_cash_session(v_business,100);

  if v_session is null then
    raise exception 'TEST FAILED: open_cash_session wrapper failed';
  end if;

  perform public.record_cash_movement(v_business,v_session,'deposit',5,'Teste depósito');
  perform public.record_cash_movement(v_business,v_session,'withdrawal',2,'Teste retirada');

  select status into v_status
  from public.close_cash_session(v_session,95,'Compatibilidade');

  if v_status<>'closed' then
    raise exception 'TEST FAILED: close_cash_session wrapper failed';
  end if;

  select round(coalesce(sum(amount),0),2)
    into v_cash
  from public.cash_movements
  where cash_session_id=v_session;

  if v_cash<>95 then
    raise exception 'TEST FAILED: cash expected 95, got %',v_cash;
  end if;

  select count(*) into v_wrappers
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and not p.prosecdef
    and p.proname=any(array[
      'close_cash_session','create_purchase_transaction','create_reservation_transaction',
      'create_sale_transaction','finalize_sale','open_cash_session','post_purchase',
      'record_cash_movement','record_expense','refund_sale_transaction',
      'setup_business','update_reservation_status'
    ]);

  if v_wrappers<>12 then
    raise exception 'TEST FAILED: expected 12 public invoker wrappers, got %',v_wrappers;
  end if;
end;
$test$;

rollback;

select 'Urbana Café private operational RPC compatibility test: PASS' as result;
