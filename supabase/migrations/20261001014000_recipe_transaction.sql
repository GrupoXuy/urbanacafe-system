-- Urbana Café: atomic recipe maintenance.
-- Invoker function: underlying RLS policies remain the authorization boundary.

create or replace function public.save_recipe_transaction(
  p_business_id uuid,
  p_recipe_id uuid default null,
  p_product_id uuid default null,
  p_yield_quantity numeric default 1,
  p_items jsonb default '[]'::jsonb
)
returns public.recipes
language plpgsql
set search_path=public
as $$
declare
  v_recipe public.recipes%rowtype;
  v_item jsonb;
  v_ingredient_id uuid;
  v_quantity numeric(14,3);
  v_product_business uuid;
  v_ingredient_business uuid;
  v_recipe_business uuid;
  v_item_count integer;
  v_distinct_count integer;
begin
  if not public.has_business_role(
    p_business_id,
    array['owner','manager','stockkeeper']::public.member_role[]
  ) then
    raise exception 'Sem permissão para manter fichas técnicas';
  end if;

  if not exists (
    select 1
    from public.businesses
    where id=p_business_id
      and active
  ) then
    raise exception 'Negócio inválido ou inativo';
  end if;

  if p_product_id is null then
    raise exception 'Produto acabado é obrigatório';
  end if;

  if p_yield_quantity is null or p_yield_quantity<=0 then
    raise exception 'Rendimento deve ser maior que zero';
  end if;

  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then
    raise exception 'A ficha técnica deve conter pelo menos um ingrediente';
  end if;

  select business_id
  into v_product_business
  from public.products
  where id=p_product_id
    and active
  for update;

  if not found or v_product_business<>p_business_id then
    raise exception 'Produto acabado inválido ou pertence a outro negócio';
  end if;

  select jsonb_array_length(p_items),
         count(distinct nullif(trim(value->>'ingredient_product_id'),'')::uuid)
  into v_item_count,v_distinct_count
  from jsonb_array_elements(p_items);

  if v_item_count<>v_distinct_count then
    raise exception 'Não repita o mesmo ingrediente na ficha técnica';
  end if;

  if p_recipe_id is null then
    insert into public.recipes(
      business_id,product_id,yield_quantity,active
    )
    values(
      p_business_id,p_product_id,p_yield_quantity,true
    )
    returning * into v_recipe;
  else
    select business_id
    into v_recipe_business
    from public.recipes
    where id=p_recipe_id
    for update;

    if not found or v_recipe_business<>p_business_id then
      raise exception 'Ficha técnica inválida ou pertence a outro negócio';
    end if;

    update public.recipes
    set product_id=p_product_id,
        yield_quantity=p_yield_quantity,
        active=true
    where id=p_recipe_id
    returning * into v_recipe;

    delete from public.recipe_items
    where recipe_id=v_recipe.id;
  end if;

  for v_item in
    select value
    from jsonb_array_elements(p_items)
  loop
    begin
      v_ingredient_id := nullif(trim(v_item->>'ingredient_product_id'),'')::uuid;
      v_quantity := (v_item->>'quantity')::numeric;
    exception when others then
      raise exception 'Ingrediente inválido';
    end;

    if v_ingredient_id is null or v_quantity is null or v_quantity<=0 then
      raise exception 'Quantidade do ingrediente deve ser maior que zero';
    end if;

    if v_ingredient_id=p_product_id then
      raise exception 'O produto acabado não pode ser ingrediente da própria ficha';
    end if;

    select business_id
    into v_ingredient_business
    from public.products
    where id=v_ingredient_id
      and active
      and is_stock_item
    for update;

    if not found or v_ingredient_business<>p_business_id then
      raise exception 'Ingrediente inválido, sem estoque ou pertence a outro negócio';
    end if;

    insert into public.recipe_items(
      recipe_id,ingredient_product_id,quantity
    )
    values(
      v_recipe.id,v_ingredient_id,v_quantity
    );
  end loop;

  return v_recipe;
end;
$$;

revoke all on function public.save_recipe_transaction(uuid,uuid,uuid,numeric,jsonb) from public;
revoke all on function public.save_recipe_transaction(uuid,uuid,uuid,numeric,jsonb) from anon;
grant execute on function public.save_recipe_transaction(uuid,uuid,uuid,numeric,jsonb) to authenticated;
