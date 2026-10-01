-- Urbana Café: lock down direct writes to transactional ledgers.
-- Client writes go through validated RPCs; ledgers remain readable by authorized staff.

-- High-volume RLS policies should evaluate auth helpers once per statement.
drop policy if exists profile_self on public.profiles;
create policy profile_self on public.profiles
for select to authenticated
using ((select auth.uid())=id);

drop policy if exists profiles_staff_read on public.profiles;
create policy profiles_staff_read on public.profiles
for select to authenticated
using (
  id=(select auth.uid())
  or exists (
    select 1
    from public.business_memberships target
    where target.user_id=profiles.id
      and target.active
      and exists (
        select 1
        from public.business_memberships viewer
        where viewer.business_id=target.business_id
          and viewer.user_id=(select auth.uid())
          and viewer.active
          and viewer.role=any(array['owner','manager']::public.member_role[])
      )
  )
);

drop policy if exists membership_read on public.business_memberships;
create policy membership_read on public.business_memberships
for select to authenticated
using (
  user_id=(select auth.uid())
  or (select public.has_business_role(
    business_id,
    array['owner','manager']::public.member_role[]
  ))
);

-- Sales: read-only from the browser; creation/finalization is transactional.
drop policy if exists sales_read_write on public.sales;
drop policy if exists sales_read on public.sales;
create policy sales_read on public.sales
for select to authenticated
using ((select public.is_business_member(business_id)));

-- Sale items and payments: read-only from the browser; POS RPC writes them atomically.
drop policy if exists sale_items_read_write on public.sale_items;
drop policy if exists sale_items_read on public.sale_items;
create policy sale_items_read on public.sale_items
for select to authenticated
using (
  exists (
    select 1 from public.sales s
    where s.id=sale_id
      and (select public.is_business_member(s.business_id))
  )
);

drop policy if exists sale_payments_read_write on public.sale_payments;
drop policy if exists sale_payments_read on public.sale_payments;
create policy sale_payments_read on public.sale_payments
for select to authenticated
using (
  exists (
    select 1 from public.sales s
    where s.id=sale_id
      and (select public.is_business_member(s.business_id))
  )
);

-- Purchases: creation/posting is now one validated RPC call.
drop policy if exists purchases_read_write on public.purchases;
drop policy if exists purchases_read on public.purchases;
create policy purchases_read on public.purchases
for select to authenticated
using ((select public.has_business_role(
  business_id,
  array['owner','manager','stockkeeper']::public.member_role[]
)));

drop policy if exists purchase_items_read_write on public.purchase_items;
drop policy if exists purchase_items_read on public.purchase_items;
create policy purchase_items_read on public.purchase_items
for select to authenticated
using (
  exists (
    select 1 from public.purchases p
    where p.id=purchase_id
      and (select public.has_business_role(
        p.business_id,
        array['owner','manager','stockkeeper']::public.member_role[]
      ))
  )
);

-- Operational/financial ledgers are written only by RPCs/triggers.
drop policy if exists cash_sessions_access on public.cash_sessions;
drop policy if exists cash_sessions_read on public.cash_sessions;
create policy cash_sessions_read on public.cash_sessions
for select to authenticated
using ((select public.has_business_role(
  business_id,
  array['owner','manager','cashier']::public.member_role[]
)));

drop policy if exists stock_access on public.stock_movements;
drop policy if exists stock_movements_read on public.stock_movements;
create policy stock_movements_read on public.stock_movements
for select to authenticated
using ((select public.has_business_role(
  business_id,
  array['owner','manager','stockkeeper','analyst']::public.member_role[]
)));

drop policy if exists expenses_access on public.expenses;
drop policy if exists expenses_read on public.expenses;
create policy expenses_read on public.expenses
for select to authenticated
using ((select public.has_business_role(
  business_id,
  array['owner','manager','cashier','analyst']::public.member_role[]
)));

drop policy if exists cash_movements_access on public.cash_movements;
drop policy if exists cash_movements_read on public.cash_movements;
create policy cash_movements_read on public.cash_movements
for select to authenticated
using ((select public.has_business_role(
  business_id,
  array['owner','manager','cashier','analyst']::public.member_role[]
)));
