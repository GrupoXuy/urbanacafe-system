-- Urbana Café role/permission matrix.
begin;

do $test$
declare
  v_user uuid;
  v_owner uuid; v_manager uuid; v_cashier uuid; v_waiter uuid; v_stockkeeper uuid; v_analyst uuid;
  v_waiter_product uuid; v_stock_product uuid; v_cashier_product uuid; v_supplier uuid; v_session uuid; v_sale public.sales%rowtype;
  v_count integer;
begin
  select user_id into v_user from public.business_memberships where role='owner' and active order by created_at limit 1;
  if v_user is null then raise exception 'TEST FAILED: no owner fixture user'; end if;

  insert into public.businesses(name) values
    ('TEST Role Owner'),('TEST Role Manager'),('TEST Role Cashier'),
    ('TEST Role Waiter'),('TEST Role Stockkeeper'),('TEST Role Analyst');

  select id into v_owner from public.businesses where name='TEST Role Owner';
  select id into v_manager from public.businesses where name='TEST Role Manager';
  select id into v_cashier from public.businesses where name='TEST Role Cashier';
  select id into v_waiter from public.businesses where name='TEST Role Waiter';
  select id into v_stockkeeper from public.businesses where name='TEST Role Stockkeeper';
  select id into v_analyst from public.businesses where name='TEST Role Analyst';

  insert into public.business_memberships(business_id,user_id,role,active) values
    (v_owner,v_user,'owner',true),(v_manager,v_user,'manager',true),(v_cashier,v_user,'cashier',true),
    (v_waiter,v_user,'waiter',true),(v_stockkeeper,v_user,'stockkeeper',true),(v_analyst,v_user,'analyst',true);

  insert into public.products(business_id,name,unit,sale_price,average_cost,stock_quantity,is_stock_item,is_sellable,active)
  values(v_owner,'TEST owner product','UN',10,1,10,true,true,true),
        (v_manager,'TEST manager product','UN',10,1,10,true,true,true),
        (v_cashier,'TEST cashier product','UN',10,1,10,true,true,true),
        (v_waiter,'TEST waiter product','UN',10,1,10,true,true,true),
        (v_stockkeeper,'TEST stock product','UN',10,1,10,true,true,true),
        (v_analyst,'TEST analyst product','UN',10,1,10,true,true,true)
  returning id into v_waiter_product;

  select id into v_cashier_product from public.products where business_id=v_cashier limit 1;
  select id into v_stock_product from public.products where business_id=v_stockkeeper limit 1;
  insert into public.suppliers(business_id,name,active) values(v_stockkeeper,'TEST supplier',true) returning id into v_supplier;
  insert into public.stock_movements(business_id,product_id,movement_type,quantity,unit_cost,created_by)
  values(v_stockkeeper,v_stock_product,'adjustment',1,1,v_user);
  insert into public.cash_sessions(business_id,opened_by,opening_amount,status)
  values(v_waiter,v_user,0,'open') returning id into v_session;

  set local role authenticated;
  perform set_config('request.jwt.claims',json_build_object('sub',v_user::text,'role','authenticated')::text,true);

  insert into public.products(business_id,name,unit,sale_price,average_cost,stock_quantity,is_stock_item,is_sellable,active)
  values(v_owner,'TEST owner write','UN',12,1,0,true,true,true);

  insert into public.products(business_id,name,unit,sale_price,average_cost,stock_quantity,is_stock_item,is_sellable,active)
  values(v_manager,'TEST manager write','UN',12,1,0,true,true,true);

  begin
    insert into public.products(business_id,name,unit,sale_price,average_cost,stock_quantity,is_stock_item,is_sellable,active)
    values(v_cashier,'TEST cashier forbidden','UN',12,1,0,true,true,true);
    raise exception 'TEST FAILED: cashier inserted product';
  exception when others then
    if sqlerrm like 'TEST FAILED:%' then raise; end if;
  end;

  begin
    insert into public.categories(business_id,name) values(v_analyst,'TEST analyst forbidden');
    raise exception 'TEST FAILED: analyst inserted category';
  exception when others then
    if sqlerrm like 'TEST FAILED:%' then raise; end if;
  end;

  select count(*) into v_count from public.stock_movements where business_id=v_stockkeeper;
  if v_count<>1 then raise exception 'TEST FAILED: stockkeeper should read stock movements'; end if;

  select count(*) into v_count from public.stock_movements where business_id=v_cashier;
  if v_count<>0 then raise exception 'TEST FAILED: cashier should not read stock movements'; end if;

  begin
    insert into public.cash_movements(business_id,cash_session_id,movement_type,amount,created_by)
    values(v_waiter,v_session,'deposit',5,v_user);
    raise exception 'TEST FAILED: waiter inserted cash movement';
  exception when others then
    if sqlerrm like 'TEST FAILED:%' then raise; end if;
  end;

  select * into v_sale from public.create_sale_transaction(
    v_waiter,v_session,null,null,'role matrix waiter sale','cash',
    jsonb_build_array(jsonb_build_object('product_id',v_waiter_product,'quantity',1)),0
  );
  if v_sale.status<>'completed' then raise exception 'TEST FAILED: waiter sale was not completed'; end if;

  begin
    perform public.create_sale_transaction(
      v_analyst,null,null,null,'role matrix forbidden','cash',
      jsonb_build_array(jsonb_build_object('product_id',v_stock_product,'quantity',1)),0
    );
    raise exception 'TEST FAILED: analyst completed sale';
  exception when others then
    if sqlerrm like 'TEST FAILED:%' then raise; end if;
  end;

  begin
    perform public.create_purchase_transaction(
      v_cashier,null,'NO','transfer',
      jsonb_build_array(jsonb_build_object('product_id',v_cashier_product,'quantity',1,'unit_cost',2))
    );
    raise exception 'TEST FAILED: cashier completed purchase';
  exception when others then
    if sqlerrm like 'TEST FAILED:%' then raise; end if;
  end;

  perform public.create_purchase_transaction(
    v_stockkeeper,v_supplier,'ROLE-001','transfer',
    jsonb_build_array(jsonb_build_object('product_id',v_stock_product,'quantity',1,'unit_cost',2))
  );

  select count(*) into v_count from public.audit_logs where business_id=v_owner;
  if v_count<0 then raise exception 'TEST FAILED: impossible audit state'; end if;

  raise notice 'Urbana Café role/permission matrix test: PASS';
end;
$test$;

rollback;
select 'Urbana Café role/permission matrix test: PASS' as result;
