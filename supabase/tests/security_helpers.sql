-- Urbana Café: authorization helper hardening regression test.
-- Uses the existing seeded owner fixture and rolls all temporary rows back.

begin;

do $test$
declare
  v_user uuid;
  v_business uuid;
  v_other_business uuid;
begin
  select m.user_id
    into v_user
  from public.business_memberships m
  where m.role='owner'
    and m.active
  order by m.created_at
  limit 1;

  if v_user is null then
    raise exception 'TEST FAILED: no active owner fixture user';
  end if;

  select m.business_id
    into v_business
  from public.business_memberships m
  where m.user_id=v_user
    and m.active
  order by m.created_at
  limit 1;

  insert into public.businesses(name,legal_name)
  values('TEST Helper Hardening Other','TEST Helper Hardening Other')
  returning id into v_other_business;

  set local role authenticated;
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub',v_user::text,'role','authenticated')::text,
    true
  );

  if not public.is_business_member(v_business) then
    raise exception 'TEST FAILED: current user was not recognized as business member';
  end if;

  if public.is_business_member(v_other_business) then
    raise exception 'TEST FAILED: cross-business membership leaked';
  end if;

  if not public.has_business_role(
    v_business,
    array['owner']::public.member_role[]
  ) then
    raise exception 'TEST FAILED: owner role was not recognized';
  end if;

  if public.has_business_role(
    v_business,
    array['cashier']::public.member_role[]
  ) then
    raise exception 'TEST FAILED: role check returned an unauthorized role';
  end if;
end;
$test$;

rollback;

select 'Urbana Café authorization helper hardening test: PASS' as result;
