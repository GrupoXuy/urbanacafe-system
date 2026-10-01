-- Transactional business operations for Urbana Café.
create or replace function public.finalize_sale(p_sale_id uuid, p_cash_session_id uuid)
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
  v_need numeric(14,3);
  v_available numeric(14,3);
begin
  select * into v_sale from public.sales where id=p_sale_id for update;
  if not found then raise exception 'Venda não encontrada'; end if;
  v_business := v_sale.business_id;

  if not public.has_business_role(v_business,array['owner','manager','cashier','waiter']::public.member_role[]) then
    raise exception 'Usuário sem permissão para finalizar esta venda';
  end if;

  if v_sale.status <> 'open' then raise exception 'Somente vendas abertas podem ser finalizadas'; end if;

  select coalesce(sum(line_total),0) into v_total from public.sale_items where sale_id=p_sale_id;
  v_total := round(v_total - coalesce(v_sale.discount,0),2);
  if v_total < 0 then raise exception 'Desconto inválido'; end if;

  select coalesce(sum(amount),0) into v_paid from public.sale_payments where sale_id=p_sale_id;
  if round(v_paid,2) <> v_total then raise exception 'Pagamento insuficiente ou divergente: esperado %, recebido %',v_total,v_paid; end if;

  if p_cash_session_id is null then raise exception 'Caixa aberto é obrigatório'; end if;
  if not exists(select 1 from public.cash_sessions where id=p_cash_session_id and business_id=v_business and status='open') then
    raise exception 'Sessão de caixa inválida ou fechada';
  end if;

  for v_item in select si.*,p.name,p.stock_quantity,p.is_stock_item from public.sale_items si join public.products p on p.id=si.product_id where si.sale_id=p_sale_id for update of si loop
    update public.sale_items set unit_cost=(select average_cost from public.products where id=v_item.product_id) where id=v_item.id;

    select coalesce(sum(
      case when r.id is null then v_item.quantity
           else (ri.quantity / r.yield_quantity) * v_item.quantity end
    ),v_item.quantity)
    into v_need
    from public.recipes r
    left join public.recipe_items ri on ri.recipe_id=r.id
    where r.product_id=v_item.product_id;

    if exists(select 1 from public.recipes where product_id=v_item.product_id and active) then
      for v_recipe in
        select ri.ingredient_product_id,
               (ri.quantity/r.yield_quantity)*v_item.quantity as required_qty
        from public.recipes r
        join public.recipe_items ri on ri.recipe_id=r.id
        where r.product_id=v_item.product_id and r.active
      loop
        select stock_quantity into v_available from public.products where id=v_recipe.ingredient_product_id for update;
        if v_available < v_recipe.required_qty then
          raise exception 'Estoque insuficiente para o ingrediente %',v_recipe.ingredient_product_id;
        end if;
        v_cogs := v_cogs + v_recipe.required_qty * (select average_cost from public.products where id=v_recipe.ingredient_product_id);
        update public.products set stock_quantity=stock_quantity-v_recipe.required_qty where id=v_recipe.ingredient_product_id;
        insert into public.stock_movements(business_id,product_id,movement_type,quantity,unit_cost,reference_id,created_by)
        values(v_business,v_recipe.ingredient_product_id,'sale',-v_recipe.required_qty,(select average_cost from public.products where id=v_recipe.ingredient_product_id),p_sale_id,auth.uid());
      end loop;
    elsif v_item.is_stock_item then
      if v_item.stock_quantity < v_item.quantity then raise exception 'Estoque insuficiente para %',v_item.name; end if;
      v_cogs := v_cogs + v_item.quantity * (select average_cost from public.products where id=v_item.product_id);
      update public.products set stock_quantity=stock_quantity-v_item.quantity where id=v_item.product_id;
      insert into public.stock_movements(business_id,product_id,movement_type,quantity,unit_cost,reference_id,created_by)
      values(v_business,v_item.product_id,'sale',-v_item.quantity,(select average_cost from public.products where id=v_item.product_id),p_sale_id,auth.uid());
    end if;
  end loop;

  update public.sales
  set subtotal=(select coalesce(sum(line_total),0) from public.sale_items where sale_id=p_sale_id),
      total=v_total,cogs=round(v_cogs,2),status='completed',
      cash_session_id=p_cash_session_id,completed_at=now(),updated_at=now()
  where id=p_sale_id
  returning * into v_sale;

  insert into public.cash_movements(business_id,cash_session_id,movement_type,amount,reference_id,description,created_by)
  values(v_business,p_cash_session_id,'sale',v_total,p_sale_id,'Venda finalizada',auth.uid());

  return v_sale;
