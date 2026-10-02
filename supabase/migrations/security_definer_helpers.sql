-- Urbana Café: move authorization lookup helpers behind a non-exposed schema.
-- Public wrappers remain SECURITY INVOKER so RLS policies keep their normal caller context.

create schema if not exists private;

create or replace function private.is_business_member(target_business uuid)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select exists(
    select 1
    from public.business_memberships m
    where m.business_id=target_business
      and m.user_id=auth.uid()
      and m.active
  );
$$;

create or replace function private.has_business_role(
  target_business uuid,
  allowed public.member_role[]
)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select exists(
    select 1
    from public.business_memberships m
    where m.business_id=target_business
      and m.user_id=auth.uid()
      and m.active
      and m.role=any(allowed)
  );
$$;

revoke all on schema private from public;
revoke all on schema private from anon;
grant usage on schema private to authenticated;

revoke all on function private.is_business_member(uuid) from public;
revoke all on function private.is_business_member(uuid) from anon;
grant execute on function private.is_business_member(uuid) to authenticated;

revoke all on function private.has_business_role(uuid,public.member_role[]) from public;
revoke all on function private.has_business_role(uuid,public.member_role[]) from anon;
grant execute on function private.has_business_role(uuid,public.member_role[]) to authenticated;

create or replace function public.is_business_member(target_business uuid)
returns boolean
language sql
stable
security invoker
set search_path=public
as $$
  select private.is_business_member(target_business);
$$;

create or replace function public.has_business_role(
  target_business uuid,
  allowed public.member_role[]
)
returns boolean
language sql
stable
security invoker
set search_path=public
as $$
  select private.has_business_role(target_business, allowed);
$$;

revoke all on function public.is_business_member(uuid) from public;
revoke all on function public.is_business_member(uuid) from anon;
grant execute on function public.is_business_member(uuid) to authenticated;

revoke all on function public.has_business_role(uuid,public.member_role[]) from public;
revoke all on function public.has_business_role(uuid,public.member_role[]) from anon;
grant execute on function public.has_business_role(uuid,public.member_role[]) to authenticated;
