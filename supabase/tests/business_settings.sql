-- Urbana Café: business settings regression test.
-- Confirms authorization, validation and audit old/new snapshots.

begin;

do $test$
declare
  v_user uuid;
  v_business uuid;
  v_old_name text;
  v_after_name text;
  v_audit_old text;
  v_audit_new text;
  v_denied boolean:=false;
  v_invalid_timezone boolean:=false;
begin
  select user_id,business_id
    into v_user,v_business
  from public.business_memberships
  where role='owner' and active
  order by created_at
  limit 1;

  if v_user is null or v_business is null then
    raise exception 'TEST FAILED: no owner fixture';
  end if;

  select name into v_old_name from public.businesses where id=v_business;

  set local role authenticated;
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub',v_user::text,'role','authenticated')::text,
    true
  );

  perform public.update_business_settings(
    v_business,
    'TEST Business Settings',
    'TEST Legal',
    'USD',
    'America/Sao_Paulo'
  );

  select name into v_after_name
  from public.businesses
  where id=v_business;

  if v_after_name<>'TEST Business Settings' then
    raise exception 'TEST FAILED: settings update did not persist';
  end if;

  select
    old_data->>'name',
    new_data->>'name'
  into v_audit_old,v_audit_new
  from public.audit_logs
  where business_id=v_business
    and action='business_settings_update'
    and entity_id=v_business
  order by created_at desc
  limit 1;

  if v_audit_old<>v_old_name or v_audit_new<>'TEST Business Settings' then
    raise exception 'TEST FAILED: audit snapshots invalid: old %, new %',v_audit_old,v_audit_new;
  end if;

  begin
    perform public.update_business_settings(
      v_business,
      'TEST Bad TZ',
      null,
      'USD',
      'Not/A/Timezone'
    );
  exception when others then
    v_invalid_timezone:=true;
  end;

  if not v_invalid_timezone then
    raise exception 'TEST FAILED: invalid timezone accepted';
  end if;

  set local role postgres;
  update public.business_memberships
  set role='cashier'
  where business_id=v_business and user_id=v_user;
  set local role authenticated;

  begin
    perform public.update_business_settings(
      v_business,
      'TEST Unauthorized',
      null,
      'USD',
      'America/Montevideo'
    );
  exception when others then
    v_denied:=true;
  end;

  if not v_denied then
    raise exception 'TEST FAILED: cashier could change business settings';
  end if;
end;
$test$;

rollback;

select 'Urbana Café business settings test: PASS' as result;
