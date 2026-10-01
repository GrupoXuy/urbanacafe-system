-- Urbana Café: hardened transactional RPCs and profile access.

-- ---------------------------------------------------------------------------
-- Profile access for managers/owners
-- ---------------------------------------------------------------------------
create policy profiles_staff_read on public.profiles
for select to authenticated
using (
  id=auth.uid()
  or exists (
    select 1
    from public.business_memberships target
    where target.user_id=profiles.id
      and target.active
      and exists (
        select 1
        from public.business_memberships viewer
        where viewer.business_id=target.business_id
          and viewer.user_id=auth.uid()
          and viewer.active
          and viewer.role=any(array['owner','manager']::public.member_role[])
      )
  )
);

-- ---------------------------------------------------------------------------
-- Draft records remain editable; posted records remain immutable.
-- ---------------------------------------------------------------------------
create or replace function public.prevent_ledger_delete()
returns trigger
language plpgsql
as $$
declare
  v_status text;
begin
  if tg_table_name='sale_items' or tg_table_name='sale_payments' then
    select status::text into v_status from public.sales where id=old.sale_id;
    if v_status='open' then return old; end if;
  elsif tg_table_name='sales' then
    if old.status='open' then return old; end if;
  elsif tg_table_name='purchase_items' then
    select status into v_status from public.purchases where id=old.purchase_id;
    if v_status='draft' then return old; end if;
  elsif tg_table_name='purchases' then
    if old.status='draft' then return old; end if;
  end if;

  raise exception 'Registro operacional/financeiro lançado não pode ser apagado; use cancelamento ou ajuste compensatório';
end;
$$;

-- ---------------------------------------------------------------------------
-- Finalize sale atomically.
-- ---------------------------------------------------------------------------
create or replace function public.finalize_sale(
  p_sale_id uuid,
  p_cash_session_id uuid
)
returns public.sales
language plpgsql
security definer
set search_path=public
as $$
declare
  v_sale public.sales%rowtype;
  v_business uuid;
  v_total numeric(14,2);
  v_paid numeric(14,2);
  v_cogs numeric(14,2) := 0;
  v_item record;
  v_recipe record;
  v_required numeric(14,3);
  v_available numeric(14,3);
  v_item_cogs numeric(14,4);
  v_avg_cost numeric(14,4);
begin
  select *
  into v_sale
  from public.sales
  where id=p_sale_id
  for update;

  if not found then raise exception 'Venda não encontrada'; end if;

  v_business := v_sale.business_id;

  if not public.has_business_role(
    v_business,
    array['owner','manager','cashier','waiter']::public.member_role[]
  ) then
    raise exception 'Usuário sem permissão para finalizar esta venda';
  end if;

  if v_sale.status<>'open' then
    raise exception 'Somente vendas abertas podem ser finalizadas';
  end if;

  if v_sale.discount<0 then
    raise exception 'Desconto inválido';
  end if;

  select round(coalesce(sum(line_total),0),2)
  into v_total
  from public.sale_items
  where sale_id=p_sale_id;

  if v_sale.discount>v_total then
    raise exception 'Desconto maior que o subtotal';
  end if;

  v_total := round(v_total-v_sale.discount,2);

  select round(coalesce(sum(amount),0),2)
  into v_paid
  from public.sale_payments
  where sale_id=p_sale_id;

  if v_paid<>v_total then
    raise exception 'Pagamento insuficiente ou divergente: esperado %, recebido %',v_total,v_paid;
  end if;

  if p_cash_session_id is null then
    raise exception 'Caixa aberto é obrigatório';
  end if;

  if not exists (
    select 1
    from public.cash_sessions
    where id=p_cash_session_id
      and business_id=v_business
      and status='open'
  ) then
    raise exception 'Sessão de caixa inválida ou fechada';
  end if;

  for v_item in
    select
      si.id,
      si.product_id,
      si.quantity,
      p.name,
      p.stock_quantity,
      p.average_cost,
      p.is_stock_item,
      p.business_id
    from public.sale_items si
    join public.products p on p.id=si.product_id
    where si.sale_id=p_sale_id
    for update of si
  loop
    if v_item.business_id<>v_business then
      raise exception 'Produto pertence a outro negócio';
    end if;

    v_item_cogs := 0;

    if exists (
      select 1 from public.recipes r
      where r.product_id=v_item.product_id
        and r.business_id=v_business
        and r.active
    ) then
      for v_recipe in
        select
          ri.ingredient_product_id,
          (ri.quantity/r.yield_quantity)*v_item.quantity as required_qty
        from public.recipes r
        join public.recipe_items ri on ri.recipe_id=r.id
        where r.product_id=v_item.product_id
          and r.business_id=v_business
          and r.active
      loop
        select stock_quantity,average_cost
        into v_available,v_avg_cost
        from public.products
        where id=v_recipe.ingredient_product_id
          and business_id=v_business
        for update;

        if not found then
          raise exception 'Ingrediente não encontrado ou pertence a outro negócio';
        end if;

        v_required := v_recipe.required_qty;

        if v_available<v_required then
          raise exception 'Estoque insuficiente para o ingrediente %',v_recipe.ingredient_product_id;
        end if;

        v_item_cogs := v_item_cogs + (v_required*v_avg_cost);

        update public.products
        set stock_quantity=stock_quantity-v_required,
            updated_at=now()
        where id=v_recipe.ingredient_product_id;

        insert into public.stock_movements(
          business_id,product_id,movement_type,quantity,unit_cost,reference_id,created_by
        )
        values(
          v_business,v_recipe.ingredient_product_id,'sale',
          -v_required,v_avg_cost,p_sale_id,auth.uid()
        );
      end loop;
    else
      v_item_cogs := v_item.quantity*v_item.average_cost;

      if v_item.is_stock_item then
        if v_item.stock_quantity<v_item.quantity then
          raise exception 'Estoque insuficiente para %',v_item.name;
        end if;

        update public.products
        set stock_quantity=stock_quantity-v_item.quantity,
            updated_at=now()
        where id=v_item.product_id
          and business_id=v_business;

        insert into public.stock_movements(
          business_id,product_id,movement_type,quantity,unit_cost,reference_id,created_by
        )
        values(
          v_business,v_item.product_id,'sale',
          -v_item.quantity,v_item.average_cost,p_sale_id,auth.uid()
        );
      end if;
    end if;

    update public.sale_items
    set unit_cost=case
      when v_item.quantity>0 then round(v_item_cogs/v_item.quantity,4)
      else 0
    end
    where id=v_item.id;

    v_cogs := v_cogs+v_item_cogs;
  end loop;

  update public.sales
  set subtotal=(
        select round(coalesce(sum(line_total),0),2)
        from public.sale_items
        where sale_id=p_sale_id
      ),
      total=v_total,
      cogs=round(v_cogs,2),
      status='completed',
      cash_session_id=p_cash_session_id,
      completed_at=now(),
      updated_at=now()
  where id=p_sale_id
  returning * into v_sale;

  insert into public.cash_movements(
    business_id,cash_session_id,movement_type,amount,reference_id,description,created_by
  )
  values(
    v_business,p_cash_session_id,'sale',v_total,p_sale_id,'Venda finalizada',auth.uid()
  );

  return v_sale;
