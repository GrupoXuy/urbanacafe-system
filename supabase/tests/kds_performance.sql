begin;
do $test$
declare v_user uuid; v_business uuid; v_result jsonb;
begin
 select user_id,business_id into v_user,v_business from public.business_memberships where active and role='owner' order by created_at limit 1;
 if v_user is null then raise exception 'TEST FAILED: no owner fixture'; end if;
 set local role authenticated;
 perform set_config('request.jwt.claims',json_build_object('sub',v_user::text,'role','authenticated')::text,true);
 select public.get_kds_performance(v_business,now()-interval '30 days',now()+interval '1 minute') into v_result;
 if v_result is null or jsonb_typeof(v_result->'stations')<>'array' or jsonb_typeof(v_result->'products')<>'array' or jsonb_typeof(v_result->'hours')<>'array' then raise exception 'TEST FAILED: performance payload shape invalid'; end if;
end;$test$;
rollback;
select 'Urbana Café KDS performance test: PASS' as result;
