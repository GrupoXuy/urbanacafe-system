-- Read-only reporting regression test.
-- Run inside a disposable transaction; all test data is rolled back at the end.

begin;

do $$
declare
  v_business uuid;
  v_product uuid;
  v_sale uuid;
  v_stock numeric;
  v_stock_value numeric;
  v_below_min boolean;
  v_gross_qty numeric;
  v_gross_revenue numeric;
  v_gross_cogs numeric;
  v_waste_qty numeric;
  v_adjustment_qty numeric;
  v_invoker boolean;
begin
  select id into v_business from public.businesses order by created_at limit 1;
  if v_business is null then
    raise exception 'TEST FAILED: business fixture not found';
  end if;

  insert into public.products(
    business_id,name,unit,sale_price,average_cost,stock_quantity,min_stock,
    is_stock_item,is_sellable,active
  ) values (
    v_business,'REPORT TEST PRODUCT','UN',5,2,0,5,true,true,true
  )
  returning id into v_product;

  update public.products
  set stock_quantity=10
  where id=v_product;

  insert into public.stock_movements(
    business_id,product_id,movement_type,quantity,unit_cost,note
  ) values (
    v_business,v_product,'purchase',10,2,'report test'
  );

  insert into public.stock_movements(
    business_id,product_id,movement_type,quantity,unit_cost,note
  ) values (
    v_business,v_product,'waste',-2,2,'report test'
  );

  insert into public.stock_movements(
    business_id,product_id,movement_type,quantity,unit_cost,note
  ) values (
    v_business,v_product,'adjustment',-4,2,'report test'
  );

  update public.products
  set stock_quantity=4
  where id=v_product;

  select stock_quantity,stock_value,below_minimum
  into v_stock,v_stock_value,v_below_min
  from public.business_inventory_summary
  where business_id=v_business and product_id=v_product;

  if v_stock<>4 or v_stock_value<>8 or v_below_min is not true then
    raise exception 'TEST FAILED: inventory summary mismatch';
  end if;

  insert into public.sales(
    business_id,status,subtotal,total,cogs,channel,completed_at
  ) values (
    v_business,'completed',10,10,4,'counter',now()
  )
  returning id into v_sale;

  insert into public.sale_items(
    sale_id,product_id,quantity,unit_price,unit_cost
  ) values (
    v_sale,v_product,2,5,2
  );

  select net_quantity,net_revenue,net_cogs
  into v_gross_qty,v_gross_revenue,v_gross_cogs
  from public.business_product_sales_daily
  where business_id=v_business
    and product_id=v_product
  order by report_date desc
  limit 1;

  if v_gross_qty<>2 or v_gross_revenue<>10 or v_gross_cogs<>4 then
    raise exception 'TEST FAILED: product sales report mismatch';
  end if;

  select sum(case when movement_type='waste' then quantity else 0 end),
         sum(case when movement_type='adjustment' then quantity else 0 end)
  into v_waste_qty,v_adjustment_qty
  from public.business_stock_movement_daily
  where business_id=v_business and product_id=v_product;

  if v_waste_qty<>-2 or v_adjustment_qty<>-4 then
    raise exception 'TEST FAILED: stock movement report mismatch';
  end if;

  select 'security_invoker=true'=any(coalesce(c.reloptions,array[]::text[]))
  into v_invoker
  from pg_class c
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname='business_inventory_summary' and c.relkind='v';

  if v_invoker is not true then
    raise exception 'TEST FAILED: inventory summary view is not security_invoker';
  end if;
end;
$$;

rollback;
