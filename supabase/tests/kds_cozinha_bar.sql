-- Urbana Café: KDS, production routing and print-flow safety.
-- All fixtures are rolled back with the transaction.

begin;

do $test$
declare
  v_user uuid;
  v_business uuid;
  v_customer uuid;
  v_table uuid;
  v_product_k uuid;
  v_product_b uuid;
  v_product_n uuid;
  v_session uuid;
  v_order public.sales%rowtype;
  v_immediate public.sales%rowtype;
  v_ticket public.production_tickets%rowtype;
  v_ticket_k public.production_tickets%rowtype;
  v_ticket_b public.production_tickets%rowtype;
  v_count integer;
  v_stock numeric;
  v_update_blocked boolean := false;
  v_direct_insert_blocked boolean := false;
  v_direct_update_blocked boolean := false;
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
  values('TEST KDS','TEST KDS')
  returning id into v_business;

  insert into public.business_memberships(business_id,user_id,role,active)
  values(v_business,v_user,'owner',true);

  insert into public.customers(business_id,name,active)
  values(v_business,'TEST KDS Customer',true)
  returning id into v_customer;

  insert into public.cafe_tables(business_id,name,seats,active)
  values(v_business,'TEST KDS Table',4,true)
  returning id into v_table;

  insert into public.products(
    business_id,name,unit,sale_price,average_cost,stock_quantity,min_stock,
    is_stock_item,is_sellable,active,production_station
  )
  values(v_business,'TEST KDS Kitchen','UN',10,2,10,1,true,true,true,'kitchen')
  returning id into v_product_k;

  insert into public.products(
    business_id,name,unit,sale_price,average_cost,stock_quantity,min_stock,
    is_stock_item,is_sellable,active,production_station
  )
  values(v_business,'TEST KDS Bar','UN',5,3,10,1,true,true,true,'bar')
  returning id into v_product_b;

  insert into public.products(
    business_id,name,unit,sale_price,average_cost,stock_quantity,min_stock,
    is_stock_item,is_sellable,active,production_station
  )
  values(v_business,'TEST KDS None','UN',2,1,10,1,true,true,true,'none')
  returning id into v_product_n;

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
    v_table,
    'Teste KDS cozinha + bar',
    jsonb_build_array(
      jsonb_build_object('product_id',v_product_k,'quantity',2),
      jsonb_build_object('product_id',v_product_b,'quantity',1),
      jsonb_build_object('product_id',v_product_n,'quantity',1)
    ),
    0
  );

  select count(*)
    into v_count
  from public.production_tickets
  where sale_id=v_order.id
    and status='pending';

  if v_count<>2 then
    raise exception 'TEST FAILED: expected two pending station tickets, got %',v_count;
  end if;

  select id into v_ticket_k
  from public.production_tickets
  where sale_id=v_order.id and station='kitchen';

  select id into v_ticket_b
  from public.production_tickets
  where sale_id=v_order.id and station='bar';

  if v_ticket_k is null or v_ticket_b is null then
    raise exception 'TEST FAILED: kitchen/bar ticket routing missing';
  end if;

  begin
    insert into public.production_tickets(
      business_id,sale_id,station,status
    )
    values(v_business,v_order.id,'kitchen','pending');
  exception when others then
    v_direct_insert_blocked:=true;
  end;

  if not v_direct_insert_blocked then
    raise exception 'TEST FAILED: direct production ticket insert was accepted';
  end if;

  select *
    into v_order
  from public.update_open_order(
    v_order.id,
    v_customer,
    v_table,
    'Teste KDS edição antes da produção',
    jsonb_build_array(
      jsonb_build_object('product_id',v_product_k,'quantity',2),
      jsonb_build_object('product_id',v_product_n,'quantity',2)
    ),
    0
  );

  select status into v_ticket_b
  from public.production_tickets
  where id=v_ticket_b.id;

  if v_ticket_b.status<>'cancelled' then
    raise exception 'TEST FAILED: removed bar station was not cancelled: %',v_ticket_b.status;
  end if;

  select count(*)
    into v_count
  from public.production_tickets
  where sale_id=v_order.id
    and station='kitchen'
    and status='pending';

  if v_count<>1 then
    raise exception 'TEST FAILED: kitchen ticket did not remain pending';
  end if;

  select *
    into v_ticket_k
  from public.update_production_ticket_status(v_ticket_k.id,'preparing');

  if v_ticket_k.status<>'preparing' or v_ticket_k.started_at is null then
    raise exception 'TEST FAILED: preparing transition invalid';
  end if;

  select *
    into v_ticket_k
  from public.update_production_ticket_status(v_ticket_k.id,'ready');

  if v_ticket_k.status<>'ready' or v_ticket_k.ready_at is null then
    raise exception 'TEST FAILED: ready transition invalid';
  end if;

  select *
    into v_ticket_k
  from public.update_production_ticket_status(v_ticket_k.id,'served');

  if v_ticket_k.status<>'served' or v_ticket_k.served_at is null then
    raise exception 'TEST FAILED: served transition invalid';
  end if;

  begin
    perform public.update_open_order(
      v_order.id,
      v_customer,
      v_table,
      'Tentativa depois do inicio da produção',
      jsonb_build_array(
        jsonb_build_object('product_id',v_product_k,'quantity',1)
      ),
      0
    );
  exception when others then
    v_update_blocked:=true;
  end;

  if not v_update_blocked then
    raise exception 'TEST FAILED: open order was editable after production started';
  end if;

  begin
    update public.production_tickets
    set status='pending'
    where id=v_ticket_k.id;
  exception when others then
    v_direct_update_blocked:=true;
  end;

  if not v_direct_update_blocked then
    raise exception 'TEST FAILED: direct production ticket update was accepted';
  end if;

  select *
    into v_order
  from public.close_open_order(v_order.id,v_session,'cash');

  if v_order.status<>'completed' then
    raise exception 'TEST FAILED: KDS order checkout failed';
  end if;

  select stock_quantity into v_stock
  from public.products
  where id=v_product_k;

  if v_stock<>8 then
    raise exception 'TEST FAILED: kitchen stock expected 8, got %',v_stock;
  end if;

  select *
    into v_immediate
  from public.create_sale_transaction(
    v_business,
    v_session,
    v_customer,
    null,
    'Venda imediata KDS',
    'cash',
    jsonb_build_array(
      jsonb_build_object('product_id',v_product_b,'quantity',1)
    ),
    0
  );

  if v_immediate.status<>'completed' or round(v_immediate.total,2)<>5 then
    raise exception 'TEST FAILED: immediate sale invalid';
  end if;

  select *
    into v_ticket
  from public.production_tickets
  where sale_id=v_immediate.id
    and station='bar';

  if v_ticket.id is null or v_ticket.status<>'pending' then
    raise exception 'TEST FAILED: immediate sale did not create pending bar ticket';
  end if;

  select count(*)
    into v_count
  from public.production_tickets
  where sale_id=v_immediate.id
    and station='bar';

  if v_count<>1 then
    raise exception 'TEST FAILED: expected one bar ticket for immediate sale, got %',v_count;
  end if;
end;
$test$;

rollback;

select 'Urbana Café KDS test: PASS' as result;
