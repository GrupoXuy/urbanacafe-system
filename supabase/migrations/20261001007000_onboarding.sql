-- Self-service onboarding for a new business tenant.
create or replace function public.setup_business(
  p_name text,
  p_legal_name text default null,
  p_full_name text default null
)
returns public.businesses
language plpgsql
security definer
set search_path=public
as $$
declare
  v_business public.businesses;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado';
  end if;

  if exists(
    select 1 from public.business_memberships
    where user_id=auth.uid() and active
  ) then
    raise exception 'Usuário já possui um negócio ativo';
  end if;

  if nullif(trim(p_name),'') is null then
    raise exception 'Nome do negócio é obrigatório';
  end if;

  -- Reuse the seeded/orphan business when it has no memberships.
  select b.*
  into v_business
  from public.businesses b
  where lower(b.name)=lower(trim(p_name))
    and b.active
    and not exists(
      select 1 from public.business_memberships m
      where m.business_id=b.id and m.active
    )
  order by b.created_at
  limit 1
  for update;

  if not found then
    insert into public.businesses(name,legal_name,currency,timezone)
    values(trim(p_name),nullif(trim(p_legal_name),''),'UYU','America/Montevideo')
    returning * into v_business;
  else
    update public.businesses
    set legal_name=coalesce(nullif(trim(p_legal_name),''),legal_name),
        updated_at=now()
    where id=v_business.id
    returning * into v_business;
  end if;

  insert into public.profiles(id,full_name,active)
  values(auth.uid(),nullif(trim(p_full_name),''),true)
  on conflict(id) do update
  set full_name=coalesce(excluded.full_name,public.profiles.full_name),
      active=true,
      updated_at=now();

  insert into public.business_memberships(business_id,user_id,role,active)
  values(v_business.id,auth.uid(),'owner',true);

  insert into public.categories(business_id,name)
  values
    (v_business.id,'Bebidas'),
    (v_business.id,'Comidas'),
    (v_business.id,'Insumos')
  on conflict(business_id,name) do nothing;

  return v_business;
end;
$$;

revoke all on function public.setup_business(text,text,text) from public;
revoke all on function public.setup_business(text,text,text) from anon;
grant execute on function public.setup_business(text,text,text) to authenticated;
