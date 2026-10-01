-- Urbana Café CRM v1.0
-- Core multi-tenant schema for Supabase PostgreSQL.
create extension if not exists pgcrypto;

create type public.member_role as enum ('owner','manager','cashier','waiter','stockkeeper','analyst');
create type public.order_channel as enum ('table','counter','delivery');
create type public.sale_status as enum ('open','completed','cancelled','refunded');
create type public.payment_method as enum ('cash','debit','credit','transfer','mercado_pago','other');
create type public.stock_movement_type as enum ('purchase','sale','adjustment','waste','transfer_in','transfer_out','production');
create type public.cash_movement_type as enum ('sale','expense','withdrawal','deposit','adjustment','refund');

create or replace function public.set_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  legal_name text,
  currency text not null default 'UYU',
  timezone text not null default 'America/Montevideo',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.business_memberships (
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.member_role not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (business_id,user_id)
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(business_id,name)
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  category_id uuid references public.categories(id) on delete set null,
  sku text,
  name text not null,
  description text,
  unit text not null default 'UN',
  sale_price numeric(14,2) not null default 0 check(sale_price >= 0),
  average_cost numeric(14,4) not null default 0 check(average_cost >= 0),
  stock_quantity numeric(14,3) not null default 0,
  min_stock numeric(14,3) not null default 0,
  is_stock_item boolean not null default true,
  is_sellable boolean not null default true,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  phone text,
  email text,
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  phone text,
  email text,
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.cafe_tables (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  seats integer,
  active boolean not null default true,
  unique(business_id,name)
);

create table public.recipes (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  yield_quantity numeric(14,3) not null default 1 check(yield_quantity > 0),
  active boolean not null default true,
  unique(product_id)
);

create table public.recipe_items (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references public.recipes(id) on delete cascade,
  ingredient_product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(14,3) not null check(quantity > 0)
);

create table public.cash_sessions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  opened_by uuid references public.profiles(id),
  opened_at timestamptz not null default now(),
  opening_amount numeric(14,2) not null default 0,
  closed_by uuid references public.profiles(id),
  closed_at timestamptz,
  expected_amount numeric(14,2),
  counted_amount numeric(14,2),
  difference numeric(14,2),
  closing_note text,
  status text not null default 'open' check(status in ('open','closed'))
);

create table public.sales (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  table_id uuid references public.cafe_tables(id) on delete set null,
  cash_session_id uuid references public.cash_sessions(id) on delete set null,
  channel public.order_channel not null default 'counter',
  status public.sale_status not null default 'open',
  subtotal numeric(14,2) not null default 0,
  discount numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  cogs numeric(14,2) not null default 0,
  notes text,
  opened_by uuid references public.profiles(id),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(14,3) not null check(quantity > 0),
  unit_price numeric(14,2) not null check(unit_price >= 0),
  unit_cost numeric(14,4) not null default 0,
  line_total numeric(14,2) generated always as (round(quantity * unit_price,2)) stored,
  line_cogs numeric(14,2) generated always as (round(quantity * unit_cost,2)) stored
);

create table public.sale_payments (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete restrict,
  method public.payment_method not null,
  amount numeric(14,2) not null check(amount > 0),
  created_at timestamptz not null default now()
);

