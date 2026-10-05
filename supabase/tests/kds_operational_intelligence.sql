begin;
do $test$
declare v_user uuid; v_business uuid; v_result jsonb; v_capacity integer;
begin
 select user_id,business_id into v_user,v_business from public.business_memberships where active and role='owner' order by created_at limit 1;
 if v_user is null then raise exception 'TEST FAILED: no owner fixture'; end if;
 set local role authenticated;
 perform set_config('request.jwt.claims',json_build_object('sub',v_user::text,'role','authenticated')::text,true);
 select(public.set_production_station_capacity(v_business,'kitchen',2)).capacity_units into v_capacity;
 if v_capacity<>2 then raise exception 'TEST FAILED: capacity setter'; end if;
 select public.get_kds_operational_control(v_business) into v_result;
 if v_result is null or jsonb_typeof(v_result->'stations')<>'array' or jsonb_typeof(v_result->'alerts')<>'array' then raise exception 'TEST FAILED: control payload'; end if;
 if(select count(*) from jsonb_array_elements(v_result->'stations') s where s->>'station'='kitchen' and(s->>'capacity_units')::integer=2)<>1 then raise exception 'TEST FAILED: capacity not reflected'; end if;
end;$test$;
rollback;
select 'Urbana Café KDS operational intelligence test: PASS' as result;