create or replace function private.sync_production_tickets(p_sale_id uuid)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  v_business uuid;
  v_uid uuid;
  v_station public.production_station;
  v_priority public.production_priority;
  v_target_seconds integer;
  v_required boolean;
begin
  v_uid:=auth.uid();

  select business_id, production_priority
    into v_business, v_priority
  from public.sales
  where id=p_sale_id;

  if v_business is null then
    raise exception 'Comanda não encontrada';
  end if;

  if not public.has_business_role(
    v_business,
    array['owner','manager','cashier','waiter']::public.member_role[]
  ) then
    raise exception 'Usuário sem permissão para enviar a comanda à produção';
  end if;

  for v_station in
    select distinct p.production_station
    from public.sale_items si
    join public.products p on p.id=si.product_id
    where si.sale_id=p_sale_id
      and p.production_station in (
        'kitchen'::public.production_station,
        'bar'::public.production_station
      )
    order by p.production_station
  loop
    select coalesce(max(p.prep_time_seconds),900)
      into v_target_seconds
    from public.sale_items si
    join public.products p on p.id=si.product_id
    where si.sale_id=p_sale_id
      and p.production_station=v_station;

    insert into public.production_tickets(
      business_id,sale_id,station,status,sent_at,priority,target_seconds
    )
    values(
      v_business,p_sale_id,v_station,'pending',now(),v_priority,v_target_seconds
    )
    on conflict (sale_id,station) do update
      set priority=case
        when public.production_tickets.status='pending' then excluded.priority
        else public.production_tickets.priority
      end,
      target_seconds=case
        when public.production_tickets.status='pending' then excluded.target_seconds
        else public.production_tickets.target_seconds
      end,
      updated_at=now();
  end loop;

  for v_station in
    select station
    from public.production_tickets
    where sale_id=p_sale_id
      and status='pending'
    order by station
  loop
    select exists(
      select 1
      from public.sale_items si
      join public.products p on p.id=si.product_id
      where si.sale_id=p_sale_id
        and p.production_station=v_station
    ) into v_required;

    if not v_required then
      update public.production_tickets
      set status='cancelled',
          cancelled_at=coalesce(cancelled_at,now()),
          updated_at=now()
      where sale_id=p_sale_id
        and station=v_station
        and status='pending';

      insert into public.audit_logs(
        business_id,user_id,action,entity,entity_id,new_data
      )
      select
        v_business,v_uid,'production_ticket_cancelled','production_ticket',pt.id,
        jsonb_build_object(
          'sale_id',pt.sale_id,
          'station',pt.station,
          'reason','Estação deixou de ser necessária após edição da comanda'
        )
      from public.production_tickets pt
      where pt.sale_id=p_sale_id
        and pt.station=v_station
        and pt.status='cancelled'
        and pt.cancelled_at is not null
        and pt.updated_at >= now()-interval '1 second';
    end if;
  end loop;
end;
$$;

revoke all on function private.sync_production_tickets(uuid) from public,anon;
grant execute on function private.sync_production_tickets(uuid) to authenticated;
