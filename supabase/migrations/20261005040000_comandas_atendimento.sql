-- Urbana Café: comandas and service lifecycle.
-- Open sales become editable service orders until checkout; stock/cash only post on finalization.

create unique index if not exists sales_one_open_table_per_business_idx
  on public.sales(business_id,table_id)
  where status='open' and table_id is not null;

create or replace function private.create_open_order_transaction(
  p_business_id uuid,
  p_customer_id uuid default null,
  p_table_id uuid default null,
  p_notes text default null,
  p_items jsonb default '[]'::jsonb,
  p_discount numeric default 0
)
returns public.sales
language plpgsql
security definer
set search_path=''
as $$
declare
  v_sale public.sales%rowtype;
  v_item jsonb;
  v_product public.products%rowtype;
  v_qty numeric(14,3);
  v_subtotal numeric(14,2) := 0;
  v_total numeric(14,2);
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado';
  end if;

  if not public.has_business_role(
    p_business_id,
    array['owner','manager','cashier','waiter']::public.member_role[]
  ) then
    raise exception 'Usuário sem permissão para abrir comandas';
  end if;

  if not exists (
    select 1 from public.businesses
    where id=p_business_id and active
  ) then
    raise exception 'Negócio inválido ou inativo';
  end if;

  if p_discount is null or p_discount<0 then
    raise exception 'Desconto inválido';
  end if;

  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then
    raise exception 'Adicione pelo menos um produto';
  end if;

  if p_customer_id is not null and not exists (
    select 1 from public.customers
    where id=p_customer_id and business_id=p_business_id and active
  ) then
    raise exception 'Cliente inválido';
  end if;

  if p_table_id is not null and not exists (
    select 1 from public.cafe_tables
    where id=p_table_id and business_id=p_business_id and active
  ) then
    raise exception 'Mesa inválida';
  end if;

  if p_table_id is not null and exists (
    select 1 from public.sales
    where business_id=p_business_id
      and table_id=p_table_id
      and status='open'
  ) then
    raise exception 'Mesa já possui uma comanda aberta';
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

    begin
      select * into v_product
      from public.products
      where id=(v_item->>'product_id')::uuid
        and business_id=p_business_id
        and active=true
        and is_sellable=true;
    exception when invalid_text_representation then
      raise exception 'Produto inválido na comanda';
    end;

    if not found then
      raise exception 'Produto não encontrado, inativo ou não vendável';
    end if;

    v_subtotal := v_subtotal + round(v_product.sale_price*v_qty,2);
  end loop;

  v_total := round(v_subtotal-coalesce(p_discount,0),2);
  if v_total<0 then
    raise exception 'Total da comanda inválido';
  end if;

  insert into public.sales(
    business_id,
    customer_id,
    table_id,
    channel,
    status,
    subtotal,
    discount,
    total,
    notes,
    opened_by
  )
  values(
    p_business_id,
    p_customer_id,
    p_table_id,
    case when p_table_id is not null
      then 'table'::public.order_channel
      else 'counter'::public.order_channel
    end,
    'open',
    v_subtotal,
    coalesce(p_discount,0),
    v_total,
    nullif(trim(coalesce(p_notes,'')),''),
    auth.uid()
  )
  returning * into v_sale;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_qty := (v_item->>'quantity')::numeric;

    select * into v_product
    from public.products
    where id=(v_item->>'product_id')::uuid
      and business_id=p_business_id
      and active=true
      and is_sellable=true;

    insert into public.sale_items(
      sale_id,product_id,quantity,unit_price,unit_cost
    )
    values(
      v_sale.id,v_product.id,v_qty,v_product.sale_price,v_product.average_cost
    );
  end loop;

  insert into public.audit_logs(
    business_id,user_id,action,entity,entity_id,new_data
  )
  values(
    p_business_id,
    auth.uid(),
    'order_opened',
    'sale',
    v_sale.id,
    jsonb_build_object(
      'table_id',p_table_id,
      'customer_id',p_customer_id,
      'subtotal',v_subtotal,
      'discount',coalesce(p_discount,0),
      'total',v_total
    )
  );

  return v_sale;
exception
  when unique_violation then
    raise exception 'Mesa já possui uma comanda aberta';
end;
$$;