end;
$$;

-- ---------------------------------------------------------------------------
-- Post purchase atomically and only remove cash when payment is cash.
-- ---------------------------------------------------------------------------
create or replace function public.post_purchase(p_purchase_id uuid)
returns public.purchases
language plpgsql
security definer
set search_path=public
as $$
declare
  v_purchase public.purchases%rowtype;
  v_item record;
  v_old_qty numeric;
  v_old_cost numeric;
  v_new_cost numeric;
  v_session uuid;
begin
  select *
  into v_purchase
  from public.purchases
  where id=p_purchase_id
  for update;

  if not found then raise exception 'Compra não encontrada'; end if;

  if not public.has_business_role(
    v_purchase.business_id,
    array['owner','manager','stockkeeper']::public.member_role[]
  ) then
    raise exception 'Sem permissão';
  end if;

  if v_purchase.status<>'draft' then
    raise exception 'Somente compras em rascunho podem ser lançadas';
  end if;

  select round(coalesce(sum(line_total),0),2)
  into v_purchase.total
  from public.purchase_items
  where purchase_id=p_purchase_id;

  if v_purchase.total<0 then
    raise exception 'Total de compra inválido';
  end if;

  if v_purchase.payment_method='cash' then
    select id into v_session
    from public.cash_sessions
    where business_id=v_purchase.business_id
      and status='open'
    limit 1;

    if v_session is null then
      raise exception 'Abra o caixa antes de lançar uma compra paga em dinheiro';
    end if;
  end if;

  for v_item in
    select *
    from public.purchase_items
    where purchase_id=p_purchase_id
  loop
    select stock_quantity,average_cost
    into v_old_qty,v_old_cost
    from public.products
    where id=v_item.product_id
      and business_id=v_purchase.business_id
    for update;

    if not found then
      raise exception 'Produto da compra não encontrado ou pertence a outro negócio';
    end if;

    if v_old_qty+v_item.quantity>0 then
      v_new_cost := (
        (v_old_qty*v_old_cost)+(v_item.quantity*v_item.unit_cost)
      )/(v_old_qty+v_item.quantity);
    else
      v_new_cost := v_item.unit_cost;
    end if;

    update public.products
    set stock_quantity=stock_quantity+v_item.quantity,
        average_cost=round(v_new_cost,4),
        updated_at=now()
    where id=v_item.product_id;

    insert into public.stock_movements(
      business_id,product_id,movement_type,quantity,unit_cost,reference_id,created_by
    )
    values(
      v_purchase.business_id,v_item.product_id,'purchase',
      v_item.quantity,v_item.unit_cost,p_purchase_id,auth.uid()
    );
  end loop;

  update public.purchases
  set total=v_purchase.total,
      status='posted'
  where id=p_purchase_id
  returning * into v_purchase;

  if v_purchase.payment_method='cash' then
    insert into public.cash_movements(
      business_id,cash_session_id,movement_type,amount,reference_id,description,created_by
    )
    values(
      v_purchase.business_id,v_session,'expense',-v_purchase.total,
      p_purchase_id,'Compra de estoque',auth.uid()
    );
  end if;

  return v_purchase;
end;
$$;

revoke all on function public.finalize_sale(uuid,uuid) from public;
revoke all on function public.finalize_sale(uuid,uuid) from anon;
grant execute on function public.finalize_sale(uuid,uuid) to authenticated;

revoke all on function public.post_purchase(uuid) from public;
revoke all on function public.post_purchase(uuid) from anon;
grant execute on function public.post_purchase(uuid) to authenticated;