end;
$$;

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
begin
  select * into v_purchase from public.purchases where id=p_purchase_id for update;
  if not found then raise exception 'Compra não encontrada'; end if;
  if not public.has_business_role(v_purchase.business_id,array['owner','manager','stockkeeper']::public.member_role[]) then raise exception 'Sem permissão'; end if;
  if v_purchase.status <> 'draft' then raise exception 'Somente compras em rascunho podem ser lançadas'; end if;

  for v_item in select * from public.purchase_items where purchase_id=p_purchase_id loop
    select stock_quantity,average_cost into v_old_qty,v_old_cost from public.products where id=v_item.product_id for update;
    if not found then raise exception 'Produto não encontrado'; end if;
    if v_old_qty + v_item.quantity > 0 then
      v_new_cost := ((v_old_qty*v_old_cost)+(v_item.quantity*v_item.unit_cost))/(v_old_qty+v_item.quantity);
    else v_new_cost := v_item.unit_cost; end if;
    update public.products set stock_quantity=stock_quantity+v_item.quantity,average_cost=round(v_new_cost,4),updated_at=now() where id=v_item.product_id;
    insert into public.stock_movements(business_id,product_id,movement_type,quantity,unit_cost,reference_id,created_by)
    values(v_purchase.business_id,v_item.product_id,'purchase',v_item.quantity,v_item.unit_cost,p_purchase_id,auth.uid());
  end loop;

  update public.purchases set status='posted',total=(select coalesce(sum(line_total),0) from public.purchase_items where purchase_id=p_purchase_id) where id=p_purchase_id returning * into v_purchase;
  insert into public.cash_movements(business_id,movement_type,amount,reference_id,description,created_by)
  values(v_purchase.business_id,'expense',-v_purchase.total,p_purchase_id,'Compra de estoque',auth.uid());
  return v_purchase;
end;
$$;

create or replace function public.open_cash_session(p_business_id uuid,p_opening_amount numeric)
returns public.cash_sessions
language plpgsql security definer set search_path=public as $$
declare v_result public.cash_sessions;
begin
 if not public.has_business_role(p_business_id,array['owner','manager','cashier']::public.member_role[]) then raise exception 'Sem permissão'; end if;
 if exists(select 1 from public.cash_sessions where business_id=p_business_id and status='open') then raise exception 'Já existe um caixa aberto'; end if;
 insert into public.cash_sessions(business_id,opened_by,opening_amount) values(p_business_id,auth.uid(),p_opening_amount) returning * into v_result;
 insert into public.cash_movements(business_id,cash_session_id,movement_type,amount,description,created_by) values(p_business_id,v_result.id,'deposit',p_opening_amount,'Abertura de caixa',auth.uid());
 return v_result;
end;
$$;

create or replace function public.close_cash_session(p_session_id uuid,p_counted_amount numeric,p_note text default null)
returns public.cash_sessions
language plpgsql security definer set search_path=public as $$
declare v_result public.cash_sessions; v_expected numeric(14,2);
begin
 select * into v_result from public.cash_sessions where id=p_session_id for update;
 if not found then raise exception 'Caixa não encontrado'; end if;
 if not public.has_business_role(v_result.business_id,array['owner','manager','cashier']::public.member_role[]) then raise exception 'Sem permissão'; end if;
 if v_result.status <> 'open' then raise exception 'Caixa já está fechado'; end if;
 select round(v_result.opening_amount+coalesce(sum(amount),0),2) into v_expected from public.cash_movements where cash_session_id=p_session_id;
 update public.cash_sessions set status='closed',closed_by=auth.uid(),closed_at=now(),expected_amount=v_expected,counted_amount=p_counted_amount,difference=round(p_counted_amount-v_expected,2),closing_note=p_note where id=p_session_id returning * into v_result;
 return v_result;
end;
$$;

grant execute on function public.finalize_sale(uuid,uuid) to authenticated;
grant execute on function public.post_purchase(uuid) to authenticated;
grant execute on function public.open_cash_session(uuid,numeric) to authenticated;
grant execute on function public.close_cash_session(uuid,numeric,text) to authenticated;