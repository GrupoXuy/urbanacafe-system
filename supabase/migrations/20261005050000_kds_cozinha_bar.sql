-- Urbana Café: kitchen display system (KDS), production routing and print-ready order flow.

create type public.production_station as enum ('none','kitchen','bar');
create type public.production_ticket_status as enum ('pending','preparing','ready','served','cancelled');

alter table public.products
  add column if not exists production_station public.production_station not null default 'none';

alter table public.products
  alter column production_station set default 'kitchen';

create table public.production_tickets (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  sale_id uuid not null references public.sales(id) on delete restrict,
  station public.production_station not null,
  status public.production_ticket_status not null default 'pending',
  sent_at timestamptz not null default now(),
  started_at timestamptz,
  ready_at timestamptz,
  served_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(station in ('kitchen','bar')),
  unique(sale_id,station)
);

create index production_tickets_kds_idx
  on public.production_tickets(business_id,station,status,created_at);

alter table public.production_tickets enable row level security;

create policy production_tickets_read
  on public.production_tickets
  for select
  to authenticated
  using (public.is_business_member(business_id));

grant select on public.production_tickets to authenticated;
revoke insert,update,delete on public.production_tickets from authenticated;

create or replace function private.sync_production_tickets(p_sale_id uuid)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  v_business uuid;
  v_uid uuid;
  v_station public.production_station;
  v_required boolean;
begin
  v_uid:=auth.uid();

  select business_id into v_business
  from public.sales
  where id=p_sale_id;

  if v_business is null then
    raise exception 'Comanda não encontrada';
  end if;

  if not public.has_business_role(
    v_business,
    array['owner','manager','cashier','waiter']::public.member_role[]
  ) then
    raise exception 'Usuário sem permissão para enviar a comanda à produção';
  end if;

  for v_station in
    select distinct p.production_station
    from public.sale_items si
    join public.products p on p.id=si.product_id
    where si.sale_id=p_sale_id
      and p.production_station in (
        'kitchen'::public.production_station,
        'bar'::public.production_station
      )
    order by p.production_station
  loop
    insert into public.production_tickets(
      business_id,sale_id,station,status,sent_at
    )
    values(
      v_business,p_sale_id,v_station,'pending',now()
    )
    on conflict (sale_id,station) do nothing;
  end loop;

  for v_station in
    select station
    from public.production_tickets
    where sale_id=p_sale_id
      and status='pending'
    order by station
  loop
    select exists(
      select 1
      from public.sale_items si
      join public.products p on p.id=si.product_id
      where si.sale_id=p_sale_id
        and p.production_station=v_station
    ) into v_required;

    if not v_required then
      update public.production_tickets
      set status='cancelled',
          cancelled_at=coalesce(cancelled_at,now()),
          updated_at=now()
      where sale_id=p_sale_id
        and station=v_station
        and status='pending';

      insert into public.audit_logs(
        business_id,user_id,action,entity,entity_id,new_data
      )
      select
        v_business,v_uid,'production_ticket_cancelled','production_ticket',pt.id,
        jsonb_build_object(
          'sale_id',pt.sale_id,
          'station',pt.station,
          'reason','Estação deixou de ser necessária após edição da comanda'
        )
      from public.production_tickets pt
      where pt.sale_id=p_sale_id
        and pt.station=v_station
        and pt.status='cancelled'
        and pt.cancelled_at is not null
        and pt.updated_at >= now()-interval '1 second';
    end if;
  end loop;
end;
$$;

