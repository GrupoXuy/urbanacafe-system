-- Urbana Café: privileged operational function isolation regression test.
-- Verifies the exposed public RPCs are SECURITY INVOKER wrappers while their
-- privileged implementations live behind the non-exposed private schema.

begin;

do $test$
declare
  v_name text;
  v_public_definer integer;
  v_private_definer integer;
  v_public_invoker integer;
  v_auth_public integer;
  v_anon_public integer;
  v_public_search_path text;
  v_private_search_path text;
begin
  select count(*) into v_public_definer
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.prosecdef
    and p.proname=any(array[
      'close_cash_session','create_purchase_transaction','create_reservation_transaction',
      'create_sale_transaction','finalize_sale','open_cash_session','post_purchase',
      'record_cash_movement','record_expense','refund_sale_transaction',
      'setup_business','update_reservation_status'
    ]);

  select count(*) into v_private_definer
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private'
    and p.prosecdef
    and p.proname=any(array[
      'close_cash_session','create_purchase_transaction','create_reservation_transaction',
      'create_sale_transaction','finalize_sale','open_cash_session','post_purchase',
      'record_cash_movement','record_expense','refund_sale_transaction',
      'setup_business','update_reservation_status'
    ]);

  select count(*) into v_public_invoker
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

  select count(*) into v_auth_public
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname=any(array[
      'close_cash_session','create_purchase_transaction','create_reservation_transaction',
      'create_sale_transaction','finalize_sale','open_cash_session','post_purchase',
      'record_cash_movement','record_expense','refund_sale_transaction',
      'setup_business','update_reservation_status'
    ])
    and has_function_privilege('authenticated',p.oid,'EXECUTE');

  select count(*) into v_anon_public
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname=any(array[
      'close_cash_session','create_purchase_transaction','create_reservation_transaction',
      'create_sale_transaction','finalize_sale','open_cash_session','post_purchase',
      'record_cash_movement','record_expense','refund_sale_transaction',
      'setup_business','update_reservation_status'
    ])
    and has_function_privilege('anon',p.oid,'EXECUTE');

  select p.proconfig[1]
    into v_public_search_path
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='create_sale_transaction'
  limit 1;

  select p.proconfig[1]
    into v_private_search_path
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private'
    and p.proname='create_sale_transaction'
  limit 1;

  if v_public_definer<>0
     or v_private_definer<>12
     or v_public_invoker<>12 then
    raise exception 'TEST FAILED: public_definer %, private_definer %, public_invoker %',
      v_public_definer,v_private_definer,v_public_invoker;
  end if;

  if v_auth_public<>12 or v_anon_public<>0 then
    raise exception 'TEST FAILED: public wrapper grants auth %, anon %',
      v_auth_public,v_anon_public;
  end if;

  if v_public_search_path<>'search_path=public' then
    raise exception 'TEST FAILED: public wrapper search_path %',v_public_search_path;
  end if;

  if v_private_search_path<>'search_path=' then
    raise exception 'TEST FAILED: private implementation search_path %',v_private_search_path;
  end if;
end;
$test$;

rollback;

select 'Urbana Café private operational function isolation test: PASS' as result;
