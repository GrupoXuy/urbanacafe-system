-- Urbana Café: concurrency-safe reservation lifecycle.
-- Exact time slots are unique per table; cancelled reservations release the slot.

create unique index if not exists uq_reservations_business_table_time_active
on public.reservations (business_id,table_id,reservation_at)
where table_id is not null and status <> 'cancelled';

create or replace function public.create_reservation_transaction(
  p_business_id uuid,
  p_customer_id uuid default null,
  p_table_id uuid default null,
  p_reservation_at timestamptz default null,
  p_party_size integer default 2,
  p_notes text default null
)
returns public.reservations
language plpgsql
security definer
set search_path=public
as $$
declare
  v_reservation public.reservations%rowtype;
  v_customer_business uuid;
  v_table_business uuid;
  v_table_seats integer;
begin
  if not public.has_business_role(
    p_business_id,
    array['owner','manager','cashier','waiter']::public.member_role[]
  ) then
    raise exception 'Sem permissão para registrar reservas';
  end if;

  if not exists (
    select 1 from public.businesses
    where id=p_business_id and active
  ) then
    raise exception 'Negócio inválido ou inativo';
  end if;

  if p_reservation_at is null or p_reservation_at <= now() then
    raise exception 'Data e hora da reserva devem ser futuras';
  end if;

  if p_party_size is null or p_party_size <= 0 then
    raise exception 'Quantidade de pessoas deve ser maior que zero';
  end if;

  if p_customer_id is not null then
    select business_id
    into v_customer_business
    from public.customers
    where id=p_customer_id and active
    for update;

    if not found or v_customer_business<>p_business_id then
      raise exception 'Cliente inválido ou pertence a outro negócio';
    end if;
  end if;

  if p_table_id is not null then
    select business_id,seats
    into v_table_business,v_table_seats
    from public.cafe_tables
    where id=p_table_id and active
    for update;

    if not found or v_table_business<>p_business_id then
      raise exception 'Mesa inválida ou pertence a outro negócio';
    end if;

    if v_table_seats is not null and p_party_size>v_table_seats then
      raise exception 'A mesa selecionada não comporta a quantidade de pessoas';
    end if;
  end if;

  if p_table_id is not null and exists (
    select 1
    from public.reservations r
    where r.business_id=p_business_id
      and r.table_id=p_table_id
      and r.reservation_at=p_reservation_at
      and r.status<>'cancelled'
  ) then
    raise exception 'A mesa já está reservada para este horário';
  end if;

  insert into public.reservations(
    business_id,customer_id,table_id,reservation_at,party_size,status,notes
  )
  values(
    p_business_id,p_customer_id,p_table_id,p_reservation_at,p_party_size,'pending',
    nullif(trim(coalesce(p_notes,'')),'')
  )
  returning * into v_reservation;

  return v_reservation;
exception
  when unique_violation then
    raise exception 'A mesa já está reservada para este horário';
end;
$$;

create or replace function public.update_reservation_status(
  p_reservation_id uuid,
  p_status text
)
returns public.reservations
language plpgsql
security definer
set search_path=public
as $$
declare
  v_reservation public.reservations%rowtype;
  v_allowed boolean := false;
begin
  select * into v_reservation
  from public.reservations
  where id=p_reservation_id
  for update;

  if not found then
    raise exception 'Reserva não encontrada';
  end if;

  if not public.has_business_role(
    v_reservation.business_id,
    array['owner','manager','cashier','waiter']::public.member_role[]
  ) then
    raise exception 'Sem permissão para alterar esta reserva';
  end if;

  v_allowed :=
       (v_reservation.status='pending' and p_status in ('confirmed','cancelled'))
    or (v_reservation.status='confirmed' and p_status in ('seated','cancelled'))
    or (v_reservation.status='seated' and p_status in ('completed','cancelled'));

  if not v_allowed then
    raise exception 'Transição de status inválida';
  end if;

  update public.reservations
  set status=p_status
  where id=p_reservation_id
  returning * into v_reservation;

  return v_reservation;
end;
$$;

revoke all on function public.create_reservation_transaction(uuid,uuid,uuid,timestamptz,integer,text) from public;
revoke all on function public.create_reservation_transaction(uuid,uuid,uuid,timestamptz,integer,text) from anon;
grant execute on function public.create_reservation_transaction(uuid,uuid,uuid,timestamptz,integer,text) to authenticated;

revoke all on function public.update_reservation_status(uuid,text) from public;
revoke all on function public.update_reservation_status(uuid,text) from anon;
grant execute on function public.update_reservation_status(uuid,text) to authenticated;

drop policy if exists reservations_access on public.reservations;
drop policy if exists reservations_read on public.reservations;
create policy reservations_read on public.reservations
for select to authenticated
using ((select public.is_business_member(business_id)));
