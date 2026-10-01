-- Urbana Café: operational inventory and product-performance reporting.
-- Views are security_invoker so product/sale/stock RLS remains effective for callers.

create index if not exists idx_sale_refund_payments_created_by
  on public.sale_refund_payments (created_by);

create index if not exists idx_sales_business_status_completed_at
  on public.sales (business_id,status,completed_at desc);

create index if not exists idx_sale_items_sale_product
  on public.sale_items (sale_id,product_id);

create or replace view public.business_inventory_summary
with (security_invoker=true)
as
select
  p.business_id,
  p.id as product_id,
  p.name as product_name,
  p.sku,
  p.unit,
  p.average_cost::numeric(14,4) as average_cost,
  p.stock_quantity::numeric(14,3) as stock_quantity,
  p.min_stock::numeric(14,3) as min_stock,
  p.active,
  p.is_sellable,
  round(p.stock_quantity * p.average_cost,2)::numeric(14,2) as stock_value,
  (p.stock_quantity <= p.min_stock) as below_minimum,
  (p.stock_quantity <= 0) as out_of_stock
from public.products p
where p.is_stock_item=true;

grant select on public.business_inventory_summary to authenticated;

create or replace view public.business_product_sales_daily
with (security_invoker=true)
as
with gross as (
  select
    s.business_id,
    (s.completed_at at time zone b.timezone)::date as report_date,
    si.product_id,
    sum(si.quantity)::numeric(14,3) as gross_quantity,
    sum(si.line_total)::numeric(14,2) as gross_revenue,
    sum(si.line_cogs)::numeric(14,2) as gross_cogs,
    count(distinct s.id)::bigint as gross_sales_count
  from public.sales s
  join public.businesses b on b.id=s.business_id
  join public.sale_items si on si.sale_id=s.id
  where s.status in ('completed','refunded')
    and s.completed_at is not null
  group by s.business_id,(s.completed_at at time zone b.timezone)::date,si.product_id
),
refunds as (
  select
    s.business_id,
    (s.updated_at at time zone b.timezone)::date as report_date,
    si.product_id,
    sum(si.quantity)::numeric(14,3) as refunded_quantity,
    sum(si.line_total)::numeric(14,2) as refunded_revenue,
    sum(si.line_cogs)::numeric(14,2) as refunded_cogs,
    count(distinct s.id)::bigint as refunds_count
  from public.sales s
  join public.businesses b on b.id=s.business_id
  join public.sale_items si on si.sale_id=s.id
  where s.status='refunded'
    and s.updated_at is not null
  group by s.business_id,(s.updated_at at time zone b.timezone)::date,si.product_id
)
select
  coalesce(g.business_id,r.business_id) as business_id,
  coalesce(g.report_date,r.report_date) as report_date,
  p.id as product_id,
  p.name as product_name,
  p.unit,
  coalesce(g.gross_quantity,0)::numeric(14,3) as gross_quantity,
  coalesce(g.gross_revenue,0)::numeric(14,2) as gross_revenue,
  coalesce(g.gross_cogs,0)::numeric(14,2) as gross_cogs,
  coalesce(r.refunded_quantity,0)::numeric(14,3) as refunded_quantity,
  coalesce(r.refunded_revenue,0)::numeric(14,2) as refunded_revenue,
  coalesce(r.refunded_cogs,0)::numeric(14,2) as refunded_cogs,
  (coalesce(g.gross_quantity,0)-coalesce(r.refunded_quantity,0))::numeric(14,3) as net_quantity,
  (coalesce(g.gross_revenue,0)-coalesce(r.refunded_revenue,0))::numeric(14,2) as net_revenue,
  (coalesce(g.gross_cogs,0)-coalesce(r.refunded_cogs,0))::numeric(14,2) as net_cogs,
  (coalesce(g.gross_revenue,0)-coalesce(r.refunded_revenue,0)
    -coalesce(g.gross_cogs,0)+coalesce(r.refunded_cogs,0))::numeric(14,2) as gross_margin,
  coalesce(g.gross_sales_count,0)::bigint as gross_sales_count,
  coalesce(r.refunds_count,0)::bigint as refunds_count
from gross g
full outer join refunds r
  on r.business_id=g.business_id
 and r.report_date=g.report_date
 and r.product_id=g.product_id
join public.products p
  on p.id=coalesce(g.product_id,r.product_id)
where p.is_stock_item=true or p.is_sellable=true;

grant select on public.business_product_sales_daily to authenticated;

create or replace view public.business_stock_movement_daily
with (security_invoker=true)
as
select
  sm.business_id,
  (sm.created_at at time zone b.timezone)::date as report_date,
  sm.product_id,
  p.name as product_name,
  p.unit,
  sm.movement_type,
  count(*)::bigint as movement_count,
  sum(sm.quantity)::numeric(14,3) as quantity,
  sum(sm.quantity * sm.unit_cost)::numeric(14,2) as value,
  sum(abs(sm.quantity * sm.unit_cost))::numeric(14,2) as absolute_value
from public.stock_movements sm
join public.businesses b on b.id=sm.business_id
join public.products p on p.id=sm.product_id
group by
  sm.business_id,
  (sm.created_at at time zone b.timezone)::date,
  sm.product_id,
  p.name,
  p.unit,
  sm.movement_type;

grant select on public.business_stock_movement_daily to authenticated;
