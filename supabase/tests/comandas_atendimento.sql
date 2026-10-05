-- Urbana Café: command lifecycle, table occupancy and checkout safety.
-- All fixtures are rolled back with the transaction.

begin;

do $test$
declare
  v_user uuid;
  v_business uuid;
  v_customer uuid;
  v_table_a uuid;
  v_table_b uuid;
  v_product_a uuid;
  v_product_b uuid;
  v_session uuid;
  v_order public.sales%rowtype;
  v_cancelled public.sales%rowtype;
  v_closed public.sales%rowtype;
  v_status text;
  v_stock_a numeric;
  v_stock_b numeric;
  v_cash numeric;
  v_paid numeric;
  v_cogs numeric;
  v_open_count integer;
  v_audit_open integer;
  v_audit_update integer;
  v_audit_cancel integer;
  v_duplicate_failed boolean := false;
  v_direct_item_failed boolean := false;
  v_direct_payment_failed boolean := false;
  v_insufficient_failed boolean := false;
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
  values('TEST Comandas','TEST Comandas')
  returning id into v_business;

  insert into public.business_memberships(business_id,user_id,role,active)
  values(v_business,v_user,'owner',true);

  insert into public.customers(business_id,name,active)
  values(v_business,'TEST Comanda Customer',true)
  returning id into v_customer;

  insert into public.cafe_tables(business_id,name,seats,active)
  values(v_business,'TEST Mesa A',2,true)
  returning id into v_table_a;

  insert into public.cafe_tables(business_id,name,seats,active)
  values(v_business,'TEST Mesa B',4,true)
  returning id into v_table_b;

  insert into public.products(
    business_id,name,unit,sale_price,average_cost,stock_quantity,min_stock,
    is_stock_item,is_sellable,active
  )
  values(v_business,'TEST Comanda Product A','UN',10,2,10,2,true,true,true)
  returning id into v_product_a;

  insert into public.products(
    business_id,name,unit,sale_price,average_cost,stock_quantity,min_stock,
    is_stock_item,is_sellable,active
  )
  values(v_business,'TEST Comanda Product B','UN',5,3,3,1,true,true,true)
  returning id into v_product_b;

  set local role authenticated;
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub',v_user::text,'role','authenticated')::text,
    true
  );

  select id
    into v_session
  from public.open_cash_session(v_business,100);

  if v_session is null then
    raise exception 'TEST FAILED: cash session could not be opened';
  end if;

  select *
    into v_order
  from public.create_open_order(
    v_business,
    v_customer,
    v_table_a,
    'Teste abertura de comanda',
    jsonb_build_array(
      jsonb_build_object('product_id',v_product_a,'quantity',2)
    ),
    0
  );

  if v_order.status<>'open' or round(v_order.total,2)<>20 then
    raise exception 'TEST FAILED: open order invalid: % / %',v_order.status,v_order.total;
  end if;

  select stock_quantity
    into v_stock_a
  from public.products
  where id=v_product_a;

  if v_stock_a<>10 then
    raise exception 'TEST FAILED: opening an order changed stock: %',v_stock_a;
  end if;

  begin
    perform public.create_open_order(
      v_business,
      v_customer,
      v_table_a,
      'Duplicata',
      jsonb_build_array(jsonb_build_object('product_id',v_product_a,'quantity',1)),
      0
    );
  exception when others then
    v_duplicate_failed:=true;
  end;

  if not v_duplicate_failed then
    raise exception 'TEST FAILED: duplicate open order on the same table was accepted';
  end if;

  select *
    into v_order
  from public.update_open_order(
    v_order.id,
    v_customer,
    v_table_b,
    'Teste edição de comanda',
    jsonb_build_array(
      jsonb_build_object('product_id',v_product_a,'quantity',3),
      jsonb_build_object('product_id',v_product_b,'quantity',1)
    ),
    0
  );

  if v_order.status<>'open' or round(v_order.total,2)<>35 or v_order.table_id<>v_table_b then
    raise exception 'TEST FAILED: open order update invalid';
  end if;

  select stock_quantity into v_stock_a from public.products where id=v_product_a;
  select stock_quantity into v_stock_b from public.products where id=v_product_b;

  if v_stock_a<>10 or v_stock_b<>3 then
    raise exception 'TEST FAILED: editing an order changed stock: % / %',v_stock_a,v_stock_b;
  end if;

  begin
    insert into public.sale_items(sale_id,product_id,quantity,unit_price,unit_cost)
    values(v_order.id,v_product_a,1,10,2);
  exception when others then
    v_direct_item_failed:=true;
  end;

  if not v_direct_item_failed then
    raise exception 'TEST FAILED: direct client sale_items insert was accepted';
  end if;

  select count(*)
    into v_open_count
  from public.sales
  where business_id=v_business
    and status='open';

  if v_open_count<>1 then
    raise exception 'TEST FAILED: expected exactly one open order, got %',v_open_count;
  end if;

  select *
    into v_cancelled
  from public.cancel_open_order(
    v_order.id,
    'Cliente desistiu no teste'
  );

  if v_cancelled.status<>'cancelled' then
    raise exception 'TEST FAILED: cancellation status invalid: %',v_cancelled.status;
  end if;

  select count(*)
    into v_open_count
  from public.sales
  where business_id=v_business
    and status='open';

  if v_open_count<>0 then
    raise exception 'TEST FAILED: cancelled order still occupies the table';
  end if;

  select *
    into v_order
  from public.create_open_order(
    v_business,
    v_customer,
    v_table_a,
    'Teste segunda abertura',
    jsonb_build_array(
      jsonb_build_object('product_id',v_product_a,'quantity',2),
      jsonb_build_object('product_id',v_product_b,'quantity',1)
    ),
    0
  );

  if v_order.status<>'open' or round(v_order.total,2)<>25 then
    raise exception 'TEST FAILED: second open order invalid';
  end if;

  begin
    insert into public.sale_payments(sale_id,method,amount)
    values(v_order.id,'cash',25);
  exception when others then
    v_direct_payment_failed:=true;
  end;

  if not v_direct_payment_failed then
    raise exception 'TEST FAILED: direct client sale_payments insert was accepted';
  end if;

  select *
    into v_closed
  from public.close_open_order(v_order.id,v_session,'cash');

  if v_closed.status<>'completed' or round(v_closed.total,2)<>25 then
    raise exception 'TEST FAILED: order checkout invalid: % / %',v_closed.status,v_closed.total;
  end if;

  select stock_quantity into v_stock_a from public.products where id=v_product_a;
  select stock_quantity into v_stock_b from public.products where id=v_product_b;

  if v_stock_a<>8 or v_stock_b<>2 then
    raise exception 'TEST FAILED: checkout stock expected 8 / 2, got % / %',v_stock_a,v_stock_b;
  end if;

  select round(coalesce(sum(amount),0),2)
    into v_cash
  from public.cash_movements
  where cash_session_id=v_session;

  if v_cash<>125 then
    raise exception 'TEST FAILED: cash ledger expected 125, got %',v_cash;
  end if;

  select round(coalesce(sum(amount),0),2)
    into v_paid
  from public.sale_payments
  where sale_id=v_closed.id;

  if v_paid<>25 then
    raise exception 'TEST FAILED: payment ledger expected 25, got %',v_paid;
  end if;

  select round(cogs,2)
    into v_cogs
  from public.sales
  where id=v_closed.id;

  if v_cogs<>7 then
    raise exception 'TEST FAILED: COGS expected 7, got %',v_cogs;
  end if;

  select count(*)
    into v_audit_open
  from public.audit_logs
  where business_id=v_business
    and action='order_opened';

  select count(*)
    into v_audit_update
  from public.audit_logs
  where business_id=v_business
    and action='order_updated';

  select count(*)
    into v_audit_cancel
  from public.audit_logs
  where business_id=v_business
    and action='order_cancelled';

  if v_audit_open<>3 or v_audit_update<>1 or v_audit_cancel<>2 then
    raise exception 'TEST FAILED: audit counts expected 3 / 1 / 1, got % / % / %',
      v_audit_open,v_audit_update,v_audit_cancel;
  end if;

  select *
    into v_order
  from public.create_open_order(
    v_business,
    v_customer,
    v_table_a,
    'Teste de estoque insuficiente',
    jsonb_build_array(
      jsonb_build_object('product_id',v_product_a,'quantity',20)
    ),
    0
  );

  begin
    perform public.close_open_order(v_order.id,v_session,'cash');
  exception when others then
    v_insufficient_failed:=true;
  end;

  if not v_insufficient_failed then
    raise exception 'TEST FAILED: checkout accepted insufficient stock';
  end if;

  select status into v_status from public.sales where id=v_order.id;
  if v_status<>'open' then
    raise exception 'TEST FAILED: failed checkout changed order status to %',v_status;
  end if;

  select stock_quantity into v_stock_a from public.products where id=v_product_a;
  if v_stock_a<>8 then
    raise exception 'TEST FAILED: failed checkout changed stock to %',v_stock_a;
  end if;

  select count(*)
    into v_open_count
  from public.sales
  where business_id=v_business
    and status='open';

  if v_open_count<>1 then
    raise exception 'TEST FAILED: expected one open order after failed checkout, got %',v_open_count;
  end if;

  select *
    into v_cancelled
  from public.cancel_open_order(v_order.id,'Limpeza do teste');

  if v_cancelled.status<>'cancelled' then
    raise exception 'TEST FAILED: cleanup cancellation failed';
  end if;
end;
$test$;

rollback;

select 'Urbana Café comandas e atendimento test: PASS' as result;
