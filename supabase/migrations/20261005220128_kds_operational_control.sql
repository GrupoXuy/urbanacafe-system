do $$
begin
  create type public.production_priority as enum ('low','normal','high','urgent');
exception
  when duplicate_object then null;
end $$;

alter table public.products
  add column if not exists prep_time_seconds integer not null default 900;

alter table public.products
  drop constraint if exists products_prep_time_seconds_check;

alter table public.products
  add constraint products_prep_time_seconds_check
  check (prep_time_seconds between 30 and 7200);

alter table public.sales
  add column if not exists production_priority public.production_priority not null default 'normal';

alter table public.production_tickets
  add column if not exists priority public.production_priority not null default 'normal',
  add column if not exists target_seconds integer not null default 900;

alter table public.production_tickets
  drop constraint if exists production_tickets_target_seconds_check;

alter table public.production_tickets
  add constraint production_tickets_target_seconds_check
  check (target_seconds between 30 and 7200);

create index if not exists production_tickets_operational_queue_idx
  on public.production_tickets (business_id, station, status, priority, sent_at);

create index if not exists production_tickets_metrics_idx
  on public.production_tickets (business_id, station, status, sent_at, started_at, ready_at, served_at);

create index if not exists sales_production_priority_idx
  on public.sales (business_id, production_priority, created_at);

create or replace function private.set_production_ticket_priority(
  p_ticket_id uuid,
  p_priority public.production_priority
)
returns public.production_tickets
language plpgsql
security definer
set search_path=''
as $$
declare
  v_ticket public.production_tickets%rowtype;
  v_old public.production_priority;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado';
  end if;

  select * into v_ticket
  from public.production_tickets
  where id=p_ticket_id
  for update;

  if not found then
    raise exception 'Ticket de produção não encontrado';
  end if;

  if not public.has_business_role(
    v_ticket.business_id,
    array['owner','manager','cashier','waiter']::public.member_role[]
  ) then
    raise exception 'Usuário sem permissão para priorizar produção';
  end if;

  if v_ticket.status in ('served','cancelled') then
    raise exception 'Ticket encerrado não pode ter prioridade alterada';
  end if;

  v_old:=v_ticket.priority;

  update public.production_tickets
  set priority=p_priority,
      updated_at=now()
  where id=p_ticket_id
  returning * into v_ticket;

  insert into public.audit_logs(
    business_id,user_id,action,entity,entity_id,old_data,new_data
  )
  values(
    v_ticket.business_id,
    auth.uid(),
    'production_priority_changed',
    'production_ticket',
    v_ticket.id,
    jsonb_build_object('priority',v_old),
    jsonb_build_object(
      'priority',v_ticket.priority,
      'station',v_ticket.station,
      'sale_id',v_ticket.sale_id
    )
  );

  return v_ticket;
end;
$$;

create or replace function public.set_production_ticket_priority(
  p_ticket_id uuid,
  p_priority public.production_priority
)
returns public.production_tickets
language sql
security invoker
set search_path=public
as $$
  select private.set_production_ticket_priority(p_ticket_id,p_priority);
$$;

revoke all on function private.set_production_ticket_priority(uuid,public.production_priority) from public,anon;
grant execute on function private.set_production_ticket_priority(uuid,public.production_priority) to authenticated;
revoke all on function public.set_production_ticket_priority(uuid,public.production_priority) from public,anon;
grant execute on function public.set_production_ticket_priority(uuid,public.production_priority) to authenticated;

create or replace function private.get_kds_metrics(
  p_business_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado';
  end if;

  if not public.has_business_role(
    p_business_id,
    array['owner','manager','cashier','waiter','stockkeeper','analyst']::public.member_role[]
  ) then
    raise exception 'Usuário sem acesso aos indicadores do KDS';
  end if;

  with scoped as (
    select
      pt.*,
      extract(epoch from (coalesce(pt.started_at, now()) - pt.sent_at))::numeric as wait_seconds,
      extract(epoch from (coalesce(pt.ready_at, now()) - coalesce(pt.started_at, pt.sent_at)))::numeric as prep_seconds,
      extract(epoch from (coalesce(pt.served_at, now()) - pt.sent_at))::numeric as total_seconds
    from public.production_tickets pt
    where pt.business_id=p_business_id
      and pt.sent_at >= p_from
      and pt.sent_at < p_to
  ),
  active as (
    select * from scoped where status in ('pending','preparing','ready')
  ),
  served as (
    select * from scoped where status='served'
  ),
  station_stats as (
    select jsonb_agg(
      jsonb_build_object(
        'station', station,
        'active', active_count,
        'pending', pending_count,
        'preparing', preparing_count,
        'ready', ready_count,
        'delayed', delayed_count,
        'served', served_count,
        'avg_wait_seconds', round(avg_wait,1),
        'avg_prep_seconds', round(avg_prep,1),
        'avg_total_seconds', round(avg_total,1)
      ) order by station
    ) as data
    from (
      select
        station,
        count(*) filter (where status in ('pending','preparing','ready')) as active_count,
        count(*) filter (where status='pending') as pending_count,
        count(*) filter (where status='preparing') as preparing_count,
        count(*) filter (where status='ready') as ready_count,
        count(*) filter (
          where status in ('pending','preparing')
            and now() > (
              case
                when status='pending' then sent_at + make_interval(secs => target_seconds)
                else started_at + make_interval(secs => target_seconds)
              end
            )
        ) as delayed_count,
        count(*) filter (where status='served') as served_count,
        coalesce(avg(wait_seconds) filter (where status='served'),0) as avg_wait,
        coalesce(avg(prep_seconds) filter (where status='served'),0) as avg_prep,
        coalesce(avg(total_seconds) filter (where status='served'),0) as avg_total
      from scoped
      group by station
    ) x
  )
  select jsonb_build_object(
    'period', jsonb_build_object('from',p_from,'to',p_to),
    'active', (select count(*) from active),
    'pending', (select count(*) from active where status='pending'),
    'preparing', (select count(*) from active where status='preparing'),
    'ready', (select count(*) from active where status='ready'),
    'delayed', (
      select count(*) from active
      where status in ('pending','preparing')
        and now() > (
          case
            when status='pending' then sent_at + make_interval(secs => target_seconds)
            else started_at + make_interval(secs => target_seconds)
          end
        )
    ),
    'served', (select count(*) from served),
    'avg_wait_seconds', coalesce((select avg(wait_seconds) from served),0),
    'avg_prep_seconds', coalesce((select avg(prep_seconds) from served),0),
    'avg_total_seconds', coalesce((select avg(total_seconds) from served),0),
    'throughput_per_hour',
      case
        when extract(epoch from (p_to-p_from)) > 0
        then round((select count(*)::numeric from served) / (extract(epoch from (p_to-p_from))/3600),1)
        else 0
      end,
    'stations', coalesce((select data from station_stats),'[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

create or replace function public.get_kds_metrics(
  p_business_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
returns jsonb
language sql
security invoker
set search_path=public
as $$
  select private.get_kds_metrics(p_business_id,p_from,p_to);
$$;

revoke all on function private.get_kds_metrics(uuid,timestamptz,timestamptz) from public,anon;
grant execute on function private.get_kds_metrics(uuid,timestamptz,timestamptz) to authenticated;
revoke all on function public.get_kds_metrics(uuid,timestamptz,timestamptz) from public,anon;
grant execute on function public.get_kds_metrics(uuid,timestamptz,timestamptz) to authenticated;

alter publication supabase_realtime add table public.production_tickets;
