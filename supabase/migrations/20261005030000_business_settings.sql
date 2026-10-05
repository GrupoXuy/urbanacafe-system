-- Urbana Café: transactional business settings.
-- The public RPC is SECURITY INVOKER; privileged validation/update stays private.

create or replace function private.update_business_settings_transaction(
  p_business_id uuid,
  p_name text,
  p_legal_name text default null,
  p_currency text default 'UYU',
  p_timezone text default 'America/Montevideo'
)
returns public.businesses
language plpgsql
security definer
set search_path=''
as $$
declare
  v_business public.businesses%rowtype;
  v_name text;
  v_legal_name text;
  v_currency text;
  v_timezone text;
  v_old_name text;
  v_old_legal_name text;
  v_old_currency text;
  v_old_timezone text;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado';
  end if;

  v_name:=nullif(trim(coalesce(p_name,'')),'');
  v_legal_name:=nullif(trim(coalesce(p_legal_name,'')),'');
  v_currency:=upper(trim(coalesce(p_currency,'')));
  v_timezone:=trim(coalesce(p_timezone,''));

  if v_name is null then
    raise exception 'Nome do negócio é obrigatório';
  end if;

  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Moeda deve usar código de 3 letras';
  end if;

  if v_timezone='' or not exists (
    select 1
    from pg_catalog.pg_timezone_names
    where name=v_timezone
  ) then
    raise exception 'Fuso horário inválido';
  end if;

  select *
    into v_business
  from public.businesses
  where id=p_business_id
    and active
  for update;

  if not found then
    raise exception 'Negócio não encontrado ou inativo';
  end if;

  v_old_name:=v_business.name;
  v_old_legal_name:=v_business.legal_name;
  v_old_currency:=v_business.currency;
  v_old_timezone:=v_business.timezone;

  if not exists (
    select 1
    from public.business_memberships m
    where m.business_id=v_business.id
      and m.user_id=auth.uid()
      and m.active
      and m.role=any(array['owner','manager']::public.member_role[])
  ) then
    raise exception 'Sem permissão para alterar as configurações do negócio';
  end if;

  update public.businesses
  set name=v_name,
      legal_name=v_legal_name,
      currency=v_currency,
      timezone=v_timezone,
      updated_at=now()
  where id=v_business.id
  returning * into v_business;

  insert into public.audit_logs(
    business_id,user_id,action,entity,entity_id,old_data,new_data
  )
  values(
    v_business.id,
    auth.uid(),
    'business_settings_update',
    'business',
    v_business.id,
    jsonb_build_object(
      'name',v_old_name,
      'legal_name',v_old_legal_name,
      'currency',v_old_currency,
      'timezone',v_old_timezone
    ),
    jsonb_build_object(
      'name',v_name,
      'legal_name',v_legal_name,
      'currency',v_currency,
      'timezone',v_timezone
    )
  );

  return v_business;
end;
$$;

revoke all on function private.update_business_settings_transaction(uuid,text,text,text,text) from public;
revoke all on function private.update_business_settings_transaction(uuid,text,text,text,text) from anon;
grant execute on function private.update_business_settings_transaction(uuid,text,text,text,text) to authenticated;

create or replace function public.update_business_settings(
  p_business_id uuid,
  p_name text,
  p_legal_name text default null,
  p_currency text default 'UYU',
  p_timezone text default 'America/Montevideo'
)
returns public.businesses
language sql
security invoker
set search_path=public
as $$
  select private.update_business_settings_transaction(
    p_business_id,p_name,p_legal_name,p_currency,p_timezone
  );
$$;

revoke all on function public.update_business_settings(uuid,text,text,text,text) from public;
revoke all on function public.update_business_settings(uuid,text,text,text,text) from anon;
grant execute on function public.update_business_settings(uuid,text,text,text,text) to authenticated;
