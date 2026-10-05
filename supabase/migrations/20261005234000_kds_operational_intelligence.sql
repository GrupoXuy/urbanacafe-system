create table if not exists public.production_station_capacity(
 business_id uuid not null references public.businesses(id) on delete cascade,
 station public.production_station not null,
 capacity_units integer not null default 1,
 updated_by uuid references auth.users(id),
 updated_at timestamptz not null default now(),
 primary key(business_id,station),
 constraint production_station_capacity_station_check check(station in('kitchen','bar')),
 constraint production_station_capacity_units_check check(capacity_units between 1 and 20)
);
create table if not exists public.kds_operational_alerts(
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.businesses(id) on delete cascade,
 station public.production_station,
 dedupe_key text not null,
 severity text not null,
 title text not null,
 message text not null,
 metric_value numeric,
 threshold numeric,
 active boolean not null default true,
 first_triggered_at timestamptz not null default now(),
 last_triggered_at timestamptz not null default now(),
 resolved_at timestamptz,
 updated_at timestamptz not null default now(),
 constraint kds_operational_alerts_station_check check(station is null or station in('kitchen','bar')),
 constraint kds_operational_alerts_severity_check check(severity in('warning','critical')),
 constraint kds_operational_alerts_business_dedupe_key_key unique(business_id,dedupe_key)
);
create index if not exists production_station_capacity_business_idx on public.production_station_capacity(business_id,station);
create index if not exists kds_operational_alerts_active_idx on public.kds_operational_alerts(business_id,active,last_triggered_at desc);
alter table public.production_station_capacity enable row level security;
alter table public.kds_operational_alerts enable row level security;
drop policy if exists production_station_capacity_read on public.production_station_capacity;
create policy production_station_capacity_read on public.production_station_capacity for select to authenticated using(is_business_member(business_id));
drop policy if exists kds_operational_alerts_read on public.kds_operational_alerts;
create policy kds_operational_alerts_read on public.kds_operational_alerts for select to authenticated using(is_business_member(business_id));
insert into public.production_station_capacity(business_id,station,capacity_units)
select b.id,s.station,1 from public.businesses b cross join(values('kitchen'::public.production_station),('bar'::public.production_station))s(station) where b.active
on conflict(business_id,station) do nothing;

create or replace function private.set_production_station_capacity(p_business_id uuid,p_station public.production_station,p_capacity_units integer)
returns public.production_station_capacity language plpgsql security definer set search_path='' as $$
declare v_row public.production_station_capacity%rowtype;
begin
 if auth.uid() is null then raise exception 'Usuário não autenticado'; end if;
 if p_station not in('kitchen','bar') then raise exception 'Estação inválida'; end if;
 if p_capacity_units not between 1 and 20 then raise exception 'A capacidade deve estar entre 1 e 20 slots'; end if;
 if not public.has_business_role(p_business_id,array['owner','manager']::public.member_role[]) then raise exception 'Usuário sem permissão para configurar capacidade de produção'; end if;
 insert into public.production_station_capacity(business_id,station,capacity_units,updated_by,updated_at)
 values(p_business_id,p_station,p_capacity_units,auth.uid(),now())
 on conflict(business_id,station) do update set capacity_units=excluded.capacity_units,updated_by=excluded.updated_by,updated_at=now()
 returning * into v_row;
 return v_row;
end; $$;
create or replace function public.set_production_station_capacity(p_business_id uuid,p_station public.production_station,p_capacity_units integer)
returns public.production_station_capacity language sql security invoker set search_path=public as $$
select private.set_production_station_capacity(p_business_id,p_station,p_capacity_units); $$;
revoke all on function private.set_production_station_capacity(uuid,public.production_station,integer) from public,anon;
grant execute on function private.set_production_station_capacity(uuid,public.production_station,integer) to authenticated;
revoke all on function public.set_production_station_capacity(uuid,public.production_station,integer) from public,anon;
grant execute on function public.set_production_station_capacity(uuid,public.production_station,integer) to authenticated;