create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  movement_type public.stock_movement_type not null,
  quantity numeric(14,3) not null,
  unit_cost numeric(14,4) not null default 0,
  reference_id uuid,
  note text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.purchases (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  supplier_id uuid references public.suppliers(id) on delete set null,
  invoice_number text,
  total numeric(14,2) not null default 0,
  purchased_at timestamptz not null default now(),
  status text not null default 'posted' check(status in ('draft','posted','cancelled')),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.purchase_items (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid not null references public.purchases(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(14,3) not null check(quantity > 0),
  unit_cost numeric(14,4) not null check(unit_cost >= 0),
  line_total numeric(14,2) generated always as (round(quantity * unit_cost,2)) stored
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  description text not null,
  category text,
  amount numeric(14,2) not null check(amount > 0),
  expense_date date not null default current_date,
  payment_method public.payment_method not null default 'cash',
  posted boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.cash_movements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  cash_session_id uuid references public.cash_sessions(id) on delete restrict,
  movement_type public.cash_movement_type not null,
  amount numeric(14,2) not null check(amount <> 0),
  reference_id uuid,
  description text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.reservations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  table_id uuid references public.cafe_tables(id) on delete set null,
  reservation_at timestamptz not null,
  party_size integer not null default 2,
  status text not null default 'pending' check(status in ('pending','confirmed','seated','cancelled','completed')),
  notes text,
  created_at timestamptz not null default now()
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid references public.profiles(id),
  action text not null,
  entity text not null,
  entity_id uuid,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz not null default now()
);

create index idx_memberships_user on public.business_memberships(user_id);
create index idx_products_business on public.products(business_id);
create index idx_sales_business_date on public.sales(business_id,created_at desc);
create index idx_stock_business_product on public.stock_movements(business_id,product_id,created_at desc);
create index idx_cash_business_date on public.cash_movements(business_id,created_at desc);
create index idx_expenses_business_date on public.expenses(business_id,expense_date desc);

create trigger businesses_updated before update on public.businesses for each row execute function public.set_updated_at();
create trigger profiles_updated before update on public.profiles for each row execute function public.set_updated_at();
create trigger products_updated before update on public.products for each row execute function public.set_updated_at();
create trigger customers_updated before update on public.customers for each row execute function public.set_updated_at();
create trigger sales_updated before update on public.sales for each row execute function public.set_updated_at();

create or replace function public.is_business_member(target_business uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.business_memberships m where m.business_id=target_business and m.user_id=auth.uid() and m.active);
$$;

create or replace function public.has_business_role(target_business uuid, allowed public.member_role[])
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.business_memberships m where m.business_id=target_business and m.user_id=auth.uid() and m.active and m.role=any(allowed));
$$;

alter table public.businesses enable row level security;
alter table public.profiles enable row level security;
alter table public.business_memberships enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.suppliers enable row level security;
alter table public.customers enable row level security;
alter table public.cafe_tables enable row level security;
alter table public.recipes enable row level security;
alter table public.recipe_items enable row level security;
alter table public.cash_sessions enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.sale_payments enable row level security;
alter table public.stock_movements enable row level security;
alter table public.purchases enable row level security;
alter table public.purchase_items enable row level security;
alter table public.expenses enable row level security;
alter table public.cash_movements enable row level security;
alter table public.reservations enable row level security;
alter table public.audit_logs enable row level security;

create policy business_read on public.businesses for select using (public.is_business_member(id));
create policy profile_self on public.profiles for select using (id=auth.uid());
create policy membership_read on public.business_memberships for select using (user_id=auth.uid() or public.has_business_role(business_id,array['owner','manager']::public.member_role[]));

create policy categories_access on public.categories for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));
create policy products_access on public.products for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));
create policy suppliers_access on public.suppliers for all using (public.has_business_role(business_id,array['owner','manager','stockkeeper']::public.member_role[])) with check (public.has_business_role(business_id,array['owner','manager','stockkeeper']::public.member_role[]));
create policy customers_access on public.customers for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));
create policy tables_access on public.cafe_tables for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));
create policy recipes_access on public.recipes for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));
create policy recipe_items_access on public.recipe_items for all using (exists(select 1 from public.recipes r where r.id=recipe_id and public.is_business_member(r.business_id))) with check (exists(select 1 from public.recipes r where r.id=recipe_id and public.is_business_member(r.business_id)));
create policy cash_sessions_access on public.cash_sessions for all using (public.has_business_role(business_id,array['owner','manager','cashier']::public.member_role[])) with check (public.has_business_role(business_id,array['owner','manager','cashier']::public.member_role[]));
create policy sales_access on public.sales for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));
create policy sale_items_access on public.sale_items for all using (exists(select 1 from public.sales s where s.id=sale_id and public.is_business_member(s.business_id))) with check (exists(select 1 from public.sales s where s.id=sale_id and public.is_business_member(s.business_id)));
create policy sale_payments_access on public.sale_payments for all using (exists(select 1 from public.sales s where s.id=sale_id and public.is_business_member(s.business_id))) with check (exists(select 1 from public.sales s where s.id=sale_id and public.is_business_member(s.business_id)));
create policy stock_access on public.stock_movements for all using (public.has_business_role(business_id,array['owner','manager','stockkeeper']::public.member_role[])) with check (public.has_business_role(business_id,array['owner','manager','stockkeeper']::public.member_role[]));
create policy purchases_access on public.purchases for all using (public.has_business_role(business_id,array['owner','manager','stockkeeper']::public.member_role[])) with check (public.has_business_role(business_id,array['owner','manager','stockkeeper']::public.member_role[]));
create policy purchase_items_access on public.purchase_items for all using (exists(select 1 from public.purchases p where p.id=purchase_id and public.has_business_role(p.business_id,array['owner','manager','stockkeeper']::public.member_role[]))) with check (exists(select 1 from public.purchases p where p.id=purchase_id and public.has_business_role(p.business_id,array['owner','manager','stockkeeper']::public.member_role[])));
create policy expenses_access on public.expenses for all using (public.has_business_role(business_id,array['owner','manager','cashier']::public.member_role[])) with check (public.has_business_role(business_id,array['owner','manager','cashier']::public.member_role[]));
create policy cash_movements_access on public.cash_movements for all using (public.has_business_role(business_id,array['owner','manager','cashier']::public.member_role[])) with check (public.has_business_role(business_id,array['owner','manager','cashier']::public.member_role[]));
create policy reservations_access on public.reservations for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));
create policy audit_read on public.audit_logs for select using (public.has_business_role(business_id,array['owner','manager','analyst']::public.member_role[]));

grant usage on schema public to authenticated;
grant select,insert,update,delete on all tables in schema public to authenticated;
grant usage,select on all sequences in schema public to authenticated;
grant execute on function public.is_business_member(uuid) to authenticated;
grant execute on function public.has_business_role(uuid,public.member_role[]) to authenticated;

comment on table public.sales is 'Confirmed sales are the source event for revenue, stock consumption, CMV and customer metrics.';
comment on table public.stock_movements is 'Immutable operational ledger; corrections use compensating movements.';
