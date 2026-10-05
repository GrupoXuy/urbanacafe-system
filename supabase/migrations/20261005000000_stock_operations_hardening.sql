-- Urbana Café: protect product stock balance and expose transactional stock operations.
-- Direct clients can read stock, but balance changes must be represented in the stock ledger.

create or replace function private.prevent_direct_stock_balance_mutation()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  if tg_op='INSERT' then
    if new.stock_quantity<>0
       and current_user<>'postgres' then
      raise exception 'Saldo inicial de estoque deve ser zero; registre a entrada como movimento de estoque';
    end if;
  elsif new.stock_quantity is distinct from old.stock_quantity
        and current_user<>'postgres' then
    raise exception 'Saldo de estoque só pode ser alterado por operação transacional';
  end if;

  return new;
end;
$$;

drop trigger if exists products_stock_balance_guard on public.products;

create trigger products_stock_balance_guard
before insert or update of stock_quantity
on public.products
for each row
execute function private.prevent_direct_stock_balance_mutation();

create or replace function private.change_stock_transaction(
  p_product_id uuid,
  p_delta numeric,
  p_movement_type public.stock_movement_type,
  p_note text default null
)
returns public.products
language plpgsql
security definer
set search_path=''
as $$
declare
  v_product public.products%rowtype;
  v_movement public.stock_movements%rowtype;
  v_delta numeric(14,3);
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado';
  end if;

  if p_delta is null or p_delta=0 then
    raise exception 'A quantidade do movimento deve ser diferente de zero';
  end if;

  if p_movement_type not in (
    'adjustment'::public.stock_movement_type,
    'waste'::public.stock_movement_type
  ) then
    raise exception 'Tipo de movimento não permitido nesta operação';
  end if;

  if not exists (
    select 1
    from public.businesses b
    join public.business_memberships m
      on m.business_id=b.id
     and m.user_id=auth.uid()
     and m.active
    where b.id=(select business_id from public.products where id=p_product_id)
      and b.active
      and m.role=any(array['owner','manager','stockkeeper']::public.member_role[])
  ) then
    raise exception 'Sem permissão para movimentar este estoque';
  end if;

  if p_movement_type='waste' then
    if p_delta>=0 then
      raise exception 'Perda deve reduzir o estoque';
    end if;
    v_delta:=p_delta::numeric(14,3);
  else
    v_delta:=p_delta::numeric(14,3);
  end if;

  select *
  into v_product
  from public.products
  where id=p_product_id
  for update;

  if not found then
    raise exception 'Produto não encontrado';
  end if;

  if not v_product.is_stock_item then
    raise exception 'Produto não possui controle de estoque';
  end if;

  if not v_product.active then
    raise exception 'Produto inativo não pode receber movimentação';
  end if;

  if v_product.stock_quantity+v_delta<0 then
    raise exception 'Movimento resultaria em estoque negativo';
  end if;

  update public.products
  set stock_quantity=stock_quantity+v_delta,
      updated_at=now()
  where id=v_product.id;

  insert into public.stock_movements(
    business_id,
    product_id,
    movement_type,
    quantity,
    unit_cost,
    note,
    created_by
  )
  values(
    v_product.business_id,
    v_product.id,
    p_movement_type,
    v_delta,
    v_product.average_cost,
    nullif(trim(coalesce(p_note,'')), ''),
    auth.uid()
  )
  returning * into v_movement;

  insert into public.audit_logs(
    business_id,
    user_id,
    action,
    entity,
    entity_id,
    new_data
  )
  values(
    v_product.business_id,
    auth.uid(),
    case when p_movement_type='waste' then 'stock_waste' else 'stock_adjustment' end,
    'stock_movement',
    v_movement.id,
    jsonb_build_object(
      'product_id',v_product.id,
      'product_name',v_product.name,
      'movement_type',p_movement_type,
      'quantity',v_delta,
      'unit_cost',v_product.average_cost,
      'note',nullif(trim(coalesce(p_note,'')), ''),
      'stock_before',v_product.stock_quantity,
      'stock_after',v_product.stock_quantity+v_delta
    )
  );

  return (
    select p
    from public.products p
    where p.id=v_product.id
  );
