-- Product deletion RLS smoke test.
-- The fixture is rolled back at the end; no production data is retained.

begin;

do $main_test$
declare
  v_user uuid;
  v_business uuid;
  v_product uuid;
  v_deleted_id uuid;
  v_remaining integer;
begin
  select user_id into v_user
  from public.business_memberships
  where role='owner' and active
  order by created_at
  limit 1;

  if v_user is null then
    raise exception 'TEST FAILED: no active owner fixture user';
  end if;

  insert into public.businesses(name,legal_name)
  values('TEST Product Delete','TEST Product Delete')
  returning id into v_business;

  insert into public.business_memberships(business_id,user_id,role,active)
  values(v_business,v_user,'owner',true);

  insert into public.products(
    business_id,name,unit,sale_price,average_cost,stock_quantity,
    min_stock,is_stock_item,is_sellable,active
  )
  values(v_business,'TEST Delete Product','UN',10,2,0,0,true,true,true)
  returning id into v_product;

  set local role authenticated;
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub',v_user::text,'role','authenticated')::text,
    true
  );

  delete from public.products
  where id=v_product
    and business_id=v_business
  returning id into v_deleted_id;

  if v_deleted_id is null then
    raise exception 'TEST FAILED: owner product deletion was not allowed';
  end if;

  select count(*) into v_remaining
  from public.products
  where id=v_product;

  if v_remaining<>0 then
    raise exception 'TEST FAILED: product still exists after deletion';
  end if;
end;
$main_test$;

rollback;

select 'Product deletion RLS test: PASS' as result;
