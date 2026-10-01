-- Urbana Café: atomic POS transaction aligned with sales + items + payments + finalize_sale.
create or replace function public.create_sale_transaction(
  p_business_id uuid,
  p_cash_session_id uuid,
  p_customer_id uuid default null,
  p_table_id uuid default null,
  p_notes text default null,
  p_payment_method public.payment_method default 'cash',
  p_items jsonb default '[]'::jsonb,
  p_discount numeric default 0
)
returns public.sales
language plpgsql
security definer
set search_path=public
as $$
declare
  v_sale public.sales%rowtype;
  v_item jsonb;
  v_product public.products%rowtype;
  v_qty numeric(14,3);
  v_subtotal numeric(14,2):=0;
  v_total numeric(14,2);
begin
  if not public.has_business_role(
    p_business_id,
    array['owner','manager','cashier','waiter']::public.member_role[]
  ) then
    raise exception 'Usuário sem permissão para registrar vendas';
  end if;

  if p_cash_session_id is null or not exists(
    select 1
    from public.cash_sessions
    where id=p_cash_session_id
      and business_id=p_business_id
      and status='open'
  ) then
    raise exception 'Sessão de caixa inválida ou fechada';
  end if;

  if coalesce(p_discount,0)<0 then
    raise exception 'Desconto inválido';
  end if;

  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then
    raise exception 'Adicione pelo menos um produto';
  end if;

  if p_customer_id is not null and not exists(
    select 1 from public.customers
    where id=p_customer_id
      and business_id=p_business_id
      and active
  ) then
    raise exception 'Cliente inválido';
  end if;

  if p_table_id is not null and not exists(
    select 1 from public.cafe_tables
    where id=p_table_id
      and business_id=p_business_id
      and active
  ) then
    raise exception 'Mesa inválida';
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    begin
      v_qty := (v_item->>'quantity')::numeric;
    exception when invalid_text_representation then
      raise exception 'Quantidade inválida para o produto %',coalesce(v_item->>'product_id','');
    end;

    if v_qty is null or v_qty<=0 then
      raise exception 'Quantidade deve ser maior que zero';
    end if;

    select *
    into v_product
    from public.products
    where id=(v_item->>'product_id')::uuid
      and business_id=p_business_id
      and active=true
      and is_sellable=true
    for update;

    if not found then
      raise exception 'Produto não encontrado, inativo ou não vendável';
    end if;

    v_subtotal:=v_subtotal+round(v_product.sale_price*v_qty,2);
  end loop;

  v_total:=round(v_subtotal-coalesce(p_discount,0),2);

  if v_total<=0 then
    raise exception 'Total da venda deve ser maior que zero';
  end if;

  insert into public.sales(
    business_id,customer_id,table_id,channel,status,subtotal,discount,total,notes,opened_by
  )
  values(
    p_business_id,
    p_customer_id,
    p_table_id,
    case
      when p_table_id is not null then 'table'::public.order_channel
      else 'counter'::public.order_channel
    end,
    'open',
    v_subtotal,
    coalesce(p_discount,0),
    v_total,
    nullif(trim(p_notes),''),
    auth.uid()
  )
  returning * into v_sale;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_qty:=(v_item->>'quantity')::numeric;

    select *
    into v_product
    from public.products
    where id=(v_item->>'product_id')::uuid
      and business_id=p_business_id;

    insert into public.sale_items(
      sale_id,product_id,quantity,unit_price,unit_cost
    )
    values(
      v_sale.id,
      v_product.id,
      v_qty,
      v_product.sale_price,
      v_product.average_cost
    );
  end loop;

  insert into public.sale_payments(sale_id,method,amount)
  values(v_sale.id,p_payment_method,v_total);

  return public.finalize_sale(v_sale.id,p_cash_session_id);
exception
  when invalid_text_representation then
    raise exception 'Produto inválido na venda';
end;
$$;

revoke all on function public.create_sale_transaction(uuid,uuid,uuid,uuid,text,public.payment_method,jsonb,numeric) from public;
revoke all on function public.create_sale_transaction(uuid,uuid,uuid,uuid,text,public.payment_method,jsonb,numeric) from anon;
grant execute on function public.create_sale_transaction(uuid,uuid,uuid,uuid,text,public.payment_method,jsonb,numeric) to authenticated;
