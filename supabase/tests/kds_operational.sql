begin;

do $test$
declare
  v_business uuid;
  v_user uuid;
  v_product uuid;
  v_customer uuid;
  v_sale uuid;
  v_ticket public.production_tickets%rowtype;
  v_metrics jsonb;
begin
  select user_id,business_id into v_user,v_business
  from public.business_memberships
  where active and role='owner'
  order by created_at
  limit 1;

  if v_user is null then
    raise exception 'TEST FAILED: no owner fixture';
  end if;

  insert into public.products(
    business_id,name,unit,sale_price,average_cost,stock_quantity,min_stock,
    is_stock_item,is_sellable,active,production_station,prep_time_seconds
  ) values (
    v_business,'TEST KDS OPS','UN',10,2,10,1,true,true,true,'kitchen',120
  ) returning id into v_product;

  insert into public.customers(business_id,name,active)
  values(v_business,'TEST KDS OPS CUSTOMER',true)
  returning id into v_customer;

  set local role authenticated;
  perform set_config('request.jwt.claims',json_build_object('sub',v_user::text,'role','authenticated')::text,true);

  insert into public.sales(
    business_id,customer_id,channel,subtotal,discount,total,notes,status,production_priority
  ) values (
    v_business,v_customer,'counter',10,0,10,'KDS OPS TEST','open','urgent'
  ) returning id into v_sale;

  insert into public.sale_items(sale_id,product_id,quantity,unit_price)
  values(v_sale,v_product,1,10);

  perform private.sync_production_tickets(v_sale);

  select * into v_ticket
  from public.production_tickets
  where sale_id=v_sale and station='kitchen';

  if v_ticket.id is null or v_ticket.priority<>'urgent' or v_ticket.target_seconds<>120 then
    raise exception 'TEST FAILED: ticket priority/target not synchronized';
  end if;

  select public.set_production_ticket_priority(v_ticket.id,'high') into v_ticket;

  if v_ticket.priority<>'high' then
    raise exception 'TEST FAILED: priority transition failed';
  end if;

  select public.get_kds_metrics(v_business,now()-interval '1 hour',now()+interval '1 minute') into v_metrics;

  if coalesce((v_metrics->>'active')::integer,0) < 1 then
    raise exception 'TEST FAILED: metrics active count missing';
  end if;
end;
$test$;

rollback;

select 'Urbana Café KDS operational test: PASS' as result;