end;
$$;

create or replace function private.set_stock_count_transaction(
  p_product_id uuid,
  p_counted_quantity numeric,
  p_note text default null
)
returns public.products
language plpgsql
security definer
set search_path=''
as $$
declare
  v_product public.products%rowtype;
  v_delta numeric(14,3);
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado';
  end if;

  if p_counted_quantity is null or p_counted_quantity<0 then
    raise exception 'Contagem física inválida';
  end if;

  select *
  into v_product
  from public.products
  where id=p_product_id
  for update;

  if not found then
    raise exception 'Produto não encontrado';
  end if;

  if not v_product.is_stock_item then
    raise exception 'Produto não possui controle de estoque';
  end if;

  if not v_product.active then
    raise exception 'Produto inativo não pode ser contado';
  end if;

  if not exists (
    select 1
    from public.business_memberships m
    join public.businesses b on b.id=m.business_id
    where m.business_id=v_product.business_id
      and m.user_id=auth.uid()
      and m.active
      and b.active
      and m.role=any(array['owner','manager','stockkeeper']::public.member_role[])
  ) then
    raise exception 'Sem permissão para lançar inventário físico';
  end if;

  v_delta:=(p_counted_quantity::numeric(14,3)-v_product.stock_quantity);

  if v_delta=0 then
    return v_product;
  end if;

  return private.change_stock_transaction(
    v_product.id,
    v_delta,
    'adjustment'::public.stock_movement_type,
    coalesce(nullif(trim(coalesce(p_note,'')),''),'Ajuste por inventário físico')
  );
end;
$$;

create or replace function public.record_stock_adjustment(
  p_product_id uuid,
  p_delta numeric,
  p_note text default null
)
returns public.products
language sql
security invoker
set search_path=public
as $$
  select private.change_stock_transaction(
    p_product_id,
    p_delta,
    'adjustment'::public.stock_movement_type,
    p_note
  );
$$;

create or replace function public.record_stock_waste(
  p_product_id uuid,
  p_quantity numeric,
  p_note text default null
)
returns public.products
language sql
security invoker
set search_path=public
as $$
  select private.change_stock_transaction(
    p_product_id,
    -abs(p_quantity),
    'waste'::public.stock_movement_type,
    p_note
  );
$$;

create or replace function public.set_stock_count(
  p_product_id uuid,
  p_counted_quantity numeric,
  p_note text default null
)
returns public.products
language sql
security invoker
set search_path=public
as $$
  select private.set_stock_count_transaction(
    p_product_id,
    p_counted_quantity,
    p_note
  );
$$;

revoke all on function private.change_stock_transaction(uuid,numeric,public.stock_movement_type,text) from public;
revoke all on function private.change_stock_transaction(uuid,numeric,public.stock_movement_type,text) from anon;
grant execute on function private.change_stock_transaction(uuid,numeric,public.stock_movement_type,text) to authenticated;

revoke all on function private.set_stock_count_transaction(uuid,numeric,text) from public;
revoke all on function private.set_stock_count_transaction(uuid,numeric,text) from anon;
grant execute on function private.set_stock_count_transaction(uuid,numeric,text) to authenticated;

revoke all on function public.record_stock_adjustment(uuid,numeric,text) from public;
revoke all on function public.record_stock_adjustment(uuid,numeric,text) from anon;
grant execute on function public.record_stock_adjustment(uuid,numeric,text) to authenticated;

revoke all on function public.record_stock_waste(uuid,numeric,text) from public;
revoke all on function public.record_stock_waste(uuid,numeric,text) from anon;
grant execute on function public.record_stock_waste(uuid,numeric,text) to authenticated;

revoke all on function public.set_stock_count(uuid,numeric,text) from public;
revoke all on function public.set_stock_count(uuid,numeric,text) from anon;
grant execute on function public.set_stock_count(uuid,numeric,text) to authenticated;
