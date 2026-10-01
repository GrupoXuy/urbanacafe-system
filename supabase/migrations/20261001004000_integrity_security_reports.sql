-- Urbana Café: integrity, role hardening and reporting layer.
-- This migration is additive and intended to run after 20261001001000.

-- ---------------------------------------------------------------------------
-- SECURITY DEFINER function execution
-- ---------------------------------------------------------------------------
revoke all on function public.is_business_member(uuid) from public;
revoke all on function public.is_business_member(uuid) from anon;
grant execute on function public.is_business_member(uuid) to authenticated;

revoke all on function public.has_business_role(uuid,public.member_role[]) from public;
revoke all on function public.has_business_role(uuid,public.member_role[]) from anon;
grant execute on function public.has_business_role(uuid,public.member_role[]) to authenticated;

revoke all on function public.finalize_sale(uuid,uuid) from public;
revoke all on function public.finalize_sale(uuid,uuid) from anon;
grant execute on function public.finalize_sale(uuid,uuid) to authenticated;

revoke all on function public.post_purchase(uuid) from public;
revoke all on function public.post_purchase(uuid) from anon;
grant execute on function public.post_purchase(uuid) to authenticated;

revoke all on function public.open_cash_session(uuid,numeric) from public;
revoke all on function public.open_cash_session(uuid,numeric) from anon;
grant execute on function public.open_cash_session(uuid,numeric) to authenticated;

revoke all on function public.close_cash_session(uuid,numeric,text) from public;
revoke all on function public.close_cash_session(uuid,numeric,text) from anon;
grant execute on function public.close_cash_session(uuid,numeric,text) to authenticated;

-- ---------------------------------------------------------------------------
-- Financial structure
-- ---------------------------------------------------------------------------
alter table public.purchases
  add column if not exists payment_method public.payment_method not null default 'cash';

alter table public.purchases
  alter column status set default 'draft';

create unique index if not exists ux_cash_sessions_one_open_per_business
  on public.cash_sessions(business_id)
  where status='open';

-- ---------------------------------------------------------------------------
-- Immutable / cross-tenant integrity
-- ---------------------------------------------------------------------------
create or replace function public.validate_sale_header_integrity()
returns trigger
language plpgsql
as $$
begin
  if new.customer_id is not null and not exists (
    select 1 from public.customers c
    where c.id=new.customer_id and c.business_id=new.business_id
  ) then
    raise exception 'Cliente pertence a outro negócio';
  end if;

  if new.table_id is not null and not exists (
    select 1 from public.cafe_tables t
    where t.id=new.table_id and t.business_id=new.business_id
  ) then
    raise exception 'Mesa pertence a outro negócio';
  end if;

  if new.cash_session_id is not null and not exists (
    select 1 from public.cash_sessions cs
    where cs.id=new.cash_session_id and cs.business_id=new.business_id
  ) then
    raise exception 'Sessão de caixa pertence a outro negócio';
  end if;

  if tg_op='UPDATE' and new.business_id<>old.business_id then
    raise exception 'O negócio da venda não pode ser alterado';
  end if;

  return new;
end;
$$;

create or replace function public.validate_sale_item_integrity()
returns trigger
language plpgsql
as $$
declare
  v_sale_business uuid;
  v_product_business uuid;
begin
  select business_id into v_sale_business from public.sales where id=new.sale_id;
  select business_id into v_product_business from public.products where id=new.product_id;

  if v_sale_business is null or v_product_business is null then
    raise exception 'Venda ou produto não encontrado';
  end if;

  if v_sale_business<>v_product_business then
    raise exception 'Produto pertence a outro negócio';
  end if;

  return new;
end;
$$;

create or replace function public.validate_purchase_integrity()
returns trigger
language plpgsql
as $$
declare
  v_purchase_business uuid;
  v_product_business uuid;
begin
  select business_id into v_purchase_business from public.purchases where id=new.purchase_id;
  select business_id into v_product_business from public.products where id=new.product_id;

  if v_purchase_business is null or v_product_business is null then
    raise exception 'Compra ou produto não encontrado';
  end if;

  if v_purchase_business<>v_product_business then
    raise exception 'Produto pertence a outro negócio';
  end if;

  return new;
end;
$$;

create or replace function public.validate_recipe_item_integrity()
returns trigger
language plpgsql
as $$
declare
  v_recipe_business uuid;
  v_product_business uuid;
