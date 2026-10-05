-- Urbana Café: stock operation hardening regression test.
-- Validates that direct stock mutation is blocked while approved RPCs remain atomic.

begin;

do $test$
declare
  v_user uuid;
  v_business uuid;
  v_other_business uuid;
  v_product uuid;
  v_other_product uuid;
  v_stock numeric;
  v_adjustment_qty numeric;
  v_waste_qty numeric;
  v_movement_count integer;
  v_audit_count integer;
  v_direct_update_failed boolean:=false;
  v_direct_insert_failed boolean:=false;
  v_cross_business_failed boolean:=false;
begin
  select m.user_id,m.business_id
    into v_user,v_business
  from public.business_memberships m
  where m.role='owner'
    and m.active
  order by m.created_at
  limit 1;

  if v_user is null or v_business is null then
    raise exception 'TEST FAILED: no active owner fixture';
  end if;

  insert into public.products(
    business_id,name,unit,sale_price,average_cost,stock_quantity,min_stock,
    is_stock_item,is_sellable,active
  ) values (
    v_business,'STOCK HARDENING TEST','UN',10,3,0,2,true,true,true
  )
  returning id into v_product;

  insert into public.businesses(name,legal_name)
  values('STOCK HARDENING OTHER','STOCK HARDENING OTHER')
  returning id into v_other_business;

  insert into public.products(
    business_id,name,unit,sale_price,average_cost,stock_quantity,min_stock,
    is_stock_item,is_sellable,active
  ) values (
    v_other_business,'STOCK HARDENING OTHER PRODUCT','UN',10,3,0,0,true,true,true
  )
  returning id into v_other_product;

  set local role authenticated;
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub',v_user::text,'role','authenticated')::text,
    true
  );

  begin
    perform public.record_stock_adjustment(v_product,10,'Entrada de ajuste');
  exception when others then
    raise exception 'TEST FAILED: approved stock adjustment rejected: %',sqlerrm;
  end;

  select stock_quantity into v_stock
  from public.products where id=v_product;

  if v_stock<>10 then
    raise exception 'TEST FAILED: adjustment did not update stock';
  end if;

  begin
    update public.products set stock_quantity=99 where id=v_product;
  exception when others then
    v_direct_update_failed:=true;
  end;

  if not v_direct_update_failed then
    raise exception 'TEST FAILED: direct stock update was allowed';
  end if;

  select stock_quantity into v_stock
  from public.products where id=v_product;

  if v_stock<>10 then
    raise exception 'TEST FAILED: direct update changed stock after rejection';
  end if;

  begin
    insert into public.products(
      business_id,name,unit,sale_price,average_cost,stock_quantity,min_stock,
      is_stock_item,is_sellable,active
    ) values (
      v_business,'STOCK HARDENING DIRECT INSERT','UN',10,3,5,0,true,true,true
    );
  exception when others then
    v_direct_insert_failed:=true;
  end;

  if not v_direct_insert_failed then
    raise exception 'TEST FAILED: non-zero direct stock insert was allowed';
  end if;

  begin
    perform public.set_stock_count(v_product,7,'Inventário físico');
  exception when others then
    raise exception 'TEST FAILED: inventory count rejected: %',sqlerrm;
  end;

  begin
    perform public.record_stock_waste(v_product,2,'Perda operacional');
  exception when others then
    raise exception 'TEST FAILED: waste operation rejected: %',sqlerrm;
  end;

  select stock_quantity into v_stock
  from public.products where id=v_product;

  if v_stock<>5 then
    raise exception 'TEST FAILED: final stock expected 5, got %',v_stock;
  end if;

  select
    coalesce(sum(quantity) filter(where movement_type='adjustment'),0),
    coalesce(sum(quantity) filter(where movement_type='waste'),0),
    count(*)::int
  into v_adjustment_qty,v_waste_qty,v_movement_count
  from public.stock_movements
  where product_id=v_product;

  if v_adjustment_qty<>7 or v_waste_qty<>-2 or v_movement_count<>3 then
    raise exception 'TEST FAILED: stock ledger mismatch';
  end if;

  select count(*)::int
  into v_audit_count
  from public.audit_logs a
  where a.entity='stock_movement'
    and a.entity_id in (
      select id from public.stock_movements where product_id=v_product
    );

  if v_audit_count<>3 then
    raise exception 'TEST FAILED: stock operation audit trail mismatch';
  end if;

  begin
    perform public.record_stock_adjustment(v_other_product,1,'Cross business attempt');
  exception when others then
    v_cross_business_failed:=true;
  end;

  if not v_cross_business_failed then
    raise exception 'TEST FAILED: cross-business stock operation was allowed';
  end if;
end;
$test$;

rollback;

select 'Urbana Café stock operation hardening test: PASS' as result;