create or replace function private.update_open_order_transaction(
  p_sale_id uuid,
  p_customer_id uuid default null,
  p_table_id uuid default null,
  p_notes text default null,
  p_items jsonb default '[]'::jsonb,
  p_discount numeric default 0
)
returns public.sales
language plpgsql
security definer
set search_path=''
as $$
declare
  v_sale public.sales%rowtype;
  v_old_table uuid;
  v_item jsonb;
  v_product public.products%rowtype;
  v_qty numeric(14,3);
  v_subtotal numeric(14,2) := 0;
  v_total numeric(14,2);
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado';
  end if;

  select * into v_sale
  from public.sales
  where id=p_sale_id
  for update;

  if not found then
    raise exception 'Comanda não encontrada';
  end if;

  if not public.has_business_role(
    v_sale.business_id,
    array['owner','manager','cashier','waiter']::public.member_role[]
  ) then
    raise exception 'Usuário sem permissão para editar esta comanda';
  end if;

  if v_sale.status<>'open' then
    raise exception 'Somente comandas abertas podem ser editadas';
  end if;

  v_old_table:=v_sale.table_id;

  if p_discount is null or p_discount<0 then
    raise exception 'Desconto inválido';
  end if;

  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then
    raise exception 'Adicione pelo menos um produto';
  end if;

  if p_customer_id is not null and not exists (
    select 1 from public.customers
    where id=p_customer_id and business_id=v_sale.business_id and active
  ) then
    raise exception 'Cliente inválido';
  end if;

  if p_table_id is not null and not exists (
    select 1 from public.cafe_tables
    where id=p_table_id and business_id=v_sale.business_id and active
  ) then
    raise exception 'Mesa inválida';
  end if;

  if p_table_id is distinct from v_old_table
     and p_table_id is not null
     and exists (
       select 1 from public.sales
       where business_id=v_sale.business_id
         and table_id=p_table_id
         and status='open'
         and id<>p_sale_id
     ) then
    raise exception 'Mesa já possui outra comanda aberta';
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

    begin
      select * into v_product
      from public.products
      where id=(v_item->>'product_id')::uuid
        and business_id=v_sale.business_id
        and active=true
        and is_sellable=true;
    exception when invalid_text_representation then
      raise exception 'Produto inválido na comanda';
    end;

    if not found then
      raise exception 'Produto não encontrado, inativo ou não vendável';
    end if;

    v_subtotal := v_subtotal + round(v_product.sale_price*v_qty,2);
  end loop;

  v_total := round(v_subtotal-coalesce(p_discount,0),2);
  if v_total<0 then
    raise exception 'Total da comanda inválido';
  end if;

  if exists(select 1 from public.sale_payments where sale_id=p_sale_id) then
    raise exception 'Comanda aberta não pode possuir pagamento registrado';
  end if;

  delete from public.sale_items
  where sale_id=p_sale_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_qty := (v_item->>'quantity')::numeric;

    select * into v_product
    from public.products
    where id=(v_item->>'product_id')::uuid
      and business_id=v_sale.business_id
      and active=true
      and is_sellable=true;

    insert into public.sale_items(
      sale_id,product_id,quantity,unit_price,unit_cost
    )
    values(
      p_sale_id,v_product.id,v_qty,v_product.sale_price,v_product.average_cost
    );
  end loop;

  update public.sales
  set customer_id=p_customer_id,
      table_id=p_table_id,
      channel=case when p_table_id is not null
        then 'table'::public.order_channel
        else 'counter'::public.order_channel
      end,
      subtotal=v_subtotal,
      discount=coalesce(p_discount,0),
      total=v_total,
      notes=nullif(trim(coalesce(p_notes,'')),''),
      updated_at=now()
  where id=p_sale_id
  returning * into v_sale;

  insert into public.audit_logs(
    business_id,user_id,action,entity,entity_id,old_data,new_data
  )
  values(
    v_sale.business_id,
    auth.uid(),
    'order_updated',
    'sale',
    v_sale.id,
    jsonb_build_object(
      'table_id',v_old_table
    ),
    jsonb_build_object(
      'table_id',v_sale.table_id,
      'customer_id',v_sale.customer_id,
      'subtotal',v_sale.subtotal,
      'discount',v_sale.discount,
      'total',v_sale.total
    )
  );

  return v_sale;
exception
  when unique_violation then
    raise exception 'Mesa já possui outra comanda aberta';
end;
$$;

create or replace function private.close_open_order_transaction(
  p_sale_id uuid,
  p_cash_session_id uuid,
  p_payment_method public.payment_method
)
returns public.sales
language plpgsql
security definer
set search_path=''
as $$
declare
  v_sale public.sales%rowtype;
  v_product public.products%rowtype;
  v_item record;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado';
  end if;

  select * into v_sale
  from public.sales
  where id=p_sale_id
  for update;

  if not found then
    raise exception 'Comanda não encontrada';
  end if;

  if not public.has_business_role(
    v_sale.business_id,
    array['owner','manager','cashier','waiter']::public.member_role[]
  ) then
    raise exception 'Usuário sem permissão para finalizar esta comanda';
  end if;

  if v_sale.status<>'open' then
    raise exception 'Somente comandas abertas podem ser finalizadas';
  end if;

  if p_cash_session_id is null or not exists (
    select 1 from public.cash_sessions
    where id=p_cash_session_id
      and business_id=v_sale.business_id
      and status='open'
  ) then
    raise exception 'Sessão de caixa inválida ou fechada';
  end if;

  if not exists(select 1 from public.sale_items where sale_id=p_sale_id) then
    raise exception 'Comanda sem itens';
  end if;

  if exists(select 1 from public.sale_payments where sale_id=p_sale_id) then
    raise exception 'Comanda já possui pagamento registrado';
  end if;

  for v_item in
    select si.id,si.product_id,p.average_cost
    from public.sale_items si
    join public.products p on p.id=si.product_id
    where si.sale_id=p_sale_id
    for update of si
  loop
    update public.sale_items
    set unit_cost=round(v_item.average_cost,4)
    where id=v_item.id;
  end loop;

  insert into public.sale_payments(sale_id,method,amount)
  values(p_sale_id,p_payment_method,round(v_sale.total,2));

  return private.finalize_sale(p_sale_id,p_cash_session_id);