begin
  select business_id into v_recipe_business from public.recipes where id=new.recipe_id;
  select business_id into v_product_business from public.products where id=new.ingredient_product_id;

  if v_recipe_business is null or v_product_business is null then
    raise exception 'Ficha técnica ou ingrediente não encontrado';
  end if;

  if v_recipe_business<>v_product_business then
    raise exception 'Ingrediente pertence a outro negócio';
  end if;

  return new;
end;
$$;

create or replace function public.validate_product_category_integrity()
returns trigger
language plpgsql
as $$
begin
  if new.category_id is not null and not exists (
    select 1 from public.categories c
    where c.id=new.category_id and c.business_id=new.business_id
  ) then
    raise exception 'Categoria pertence a outro negócio';
  end if;

  if tg_op='UPDATE' and new.business_id<>old.business_id then
    raise exception 'O negócio do produto não pode ser alterado';
  end if;

  return new;
end;
$$;

create or replace function public.validate_purchase_supplier_integrity()
returns trigger
language plpgsql
as $$
begin
  if new.supplier_id is not null and not exists (
    select 1 from public.suppliers s
    where s.id=new.supplier_id and s.business_id=new.business_id
  ) then
    raise exception 'Fornecedor pertence a outro negócio';
  end if;

  if tg_op='UPDATE' and new.business_id<>old.business_id then
    raise exception 'O negócio da compra não pode ser alterado';
  end if;

  return new;
end;
$$;

drop trigger if exists sale_header_integrity on public.sales;
create trigger sale_header_integrity
before insert or update on public.sales
for each row execute function public.validate_sale_header_integrity();

drop trigger if exists sale_item_integrity on public.sale_items;
create trigger sale_item_integrity
before insert or update on public.sale_items
for each row execute function public.validate_sale_item_integrity();

drop trigger if exists purchase_item_integrity on public.purchase_items;
create trigger purchase_item_integrity
before insert or update on public.purchase_items
for each row execute function public.validate_purchase_integrity();

drop trigger if exists recipe_item_integrity on public.recipe_items;
create trigger recipe_item_integrity
before insert or update on public.recipe_items
for each row execute function public.validate_recipe_item_integrity();

drop trigger if exists product_category_integrity on public.products;
create trigger product_category_integrity
before insert or update on public.products
for each row execute function public.validate_product_category_integrity();

drop trigger if exists purchase_supplier_integrity on public.purchases;
create trigger purchase_supplier_integrity
before insert or update on public.purchases
for each row execute function public.validate_purchase_supplier_integrity();

-- ---------------------------------------------------------------------------
-- Protect posted financial/stock records from client-side deletion or mutation
-- ---------------------------------------------------------------------------
create or replace function public.prevent_ledger_delete()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Registro operacional/financeiro não pode ser apagado; use cancelamento ou ajuste compensatório';
end;
$$;

create or replace function public.prevent_closed_or_posted_mutation()
returns trigger
language plpgsql
as $$
begin
  if tg_table_name='sales' and old.status in ('completed','cancelled','refunded') then
    raise exception 'Venda finalizada não pode ser alterada';
  end if;

  if tg_table_name='purchases' and old.status in ('posted','cancelled') then
    raise exception 'Compra lançada não pode ser alterada';
  end if;

  if tg_table_name='cash_sessions' and old.status='closed' then
    raise exception 'Caixa fechado não pode ser alterado';
  end if;

  return new;
end;
$$;

drop trigger if exists no_delete_sales on public.sales;
create trigger no_delete_sales before delete on public.sales
for each row execute function public.prevent_ledger_delete();

drop trigger if exists no_delete_sale_items on public.sale_items;
create trigger no_delete_sale_items before delete on public.sale_items
for each row execute function public.prevent_ledger_delete();

drop trigger if exists no_delete_sale_payments on public.sale_payments;
create trigger no_delete_sale_payments before delete on public.sale_payments
for each row execute function public.prevent_ledger_delete();

drop trigger if exists no_delete_stock_movements on public.stock_movements;
create trigger no_delete_stock_movements before delete on public.stock_movements
for each row execute function public.prevent_ledger_delete();

drop trigger if exists no_delete_purchases on public.purchases;
create trigger no_delete_purchases before delete on public.purchases
for each row execute function public.prevent_ledger_delete();

drop trigger if exists no_delete_purchase_items on public.purchase_items;
create trigger no_delete_purchase_items before delete on public.purchase_items
for each row execute function public.prevent_ledger_delete();

drop trigger if exists no_delete_cash_sessions on public.cash_sessions;
create trigger no_delete_cash_sessions before delete on public.cash_sessions
for each row execute function public.prevent_ledger_delete();

