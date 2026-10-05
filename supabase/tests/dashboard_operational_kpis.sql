-- Urbana Café: dashboard KPI regression test.
-- Confirms financial, stock and cash indicators aggregate the current-day sources.

begin;

do $test$
declare
  v_user uuid;
  v_business uuid;
  v_product uuid;
  v_session uuid;
  v_dashboard record;
begin
  select user_id,business_id
    into v_user,v_business
  from public.business_memberships
  where role='owner' and active
  order by created_at
  limit 1;

  if v_user is null or v_business is null then
    raise exception 'TEST FAILED: no active owner fixture';
  end if;

  insert into public.products(
    business_id,name,unit,sale_price,average_cost,stock_quantity,min_stock,
    is_stock_item,is_sellable,active
  )
  values(v_business,'TEST Dashboard KPI Product','UN',10,2,10,5,true,true,true)
  returning id into v_product;

  set local role authenticated;
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub',v_user::text,'role','authenticated')::text,
    true
  );

  select id
    into v_session
  from public.open_cash_session(v_business,100);

  perform public.create_sale_transaction(
    v_business,
    v_session,
    null,
    null,
    'Dashboard KPI test',
    'cash',
    jsonb_build_array(jsonb_build_object('product_id',v_product,'quantity',2)),
    0
  );

  perform public.record_expense(
    v_business,'Dashboard KPI expense','Test',5,current_date,'cash'
  );

  select *
    into v_dashboard
  from public.business_dashboard
  where business_id=v_business;

  if v_dashboard.report_date<>(current_timestamp at time zone (select timezone from public.businesses where id=v_business))::date then
    raise exception 'TEST FAILED: dashboard report date mismatch';
  end if;

  if round(v_dashboard.revenue,2)<>20
     or round(v_dashboard.cogs,2)<>4
     or v_dashboard.sales_count<>1
     or v_dashboard.expenses<>5
     or v_dashboard.gross_profit<>16
     or v_dashboard.net_profit<>11 then
    raise exception 'TEST FAILED: financial KPIs mismatch: revenue %, cogs %, sales %, expenses %, gross %, net %',
      v_dashboard.revenue,v_dashboard.cogs,v_dashboard.sales_count,v_dashboard.expenses,
      v_dashboard.gross_profit,v_dashboard.net_profit;
  end if;

  if round(v_dashboard.stock_value,2)<>16
     or v_dashboard.stock_items<>1
     or v_dashboard.low_stock_count<>0
     or v_dashboard.out_of_stock_count<>0 then
    raise exception 'TEST FAILED: stock KPIs mismatch: value %, items %, low %, out %',
      v_dashboard.stock_value,v_dashboard.stock_items,v_dashboard.low_stock_count,v_dashboard.out_of_stock_count;
  end if;

  if v_dashboard.open_cash_sessions<>1 then
    raise exception 'TEST FAILED: open cash session KPI expected 1, got %',v_dashboard.open_cash_sessions;
  end if;
end;
$test$;

rollback;

select 'Urbana Café dashboard KPI test: PASS' as result;
