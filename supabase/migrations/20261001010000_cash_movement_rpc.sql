-- Urbana Café: transactional manual cash movements and security hardening.
create or replace function public.record_cash_movement(
  p_business_id uuid,
  p_cash_session_id uuid,
  p_movement_type public.cash_movement_type,
  p_amount numeric,
  p_description text default null
)
returns public.cash_movements
language plpgsql
security definer
set search_path=public
as $$
declare
  v_session public.cash_sessions%rowtype;
  v_amount numeric(14,2);
  v_signed numeric(14,2);
  v_result public.cash_movements%rowtype;
begin
  if not public.has_business_role(
    p_business_id,
    array['owner','manager','cashier']::public.member_role[]
  ) then
    raise exception 'Sem permissão para movimentar o caixa';
  end if;

  if p_movement_type not in ('deposit','withdrawal','adjustment') then
    raise exception 'Tipo de movimentação não permitido';
  end if;

  v_amount:=round(abs(coalesce(p_amount,0)),2);
  if v_amount<=0 then
    raise exception 'Valor deve ser maior que zero';
  end if;

  select *
  into v_session
  from public.cash_sessions
  where id=p_cash_session_id
    and business_id=p_business_id
    and status='open'
  for update;

  if not found then
    raise exception 'Sessão de caixa inválida ou fechada';
  end if;

  v_signed:=case
    when p_movement_type='withdrawal' then -v_amount
    else v_amount
  end;

  insert into public.cash_movements(
    business_id,cash_session_id,movement_type,amount,description,created_by
  )
  values(
    p_business_id,
    p_cash_session_id,
    p_movement_type,
    v_signed,
    nullif(trim(p_description),''),
    auth.uid()
  )
  returning * into v_result;

  return v_result;
end;
$$;

-- Fix cross-table status checks: sale_status and purchase status are different types.
create or replace function public.prevent_closed_or_posted_mutation()
returns trigger
language plpgsql
as $$
begin
  if tg_table_name='sales' then
    if old.status in ('completed','cancelled','refunded') then
      raise exception 'Venda finalizada não pode ser alterada';
    end if;
  elsif tg_table_name='purchases' then
    if old.status in ('posted','cancelled') then
      raise exception 'Compra lançada não pode ser alterada';
    end if;
  elsif tg_table_name='cash_sessions' then
    if old.status='closed' then
      raise exception 'Caixa fechado não pode ser alterado';
    end if;
  end if;

  return new;
end;
$$;

alter function public.record_cash_movement(uuid,uuid,public.cash_movement_type,numeric,text) set search_path=public;
alter function public.set_updated_at() set search_path=public;
alter function public.validate_sale_header_integrity() set search_path=public;
alter function public.validate_sale_item_integrity() set search_path=public;
alter function public.validate_purchase_integrity() set search_path=public;
alter function public.validate_recipe_item_integrity() set search_path=public;
alter function public.validate_product_category_integrity() set search_path=public;
alter function public.validate_purchase_supplier_integrity() set search_path=public;
alter function public.prevent_ledger_delete() set search_path=public;
alter function public.prevent_closed_or_posted_mutation() set search_path=public;
alter function public.normalize_sale_cash_movement() set search_path=public;

revoke all on function public.record_cash_movement(uuid,uuid,public.cash_movement_type,numeric,text) from public;
revoke all on function public.record_cash_movement(uuid,uuid,public.cash_movement_type,numeric,text) from anon;
grant execute on function public.record_cash_movement(uuid,uuid,public.cash_movement_type,numeric,text) to authenticated;

revoke all on function public.create_sale_transaction(uuid,uuid,uuid,uuid,text,public.payment_method,jsonb,numeric) from public;
revoke all on function public.create_sale_transaction(uuid,uuid,uuid,uuid,text,public.payment_method,jsonb,numeric) from anon;
grant execute on function public.create_sale_transaction(uuid,uuid,uuid,uuid,text,public.payment_method,jsonb,numeric) to authenticated;

revoke all on function public.finalize_sale(uuid,uuid) from public;
revoke all on function public.finalize_sale(uuid,uuid) from anon;
grant execute on function public.finalize_sale(uuid,uuid) to authenticated;

revoke all on function public.post_purchase(uuid) from public;
revoke all on function public.post_purchase(uuid) from anon;
grant execute on function public.post_purchase(uuid) to authenticated;

revoke all on function public.record_expense(uuid,text,text,numeric,date,public.payment_method) from public;
revoke all on function public.record_expense(uuid,text,text,numeric,date,public.payment_method) from anon;
grant execute on function public.record_expense(uuid,text,text,numeric,date,public.payment_method) to authenticated;

revoke all on function public.setup_business(text,text,text) from public;
revoke all on function public.setup_business(text,text,text) from anon;
grant execute on function public.setup_business(text,text,text) to authenticated;