drop trigger if exists no_delete_cash_movements on public.cash_movements;
create trigger no_delete_cash_movements before delete on public.cash_movements
for each row execute function public.prevent_ledger_delete();

drop trigger if exists no_delete_expenses on public.expenses;
create trigger no_delete_expenses before delete on public.expenses
for each row execute function public.prevent_ledger_delete();

drop trigger if exists protect_posted_sales on public.sales;
create trigger protect_posted_sales before update on public.sales
for each row execute function public.prevent_closed_or_posted_mutation();

drop trigger if exists protect_posted_purchases on public.purchases;
create trigger protect_posted_purchases before update on public.purchases
for each row execute function public.prevent_closed_or_posted_mutation();

drop trigger if exists protect_closed_cash on public.cash_sessions;
create trigger protect_closed_cash before update on public.cash_sessions
for each row execute function public.prevent_closed_or_posted_mutation();

-- ---------------------------------------------------------------------------
-- Cash correctness: opening deposit is already represented by a movement,
-- so closing expected amount must sum movements once (not opening + movements).
-- ---------------------------------------------------------------------------
create or replace function public.close_cash_session(
  p_session_id uuid,
  p_counted_amount numeric,
  p_note text default null
)
returns public.cash_sessions
language plpgsql
security definer
set search_path=public
as $$
declare
  v_result public.cash_sessions;
  v_expected numeric(14,2);
begin
  select * into v_result
  from public.cash_sessions
  where id=p_session_id
  for update;

  if not found then raise exception 'Caixa não encontrado'; end if;
  if not public.has_business_role(v_result.business_id,array['owner','manager','cashier']::public.member_role[]) then
    raise exception 'Sem permissão';
  end if;
  if v_result.status<>'open' then raise exception 'Caixa já está fechado'; end if;

  select round(coalesce(sum(amount),0),2)
    into v_expected
  from public.cash_movements
  where cash_session_id=p_session_id;

  update public.cash_sessions
  set status='closed',
      closed_by=auth.uid(),
      closed_at=now(),
      expected_amount=v_expected,
      counted_amount=p_counted_amount,
      difference=round(p_counted_amount-v_expected,2),
      closing_note=p_note
  where id=p_session_id
  returning * into v_result;

  return v_result;
end;
$$;

grant execute on function public.close_cash_session(uuid,numeric,text) to authenticated;
revoke all on function public.close_cash_session(uuid,numeric,text) from anon;

-- ---------------------------------------------------------------------------
-- Expense transaction: one server-side operation handles expense and cash.
-- ---------------------------------------------------------------------------
create or replace function public.record_expense(
  p_business_id uuid,
  p_description text,
  p_category text,
  p_amount numeric,
  p_expense_date date,
  p_payment_method public.payment_method
)
returns public.expenses
language plpgsql
security definer
set search_path=public
as $$
declare
  v_expense public.expenses;
  v_session uuid;
begin
  if not public.has_business_role(p_business_id,array['owner','manager','cashier']::public.member_role[]) then
    raise exception 'Sem permissão';
  end if;

  if p_amount is null or p_amount<=0 then
    raise exception 'Valor da despesa deve ser maior que zero';
  end if;

  if p_payment_method='cash' then
    select id into v_session
    from public.cash_sessions
    where business_id=p_business_id and status='open'
    limit 1;

    if v_session is null then
      raise exception 'Abra o caixa antes de lançar uma despesa em dinheiro';
    end if;
  end if;

  insert into public.expenses(
    business_id,description,category,amount,expense_date,payment_method,posted,created_by
  )
  values(
    p_business_id,trim(p_description),nullif(trim(p_category),''),round(p_amount,2),
    coalesce(p_expense_date,current_date),p_payment_method,true,auth.uid()
  )
  returning * into v_expense;

  if p_payment_method='cash' then
    insert into public.cash_movements(
      business_id,cash_session_id,movement_type,amount,reference_id,description,created_by
    )
    values(
      p_business_id,v_session,'expense',-v_expense.amount,v_expense.id,
      'Despesa: '||v_expense.description,auth.uid()
    );
  end if;

  return v_expense;
end;
$$;

revoke all on function public.record_expense(uuid,text,text,numeric,date,public.payment_method) from public;
revoke all on function public.record_expense(uuid,text,text,numeric,date,public.payment_method) from anon;
grant execute on function public.record_expense(uuid,text,text,numeric,date,public.payment_method) to authenticated;

-- ---------------------------------------------------------------------------
-- Rebuild financial RLS with read-only ledgers and role-specific writes.
-- ---------------------------------------------------------------------------
drop policy if exists cash_sessions_access on public.cash_sessions;
create policy cash_sessions_read on public.cash_sessions
for select to authenticated
using (public.has_business_role(business_id,array['owner','manager','cashier']::public.member_role[]));

