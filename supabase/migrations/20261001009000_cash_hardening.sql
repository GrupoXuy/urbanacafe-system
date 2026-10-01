-- Urbana Café: cash opening/closing hardening.
create unique index if not exists ux_cash_sessions_one_open_per_business
  on public.cash_sessions(business_id)
  where status='open';

create or replace function public.open_cash_session(
  p_business_id uuid,
  p_opening_amount numeric
)
returns public.cash_sessions
language plpgsql
security definer
set search_path=public
as $$
declare
  v_result public.cash_sessions;
  v_opening numeric(14,2);
begin
  if not public.has_business_role(
    p_business_id,
    array['owner','manager','cashier']::public.member_role[]
  ) then
    raise exception 'Sem permissão';
  end if;

  v_opening:=round(coalesce(p_opening_amount,0),2);

  if v_opening<0 then
    raise exception 'Valor inicial não pode ser negativo';
  end if;

  if exists(
    select 1 from public.cash_sessions
    where business_id=p_business_id
      and status='open'
  ) then
    raise exception 'Já existe um caixa aberto';
  end if;

  insert into public.cash_sessions(
    business_id,opened_by,opening_amount
  )
  values(
    p_business_id,auth.uid(),v_opening
  )
  returning * into v_result;

  if v_opening<>0 then
    insert into public.cash_movements(
      business_id,cash_session_id,movement_type,amount,description,created_by
    )
    values(
      p_business_id,v_result.id,'deposit',v_opening,'Abertura de caixa',auth.uid()
    );
  end if;

  return v_result;
end;
$$;

create or replace function public.close_cash_session(
  p_session_id uuid,
  p_counted_amount numeric,
  p_note text default null
)
returns public.cash_sessions
language plpgsql
security definer
set search_path=public
as $$
declare
  v_result public.cash_sessions;
  v_expected numeric(14,2);
  v_counted numeric(14,2);
begin
  select *
  into v_result
  from public.cash_sessions
  where id=p_session_id
  for update;

  if not found then
    raise exception 'Caixa não encontrado';
  end if;

  if not public.has_business_role(
    v_result.business_id,
    array['owner','manager','cashier']::public.member_role[]
  ) then
    raise exception 'Sem permissão';
  end if;

  if v_result.status<>'open' then
    raise exception 'Caixa já está fechado';
  end if;

  v_counted:=round(coalesce(p_counted_amount,0),2);
  if v_counted<0 then
    raise exception 'Valor contado não pode ser negativo';
  end if;

  select round(coalesce(sum(amount),0),2)
  into v_expected
  from public.cash_movements
  where cash_session_id=p_session_id;

  update public.cash_sessions
  set status='closed',
      closed_by=auth.uid(),
      closed_at=now(),
      expected_amount=v_expected,
      counted_amount=v_counted,
      difference=round(v_counted-v_expected,2),
      closing_note=nullif(trim(p_note),'')
  where id=p_session_id
  returning * into v_result;

  return v_result;
end;
$$;

revoke all on function public.open_cash_session(uuid,numeric) from public;
revoke all on function public.open_cash_session(uuid,numeric) from anon;
grant execute on function public.open_cash_session(uuid,numeric) to authenticated;

revoke all on function public.close_cash_session(uuid,numeric,text) from public;
revoke all on function public.close_cash_session(uuid,numeric,text) from anon;
grant execute on function public.close_cash_session(uuid,numeric,text) to authenticated;
