-- Urbana Café: atomic purchase creation and posting.
-- Creates the purchase, its items and stock/cash effects in one transaction.

create or replace function public.create_purchase_transaction(
  p_business_id uuid,
  p_supplier_id uuid default null,
  p_invoice_number text default null,
  p_payment_method public.payment_method default 'cash',
  p_items jsonb default '[]'::jsonb
)
returns public.purchases
language plpgsql
security definer
set search_path=public
as $$
declare
  v_purchase public.purchases%rowtype;
  v_item jsonb;
  v_product_id uuid;
  v_quantity numeric(14,3);
  v_unit_cost numeric(14,4);
  v_product_business uuid;
  v_supplier_business uuid;
begin
  if not public.has_business_role(
    p_business_id,
    array['owner','manager','stockkeeper']::public.member_role[]
  ) then
    raise exception 'Sem permissão para registrar compras';
  end if;

  if not exists (
    select 1
    from public.businesses
    where id=p_business_id
      and active
  ) then
    raise exception 'Negócio inválido ou inativo';
  end if;

  if p_supplier_id is not null then
    select business_id
    into v_supplier_business
    from public.suppliers
    where id=p_supplier_id
      and active
    for update;

    if not found or v_supplier_business<>p_business_id then
      raise exception 'Fornecedor inválido ou pertence a outro negócio';
    end if;
  end if;

  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then
    raise exception 'A compra deve conter pelo menos um item';
  end if;

  insert into public.purchases(
    business_id,supplier_id,invoice_number,status,payment_method,total,created_by
  )
  values(
    p_business_id,p_supplier_id,nullif(trim(p_invoice_number),''),'draft',p_payment_method,0,auth.uid()
  )
  returning * into v_purchase;

  for v_item in
    select value
    from jsonb_array_elements(p_items)
  loop
    begin
      v_product_id := nullif(trim(v_item->>'product_id'),'')::uuid;
      v_quantity := (v_item->>'quantity')::numeric;
      v_unit_cost := (v_item->>'unit_cost')::numeric;
    exception when others then
      raise exception 'Item de compra inválido';
    end;

    if v_product_id is null or v_quantity is null or v_quantity<=0 or v_unit_cost is null or v_unit_cost<0 then
      raise exception 'Quantidade e custo do item devem ser válidos';
    end if;

    select business_id
    into v_product_business
    from public.products
    where id=v_product_id
      and active
    for update;

    if not found or v_product_business<>p_business_id then
      raise exception 'Produto da compra inválido ou pertence a outro negócio';
    end if;

    insert into public.purchase_items(purchase_id,product_id,quantity,unit_cost)
    values(v_purchase.id,v_product_id,v_quantity,v_unit_cost);
  end loop;

  select * into v_purchase
  from public.post_purchase(v_purchase.id);

  return v_purchase;
end;
$$;

revoke all on function public.create_purchase_transaction(uuid,uuid,text,public.payment_method,jsonb) from public;
revoke all on function public.create_purchase_transaction(uuid,uuid,text,public.payment_method,jsonb) from anon;
grant execute on function public.create_purchase_transaction(uuid,uuid,text,public.payment_method,jsonb) to authenticated;