create or replace function private.create_sale_transaction(
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
set search_path=''
as $create_sale$
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

  if not public.has_business_role(p_business_id,array['owner','manager','cashier','waiter']::public.member_role[]) then
    raise exception 'Usuário sem permissão para registrar vendas';
  end if;

  if p_cash_session_id is null or not exists(
    select 1 from public.cash_sessions
    where id=p_cash_session_id and business_id=p_business_id and status='open'
  ) then
    raise exception 'Sessão de caixa inválida ou fechada';
  end if;

  if p_discount<0 then raise exception 'Desconto inválido'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then
    raise exception 'Adicione pelo menos um produto';
  end if;

  if p_customer_id is not null and not exists(
    select 1 from public.customers
    where id=p_customer_id and business_id=p_business_id and active
  ) then
    raise exception 'Cliente inválido';
  end if;

  if p_table_id is not null and not exists(
    select 1 from public.cafe_tables
    where id=p_table_id and business_id=p_business_id and active
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

    select * into v_product
    from public.products
    where id=(v_item->>'product_id')::uuid
      and business_id=p_business_id
      and active=true
      and is_sellable=true
    for update;

    if not found then
      raise exception 'Produto não encontrado, inativo ou não vendável';
    end if;

    v_subtotal := v_subtotal + round(v_product.sale_price*v_qty,2);
  end loop;

  v_total := round(v_subtotal-coalesce(p_discount,0),2);
  if v_total<0 then raise exception 'Total da venda inválido'; end if;

  insert into public.sales(
    business_id,customer_id,table_id,channel,status,
    subtotal,discount,total,notes,opened_by
  )
  values(
    p_business_id,p_customer_id,p_table_id,
    case when p_table_id is not null then 'table'::public.order_channel else 'counter'::public.order_channel end,
    'open',v_subtotal,coalesce(p_discount,0),v_total,
    nullif(trim(p_notes),''),
    auth.uid()
  )
  returning * into v_sale;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_qty := (v_item->>'quantity')::numeric;
    select * into v_product
    from public.products
    where id=(v_item->>'product_id')::uuid
      and business_id=p_business_id;
    insert into public.sale_items(
      sale_id,product_id,quantity,unit_price,unit_cost
    )
    values(v_sale.id,v_product.id,v_qty,v_product.sale_price,v_product.average_cost);
  end loop;

  perform private.sync_production_tickets(v_sale.id);

  insert into public.sale_payments(sale_id,method,amount)
  values(v_sale.id,p_payment_method,v_total);

  return private.finalize_sale(v_sale.id,p_cash_session_id);
exception
  when invalid_text_representation then
    raise exception 'Produto inválido na venda';
end;
$create_sale$;

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
    business_id,customer_id,table_id,channel,status,
    subtotal,discount,total,notes,opened_by
  )
  values(
    p_business_id,p_customer_id,p_table_id,
    case when p_table_id is not null
      then 'table'::public.order_channel
      else 'counter'::public.order_channel
    end,
    'open',v_subtotal,coalesce(p_discount,0),v_total,
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

  perform private.sync_production_tickets(v_sale.id);

  insert into public.audit_logs(
    business_id,user_id,action,entity,entity_id,new_data
  )
  values(
    p_business_id,auth.uid(),'order_opened','sale',v_sale.id,
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

  if exists(
    select 1 from public.production_tickets
    where sale_id=p_sale_id
      and status<> 'pending'
  ) then
    raise exception 'Comanda já está em produção; não é permitido alterar os itens';
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

  perform private.sync_production_tickets(p_sale_id);

  insert into public.audit_logs(
    business_id,user_id,action,entity,entity_id,old_data,new_data
  )
  values(
    v_sale.business_id,auth.uid(),'order_updated','sale',v_sale.id,
    jsonb_build_object('table_id',v_old_table),
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

  if exists(
    select 1 from public.production_tickets
    where sale_id=p_sale_id and status='served'
  ) then
    raise exception 'Comanda já possui item entregue e não pode ser cancelada';
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

  update public.production_tickets
  set status='cancelled',
      cancelled_at=coalesce(cancelled_at,now()),
      updated_at=now()
  where sale_id=p_sale_id
    and status<>'cancelled';

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
    jsonb_build_object(
      'table_id',v_sale.table_id,
      'status','cancelled',
      'reason',v_reason
    )
  );

  return v_sale;
end;
$$;

create or replace function private.update_production_ticket_status(
  p_ticket_id uuid,
  p_status public.production_ticket_status
)
returns public.production_tickets
language plpgsql
security definer
set search_path=''
as $$
declare
  v_ticket public.production_tickets%rowtype;
  v_sale_status public.sale_status;
  v_uid uuid;
begin
  v_uid:=auth.uid();

  if v_uid is null then
    raise exception 'Usuário não autenticado';
  end if;

  select * into v_ticket
  from public.production_tickets
  where id=p_ticket_id
  for update;

  if not found then
    raise exception 'Ticket de produção não encontrado';
  end if;

  if not public.has_business_role(
    v_ticket.business_id,
    array['owner','manager','cashier','waiter']::public.member_role[]
  ) then
    raise exception 'Usuário sem permissão para atualizar produção';
  end if;

  select status into v_sale_status
  from public.sales
  where id=v_ticket.sale_id;

  if v_sale_status not in ('open','completed') then
    raise exception 'Comanda não está disponível para produção';
  end if;

  if p_status='preparing' and v_ticket.status='pending' then
    update public.production_tickets
    set status='preparing',
        started_at=coalesce(started_at,now()),
        updated_at=now()
    where id=p_ticket_id;
  elsif p_status='ready' and v_ticket.status='preparing' then
    update public.production_tickets
    set status='ready',
        ready_at=coalesce(ready_at,now()),
        updated_at=now()
    where id=p_ticket_id;
  elsif p_status='served' and v_ticket.status='ready' then
    update public.production_tickets
    set status='served',
        served_at=coalesce(served_at,now()),
        updated_at=now()
    where id=p_ticket_id;
  elsif p_status=v_ticket.status then
    return v_ticket;
  else
    raise exception 'Transição de produção inválida: % → %',v_ticket.status,p_status;
  end if;

  select * into v_ticket
  from public.production_tickets
  where id=p_ticket_id;

  insert into public.audit_logs(
    business_id,user_id,action,entity,entity_id,new_data
  )
  values(
    v_ticket.business_id,
    v_uid,
    'production_status_changed',
    'production_ticket',
    v_ticket.id,
    jsonb_build_object(
      'sale_id',v_ticket.sale_id,
      'station',v_ticket.station,
      'status',v_ticket.status
    )
  );

  return v_ticket;
end;
$$;

create or replace function public.update_production_ticket_status(
  p_ticket_id uuid,
  p_status public.production_ticket_status
)
returns public.production_tickets
language sql
security invoker
set search_path=public
as $$
  select private.update_production_ticket_status(p_ticket_id,p_status);
$$;

revoke all on function private.sync_production_tickets(uuid) from public,anon;
revoke all on function private.update_production_ticket_status(uuid,public.production_ticket_status) from public,anon;
grant execute on function private.sync_production_tickets(uuid) to authenticated;
grant execute on function private.update_production_ticket_status(uuid,public.production_ticket_status) to authenticated;

revoke all on function public.update_production_ticket_status(uuid,public.production_ticket_status) from public,anon;
grant execute on function public.update_production_ticket_status(uuid,public.production_ticket_status) to authenticated;

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

comment on table public.production_tickets is 'KDS tickets derived from open/completed service orders; operational state is independent from financial posting.';