end;
$$;

create or replace function private.cancel_open_order_transaction(
  p_sale_id uuid,
  p_reason text default null
)
returns public.sales
language plpgsql
security definer
set search_path=''
as $$
declare
  v_sale public.sales%rowtype;
  v_reason text;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado';
  end if;

  select * into v_sale
  from public.sales
  where id=p_sale_id
  for update;

  if not found then
    raise exception 'Comanda não encontrada';
  end if;

  if not public.has_business_role(
    v_sale.business_id,
    array['owner','manager','cashier','waiter']::public.member_role[]
  ) then
    raise exception 'Usuário sem permissão para cancelar esta comanda';
  end if;

  if v_sale.status<>'open' then
    raise exception 'Somente comandas abertas podem ser canceladas';
  end if;

  v_reason:=nullif(trim(coalesce(p_reason,'')),'');
  if v_reason is null then
    raise exception 'Informe o motivo do cancelamento';
  end if;

  update public.sales
  set status='cancelled',
      notes=case
        when nullif(trim(coalesce(notes,'')),'') is null then '[Cancelada] '||v_reason
        else notes||' | [Cancelada] '||v_reason
      end,
      updated_at=now()
  where id=p_sale_id
  returning * into v_sale;

  insert into public.audit_logs(
    business_id,user_id,action,entity,entity_id,old_data,new_data
  )
  values(
    v_sale.business_id,
    auth.uid(),
    'order_cancelled',
    'sale',
    v_sale.id,
    jsonb_build_object('table_id',v_sale.table_id,'status','open'),
    jsonb_build_object('table_id',v_sale.table_id,'status','cancelled','reason',v_reason)
  );

  return v_sale;
end;
$$;

create or replace function public.create_open_order(
  p_business_id uuid,
  p_customer_id uuid default null,
  p_table_id uuid default null,
  p_notes text default null,
  p_items jsonb default '[]'::jsonb,
  p_discount numeric default 0
)
returns public.sales
language sql
security invoker
set search_path=public
as $$
  select private.create_open_order_transaction(
    p_business_id,p_customer_id,p_table_id,p_notes,p_items,p_discount
  );
$$;

create or replace function public.update_open_order(
  p_sale_id uuid,
  p_customer_id uuid default null,
  p_table_id uuid default null,
  p_notes text default null,
  p_items jsonb default '[]'::jsonb,
  p_discount numeric default 0
)
returns public.sales
language sql
security invoker
set search_path=public
as $$
  select private.update_open_order_transaction(
    p_sale_id,p_customer_id,p_table_id,p_notes,p_items,p_discount
  );
$$;

create or replace function public.close_open_order(
  p_sale_id uuid,
  p_cash_session_id uuid,
  p_payment_method public.payment_method
)
returns public.sales
language sql
security invoker
set search_path=public
as $$
  select private.close_open_order_transaction(
    p_sale_id,p_cash_session_id,p_payment_method
  );
$$;

create or replace function public.cancel_open_order(
  p_sale_id uuid,
  p_reason text default null
)
returns public.sales
language sql
security invoker
set search_path=public
as $$
  select private.cancel_open_order_transaction(
    p_sale_id,p_reason
  );
$$;

revoke all on function private.create_open_order_transaction(uuid,uuid,uuid,text,jsonb,numeric) from public,anon;
revoke all on function private.update_open_order_transaction(uuid,uuid,uuid,text,jsonb,numeric) from public,anon;
revoke all on function private.close_open_order_transaction(uuid,uuid,public.payment_method) from public,anon;
revoke all on function private.cancel_open_order_transaction(uuid,text) from public,anon;

grant execute on function private.create_open_order_transaction(uuid,uuid,uuid,text,jsonb,numeric) to authenticated;
grant execute on function private.update_open_order_transaction(uuid,uuid,uuid,text,jsonb,numeric) to authenticated;
grant execute on function private.close_open_order_transaction(uuid,uuid,public.payment_method) to authenticated;
grant execute on function private.cancel_open_order_transaction(uuid,text) to authenticated;

revoke all on function public.create_open_order(uuid,uuid,uuid,text,jsonb,numeric) from public,anon;
revoke all on function public.update_open_order(uuid,uuid,uuid,text,jsonb,numeric) from public,anon;
revoke all on function public.close_open_order(uuid,uuid,public.payment_method) from public,anon;
revoke all on function public.cancel_open_order(uuid,text) from public,anon;

grant execute on function public.create_open_order(uuid,uuid,uuid,text,jsonb,numeric) to authenticated;
grant execute on function public.update_open_order(uuid,uuid,uuid,text,jsonb,numeric) to authenticated;
grant execute on function public.close_open_order(uuid,uuid,public.payment_method) to authenticated;
grant execute on function public.cancel_open_order(uuid,text) to authenticated;

revoke all on schema private from public,anon;
grant usage on schema private to authenticated;
