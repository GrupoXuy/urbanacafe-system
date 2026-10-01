-- Urbana Café RPC/RLS smoke test.
-- Run in a Supabase SQL session with sufficient privileges.
-- All fixtures are rolled back at the end.
begin;

do $$
declare
  v_user uuid;
  v_business uuid;
  v_other_business uuid;
  v_product uuid;
  v_other_product uuid;
  v_session uuid;
  v_sale public.sales%rowtype;
  v_cross_count integer;
  v_stock numeric;
  v_payment numeric;
  v_cash numeric;
  v_expected numeric;
begin
  select m.user_id
  into v_user
  from public.business_memberships m
  where m.role='owner' and m.active
  order by m.created_at
  limit 1;

  if v_user is null then
    raise exception 'TEST FAILED: no active owner fixture user';
  end if;

  insert into public.businesses(name,legal_name)
  values('TEST Urbana Café','TEST Urbana Café')
  returning id into v_business;

  insert into public.businesses(name,legal_name)
  values('TEST Urbana Café Other','TEST Urbana Café Other')
  returning id into v_other_business;

  insert into public.business_memberships(business_id,user_id,role,active)
  values(v_business,v_user,'owner',true);

  insert into public.products(
    business_id,name,unit,sale_price,average_cost,stock_quantity,min_stock,is_stock_item,is_sellable,active
  )
  values(v_business,'TEST Espresso','UN',10,2,5,0,true,true,true)
  returning id into v_product;

  insert into public.products(
    business_id,name,unit,sale_price,average_cost,stock_quantity,min_stock,is_stock_item,is_sellable,active
  )
  values(v_other_business,'TEST Other','UN',99,1,10,0,true,true,true)
  returning id into v_other_product;

  set local role authenticated;
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub',v_user::text,'role','authenticated')::text,
    true
  );

  select id
  into v_session
  from public.open_cash_session(v_business,100);

  begin
    insert into public.cash_movements(
      business_id,cash_session_id,movement_type,amount,description,created_by
    )
    values(v_business,v_session,'deposit',1,'should fail',v_user);

    raise exception 'TEST FAILED: direct cash_movements INSERT unexpectedly succeeded';
  exception
    when others then
      if sqlerrm like 'TEST FAILED:%' then
        raise;
      end if;
  end;

  perform public.record_cash_movement(
    v_business,
    v_session,
    'withdrawal',
    10,
    'Teste de retirada'
  );

  select public.create_sale_transaction(
    v_business,
    v_session,
    null,
    null,
    'Teste POS atomic',
    'cash',
    jsonb_build_array(jsonb_build_object('product_id',v_product,'quantity',2)),
    0
  )
  into v_sale;

  if v_sale.status<>'completed' or round(v_sale.total,2)<>20 then
    raise exception 'TEST FAILED: sale was not completed at expected total';
  end if;

  select stock_quantity
  into v_stock
  from public.products
  where id=v_product;

  if round(v_stock,3)<>3 then
    raise exception 'TEST FAILED: stock expected 3, got %',v_stock;
  end if;

  select coalesce(sum(amount),0)
  into v_payment
  from public.sale_payments
  where sale_id=v_sale.id;

  if round(v_payment,2)<>20 then
    raise exception 'TEST FAILED: payment expected 20, got %',v_payment;
  end if;

  select round(coalesce(sum(amount),0),2)
  into v_cash
  from public.cash_movements
  where cash_session_id=v_session;

  if v_cash<>110 then
    raise exception 'TEST FAILED: cash expected 110, got %',v_cash;
  end if;

  select count(*)
  into v_cross_count
  from public.products
  where business_id=v_other_business;

  if v_cross_count<>0 then
    raise exception 'TEST FAILED: cross-tenant product rows visible';
  end if;

  select expected_amount
  into v_expected
  from public.close_cash_session(v_session,110,'Teste de fechamento');

  if round(v_expected,2)<>110 then
    raise exception 'TEST FAILED: close expected 110, got %',v_expected;
  end if;
end;
$$;

rollback;

select 'Urbana Café RPC/RLS smoke test: PASS' as result;