drop policy if exists cash_movements_access on public.cash_movements;
create policy cash_movements_read on public.cash_movements
for select to authenticated
using (public.has_business_role(business_id,array['owner','manager','cashier','analyst']::public.member_role[]));

drop policy if exists stock_access on public.stock_movements;
create policy stock_movements_read on public.stock_movements
for select to authenticated
using (public.has_business_role(business_id,array['owner','manager','stockkeeper','analyst']::public.member_role[]));

drop policy if exists expenses_access on public.expenses;
create policy expenses_read on public.expenses
for select to authenticated
using (public.has_business_role(business_id,array['owner','manager','cashier','analyst']::public.member_role[]));

drop policy if exists purchases_access on public.purchases;
create policy purchases_read_write on public.purchases
for all to authenticated
using (public.has_business_role(business_id,array['owner','manager','stockkeeper']::public.member_role[]))
with check (public.has_business_role(business_id,array['owner','manager','stockkeeper']::public.member_role[]));

drop policy if exists purchase_items_access on public.purchase_items;
create policy purchase_items_read_write on public.purchase_items
for all to authenticated
using (exists(
  select 1 from public.purchases p
  where p.id=purchase_id
  and public.has_business_role(p.business_id,array['owner','manager','stockkeeper']::public.member_role[])
))
with check (exists(
  select 1 from public.purchases p
  where p.id=purchase_id
  and public.has_business_role(p.business_id,array['owner','manager','stockkeeper']::public.member_role[])
));

drop policy if exists sales_access on public.sales;
create policy sales_read_write on public.sales
for all to authenticated
using (public.is_business_member(business_id))
with check (public.is_business_member(business_id));

drop policy if exists sale_items_access on public.sale_items;
create policy sale_items_read_write on public.sale_items
for all to authenticated
using (exists(
  select 1 from public.sales s
  where s.id=sale_id and public.is_business_member(s.business_id)
))
with check (exists(
  select 1 from public.sales s
  where s.id=sale_id and public.is_business_member(s.business_id)
));

drop policy if exists sale_payments_access on public.sale_payments;
create policy sale_payments_read_write on public.sale_payments
for all to authenticated
using (exists(
  select 1 from public.sales s
  where s.id=sale_id and public.is_business_member(s.business_id)
))
with check (exists(
  select 1 from public.sales s
  where s.id=sale_id and public.is_business_member(s.business_id)
));

drop policy if exists products_access on public.products;
create policy products_read on public.products
for select to authenticated
using (public.is_business_member(business_id));

create policy products_write on public.products
for insert to authenticated
with check (public.has_business_role(business_id,array['owner','manager']::public.member_role[]));

create policy products_update on public.products
for update to authenticated
using (public.has_business_role(business_id,array['owner','manager']::public.member_role[]))
with check (public.has_business_role(business_id,array['owner','manager']::public.member_role[]));

create policy products_delete on public.products
for delete to authenticated
using (public.has_business_role(business_id,array['owner','manager']::public.member_role[]));

drop policy if exists categories_access on public.categories;
create policy categories_read on public.categories
for select to authenticated
using (public.is_business_member(business_id));
create policy categories_write on public.categories
for insert to authenticated
with check (public.has_business_role(business_id,array['owner','manager']::public.member_role[]));
create policy categories_update on public.categories
for update to authenticated
using (public.has_business_role(business_id,array['owner','manager']::public.member_role[]))
with check (public.has_business_role(business_id,array['owner','manager']::public.member_role[]));
create policy categories_delete on public.categories
for delete to authenticated
using (public.has_business_role(business_id,array['owner','manager']::public.member_role[]));

drop policy if exists tables_access on public.cafe_tables;
create policy tables_read on public.cafe_tables
for select to authenticated
using (public.is_business_member(business_id));
create policy tables_write on public.cafe_tables
for insert to authenticated
with check (public.has_business_role(business_id,array['owner','manager']::public.member_role[]));
create policy tables_update on public.cafe_tables
for update to authenticated
using (public.has_business_role(business_id,array['owner','manager']::public.member_role[]))
with check (public.has_business_role(business_id,array['owner','manager']::public.member_role[]));
create policy tables_delete on public.cafe_tables
for delete to authenticated
using (public.has_business_role(business_id,array['owner','manager']::public.member_role[]));