create or replace function private.refresh_kds_operational_alerts(p_business_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_now timestamptz:=now(); v_keys text[]:='{}'; v_station_data jsonb:='[]'::jsonb; v_alert_data jsonb:='[]'::jsonb; v_result jsonb;
 r record; v_key text; v_severity text; v_title text; v_message text; v_metric numeric; v_threshold numeric;
begin
 if auth.uid() is null then raise exception 'Usuário não autenticado'; end if;
 if not public.has_business_role(p_business_id,array['owner','manager','cashier','waiter','stockkeeper','analyst']::public.member_role[]) then raise exception 'Usuário sem acesso ao alerta operacional do KDS'; end if;
 for r in
  with cfg as(
   select s.station,coalesce(c.capacity_units,1) capacity_units from(values('kitchen'::public.production_station),('bar'::public.production_station))s(station)
   left join public.production_station_capacity c on c.business_id=p_business_id and c.station=s.station
  ),base as(
   select pt.*,case when pt.status='pending' then pt.target_seconds when pt.status='preparing' then greatest(pt.target_seconds-extract(epoch from(v_now-coalesce(pt.started_at,pt.sent_at)))::integer,0) else 0 end::numeric work_seconds
   from public.production_tickets pt where pt.business_id=p_business_id and pt.status in('pending','preparing','ready')
  ),ordered as(
   select b.*,coalesce(sum(b.work_seconds) over(partition by b.station order by b.priority desc,b.sent_at asc,b.id asc rows between unbounded preceding and 1 preceding),0)::numeric ahead_work_seconds
   from base b
  ),predicted as(
   select o.*,case when o.status in('pending','preparing') then greatest(extract(epoch from(v_now+make_interval(secs=>((o.ahead_work_seconds+o.work_seconds)/greatest(c.capacity_units,1)))-(o.sent_at+make_interval(secs=>o.target_seconds)))),0) else 0 end::numeric predicted_delay_seconds
   from ordered o join cfg c on c.station=o.station
  )
  select c.station,c.capacity_units,count(p.id)::integer active,
   count(p.id) filter(where p.status='pending')::integer pending,
   count(p.id) filter(where p.status='preparing')::integer preparing,
   count(p.id) filter(where p.status='ready')::integer ready,
   coalesce(sum(p.work_seconds),0)::numeric queue_work_seconds,
   coalesce(avg(nullif(p.target_seconds,0)),900)::numeric avg_target_seconds,
   coalesce(sum(case when p.predicted_delay_seconds>0 then 1 else 0 end),0)::integer predicted_delay_count,
   coalesce(max(p.predicted_delay_seconds),0)::numeric max_predicted_delay_seconds
  from cfg c left join predicted p on p.station=c.station group by c.station,c.capacity_units order by c.station
 loop
  v_station_data:=v_station_data||jsonb_build_array(jsonb_build_object(
   'station',r.station,'capacity_units',r.capacity_units,'active',r.active,'pending',r.pending,'preparing',r.preparing,'ready',r.ready,
   'queue_work_seconds',round(r.queue_work_seconds,0),'estimated_wait_seconds',round(r.queue_work_seconds/greatest(r.capacity_units,1),0),
   'pressure_percent',round(100*r.queue_work_seconds/(3600*greatest(r.capacity_units,1)),1),
   'capacity_tickets_per_hour',round((3600*greatest(r.capacity_units,1))/greatest(r.avg_target_seconds,1),1),
   'predicted_delay_count',r.predicted_delay_count,'max_predicted_delay_seconds',round(r.max_predicted_delay_seconds,0)
  ));
  if(100*r.queue_work_seconds/(3600*greatest(r.capacity_units,1)))>=75 then
   v_key:='station_pressure:'||r.station;v_keys:=array_append(v_keys,v_key);v_metric:=100*r.queue_work_seconds/(3600*greatest(r.capacity_units,1));v_threshold:=case when v_metric>=100 then 100 else 75 end;
   v_severity:=case when v_metric>=100 then 'critical' else 'warning' end;
   v_title:='Pressão de fila — '||case when r.station='kitchen' then 'Cozinha' else 'Bar' end;
   v_message:=case when v_metric>=100 then 'A carga estimada excede a capacidade configurada da estação. Redistribua produção ou aumente os slots.' else 'A estação está próxima do limite de capacidade configurado. Acompanhe a fila para evitar atrasos.' end;
   insert into public.kds_operational_alerts(business_id,station,dedupe_key,severity,title,message,metric_value,threshold,active,first_triggered_at,last_triggered_at,resolved_at,updated_at)
   values(p_business_id,r.station,v_key,v_severity,v_title,v_message,v_metric,v_threshold,true,v_now,v_now,null,v_now)
   on conflict(business_id,dedupe_key) do update set severity=excluded.severity,title=excluded.title,message=excluded.message,metric_value=excluded.metric_value,threshold=excluded.threshold,active=true,last_triggered_at=v_now,resolved_at=null,updated_at=v_now;
  end if;
  if r.predicted_delay_count>0 then
   v_key:='predicted_delay:'||r.station;v_keys:=array_append(v_keys,v_key);v_metric:=r.max_predicted_delay_seconds;v_threshold:=r.avg_target_seconds;
   v_severity:=case when r.max_predicted_delay_seconds>=r.avg_target_seconds then 'critical' else 'warning' end;
   v_title:='Atraso previsto — '||case when r.station='kitchen' then 'Cozinha' else 'Bar' end;
   v_message:='A fila atual indica atraso previsto em '||r.predicted_delay_count||' ticket(s). Antecipe esta estação antes que o atraso aconteça.';
   insert into public.kds_operational_alerts(business_id,station,dedupe_key,severity,title,message,metric_value,threshold,active,first_triggered_at,last_triggered_at,resolved_at,updated_at)
   values(p_business_id,r.station,v_key,v_severity,v_title,v_message,v_metric,v_threshold,true,v_now,v_now,null,v_now)
   on conflict(business_id,dedupe_key) do update set severity=excluded.severity,title=excluded.title,message=excluded.message,metric_value=excluded.metric_value,threshold=excluded.threshold,active=true,last_triggered_at=v_now,resolved_at=null,updated_at=v_now;
  end if;
  if r.ready>=5 then
   v_key:='ready_backlog:'||r.station;v_keys:=array_append(v_keys,v_key);v_metric:=r.ready;v_threshold:=5;v_severity:=case when r.ready>=8 then 'critical' else 'warning' end;
   v_title:='Acúmulo de prontos — '||case when r.station='kitchen' then 'Cozinha' else 'Bar' end;
   v_message:='Há '||r.ready||' ticket(s) prontos aguardando continuidade do atendimento. Verifique entrega/retirada.';
   insert into public.kds_operational_alerts(business_id,station,dedupe_key,severity,title,message,metric_value,threshold,active,first_triggered_at,last_triggered_at,resolved_at,updated_at)
   values(p_business_id,r.station,v_key,v_severity,v_title,v_message,v_metric,v_threshold,true,v_now,v_now,null,v_now)
   on conflict(business_id,dedupe_key) do update set severity=excluded.severity,title=excluded.title,message=excluded.message,metric_value=excluded.metric_value,threshold=excluded.threshold,active=true,last_triggered_at=v_now,resolved_at=null,updated_at=v_now;
  end if;
 end loop;
 update public.kds_operational_alerts set active=false,resolved_at=v_now,updated_at=v_now where business_id=p_business_id and active and not(dedupe_key=any(v_keys));
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'station',station,'severity',severity,'title',title,'message',message,'metric_value',metric_value,'threshold',threshold,'last_triggered_at',last_triggered_at) order by case severity when 'critical' then 0 else 1 end,last_triggered_at desc),'[]'::jsonb) into v_alert_data
 from public.kds_operational_alerts where business_id=p_business_id and active;
 return jsonb_build_object('stations',v_station_data,'alerts',v_alert_data);
end; $$;
create or replace function public.get_kds_operational_control(p_business_id uuid)
returns jsonb language sql security invoker set search_path=public as $$
select private.refresh_kds_operational_alerts(p_business_id); $$;
revoke all on function private.refresh_kds_operational_alerts(uuid) from public,anon;
grant execute on function private.refresh_kds_operational_alerts(uuid) to authenticated;
revoke all on function public.get_kds_operational_control(uuid) from public,anon;
grant execute on function public.get_kds_operational_control(uuid) to authenticated;