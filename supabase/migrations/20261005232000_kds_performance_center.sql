create or replace function private.get_kds_performance(
  p_business_id uuid,p_from timestamptz,p_to timestamptz
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb;
begin
  if auth.uid() is null then raise exception 'Usuário não autenticado'; end if;
  if not public.has_business_role(p_business_id,array['owner','manager','cashier','waiter','stockkeeper','analyst']::public.member_role[]) then raise exception 'Usuário sem acesso aos indicadores do KDS'; end if;
  with scoped as (
    select pt.*,
      extract(epoch from(coalesce(pt.started_at,pt.ready_at,pt.served_at,now())-pt.sent_at))::numeric wait_seconds,
      extract(epoch from(coalesce(pt.ready_at,pt.served_at,now())-coalesce(pt.started_at,pt.sent_at)))::numeric prep_seconds,
      extract(epoch from(coalesce(pt.served_at,now())-pt.sent_at))::numeric total_seconds,
      case when pt.status in('pending','preparing') then now()>case when pt.status='pending' then pt.sent_at+make_interval(secs=>pt.target_seconds) else pt.started_at+make_interval(secs=>pt.target_seconds) end
           when pt.status='served' then coalesce(pt.ready_at,pt.served_at)>coalesce(pt.started_at,pt.sent_at)+make_interval(secs=>pt.target_seconds)
           else false end delayed
    from public.production_tickets pt
    where pt.business_id=p_business_id and pt.sent_at>=p_from and pt.sent_at<p_to
  ), completed as(select * from scoped where status='served'),
  station_rows as(select station,count(*)::integer served,count(*) filter(where delayed)::integer delayed,coalesce(avg(wait_seconds),0) avg_wait_seconds,coalesce(avg(prep_seconds),0) avg_prep_seconds,coalesce(avg(total_seconds),0) avg_total_seconds from completed group by station),
  station_data as(select coalesce(jsonb_agg(jsonb_build_object('station',station,'served',served,'delayed',delayed,'avg_wait_seconds',round(avg_wait_seconds,1),'avg_prep_seconds',round(avg_prep_seconds,1),'avg_total_seconds',round(avg_total_seconds,1),'sla_percent',case when served>0 then round(100.0*(served-delayed)/served,1) else 0 end) order by station),'[]'::jsonb) data from station_rows),
  product_rows as(select p.id product_id,p.name product_name,p.production_station station,sum(si.quantity)::numeric quantity,count(distinct sc.sale_id)::integer tickets,count(distinct sc.sale_id) filter(where sc.delayed)::integer delayed_tickets,coalesce(avg(sc.prep_seconds),0) avg_prep_seconds,coalesce(avg(sc.total_seconds),0) avg_total_seconds from completed sc join public.sale_items si on si.sale_id=sc.sale_id join public.products p on p.id=si.product_id and p.production_station=sc.station where p.production_station in('kitchen','bar') group by p.id,p.name,p.production_station),
  product_data as(select coalesce(jsonb_agg(jsonb_build_object('product_id',product_id,'product_name',product_name,'station',station,'quantity',quantity,'tickets',tickets,'delayed_tickets',delayed_tickets,'avg_prep_seconds',round(avg_prep_seconds,1),'avg_total_seconds',round(avg_total_seconds,1)) order by delayed_tickets desc,avg_prep_seconds desc,quantity desc),'[]'::jsonb) data from(select * from product_rows order by delayed_tickets desc,avg_prep_seconds desc,quantity desc limit 12)x),
  hour_rows as(select extract(hour from served_at at time zone coalesce((select timezone from public.businesses where id=p_business_id),'America/Montevideo'))::integer hour_value,count(*)::integer served,coalesce(avg(total_seconds),0) avg_total_seconds from completed group by 1),
  hour_data as(select coalesce(jsonb_agg(jsonb_build_object('hour',hour_value,'served',served,'avg_total_seconds',round(avg_total_seconds,1)) order by hour_value),'[]'::jsonb) data from hour_rows)
  select jsonb_build_object('period',jsonb_build_object('from',p_from,'to',p_to),'served',(select count(*) from completed),'delayed',(select count(*) from completed where delayed),'avg_wait_seconds',coalesce((select avg(wait_seconds) from completed),0),'avg_prep_seconds',coalesce((select avg(prep_seconds) from completed),0),'avg_total_seconds',coalesce((select avg(total_seconds) from completed),0),'throughput_per_hour',case when extract(epoch from(p_to-p_from))>0 then round((select count(*)::numeric from completed)/(extract(epoch from(p_to-p_from))/3600),1) else 0 end,'sla_percent',case when(select count(*) from completed)>0 then round(100.0*(select count(*) from completed where not delayed)/(select count(*) from completed),1) else 0 end,'stations',(select data from station_data),'products',(select data from product_data),'hours',(select data from hour_data)) into v_result;
  return v_result;
end; $$;

create or replace function public.get_kds_performance(p_business_id uuid,p_from timestamptz,p_to timestamptz)
returns jsonb language sql security invoker set search_path=public as $$ select private.get_kds_performance(p_business_id,p_from,p_to); $$;
revoke all on function private.get_kds_performance(uuid,timestamptz,timestamptz) from public,anon;
grant execute on function private.get_kds_performance(uuid,timestamptz,timestamptz) to authenticated;
revoke all on function public.get_kds_performance(uuid,timestamptz,timestamptz) from public,anon;
grant execute on function public.get_kds_performance(uuid,timestamptz,timestamptz) to authenticated;