drop policy if exists recipes_access on public.recipes;
create policy recipes_read on public.recipes
for select to authenticated
using (public.is_business_member(business_id));
create policy recipes_write on public.recipes
for insert to authenticated
with check (public.has_business_role(business_id,array['owner','manager','stockkeeper']::public.member_role[]));
create policy recipes_update on public.recipes
for update to authenticated
using (public.has_business_role(business_id,array['owner','manager','stockkeeper']::public.member_role[]))
with check (public.has_business_role(business_id,array['owner','manager','stockkeeper']::public.member_role[]));
create policy recipes_delete on public.recipes
for delete to authenticated
using (public.has_business_role(business_id,array['owner','manager','stockkeeper']::public.member_role[]));

drop policy if exists recipe_items_access on public.recipe_items;
create policy recipe_items_read on public.recipe_items
for select to authenticated
using (exists(select 1 from public.recipes r where r.id=recipe_id and public.is_business_member(r.business_id)));
create policy recipe_items_write on public.recipe_items
for insert to authenticated
with check (exists(select 1 from public.recipes r where r.id=recipe_id and public.has_business_role(r.business_id,array['owner','manager','stockkeeper']::public.member_role[])));
create policy recipe_items_update on public.recipe_items
for update to authenticated
using (exists(select 1 from public.recipes r where r.id=recipe_id and public.has_business_role(r.business_id,array['owner','manager','stockkeeper']::public.member_role[])))
with check (exists(select 1 from public.recipes r where r.id=recipe_id and public.has_business_role(r.business_id,array['owner','manager','stockkeeper']::public.member_role[])));
create policy recipe_items_delete on public.recipe_items
for delete to authenticated
using (exists(select 1 from public.recipes r where r.id=recipe_id and public.has_business_role(r.business_id,array['owner','manager','stockkeeper']::public.member_role[])));

-- ---------------------------------------------------------------------------
-- Reporting views (security_invoker keeps source-table RLS effective).
-- ---------------------------------------------------------------------------
create or replace view public.business_dashboard
with (security_invoker=true)
as
select
  s.business_id,
  current_date as report_date,
  coalesce(sum(case
    when s.status='completed' and s.created_at::date=current_date then s.total
    else 0 end),0)::numeric(14,2) as revenue,
  coalesce(sum(case
    when s.status='completed' and s.created_at::date=current_date then s.cogs
    else 0 end),0)::numeric(14,2) as cogs,
  count(*) filter(where s.status='completed' and s.created_at::date=current_date) as sales_count
from public.sales s
where s.created_at::date=current_date
group by s.business_id;

create or replace view public.business_financial_daily
with (security_invoker=true)
as
with sales as (
  select
    business_id,
    created_at::date as report_date,
    sum(total) filter(where status='completed')::numeric(14,2) as revenue,
    sum(cogs) filter(where status='completed')::numeric(14,2) as cogs,
    count(*) filter(where status='completed') as sales_count
  from public.sales
  group by business_id,created_at::date
),
expenses as (
  select
    business_id,
    expense_date as report_date,
    sum(amount) filter(where posted)::numeric(14,2) as expenses
  from public.expenses
  group by business_id,expense_date
),
cash as (
  select
    business_id,
    created_at::date as report_date,
    sum(amount) filter(where amount>0)::numeric(14,2) as cash_in,
    abs(sum(amount) filter(where amount<0))::numeric(14,2) as cash_out
  from public.cash_movements
  group by business_id,created_at::date
)
select
  coalesce(s.business_id,e.business_id,c.business_id) as business_id,
  coalesce(s.report_date,e.report_date,c.report_date) as report_date,
  coalesce(s.revenue,0)::numeric(14,2) as revenue,
  coalesce(s.cogs,0)::numeric(14,2) as cogs,
  coalesce(s.sales_count,0)::bigint as sales_count,
  coalesce(e.expenses,0)::numeric(14,2) as expenses,
  coalesce(c.cash_in,0)::numeric(14,2) as cash_in,
  coalesce(c.cash_out,0)::numeric(14,2) as cash_out,
  (coalesce(s.revenue,0)-coalesce(s.cogs,0))::numeric(14,2) as gross_profit,
  (coalesce(s.revenue,0)-coalesce(s.cogs,0)-coalesce(e.expenses,0))::numeric(14,2) as net_profit
from sales s
full outer join expenses e on e.business_id=s.business_id and e.report_date=s.report_date
full outer join cash c on c.business_id=coalesce(s.business_id,e.business_id)
                     and c.report_date=coalesce(s.report_date,e.report_date);

grant select on public.business_dashboard to authenticated;
grant select on public.business_financial_daily to authenticated;
