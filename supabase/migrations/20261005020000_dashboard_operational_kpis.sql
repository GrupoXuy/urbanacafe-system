-- Urbana Café: enrich the main dashboard with financial and operational KPIs.
-- The view remains security_invoker so tenant RLS applies to all underlying sources.

create or replace view public.business_dashboard
with (security_invoker=true)
as
with today_financial as (
  select
    f.business_id,
    f.report_date,
    f.revenue,
    f.cogs,
    f.sales_count,
    f.refunds_count,
    f.expenses,
    f.gross_profit,
    f.net_profit
  from public.business_financial_daily f
),
inventory as (
  select
    i.business_id,
    round(coalesce(sum(i.stock_value) filter(where i.active),0),2)::numeric(14,2) as stock_value,
    count(*) filter(where i.active)::bigint as stock_items,
    count(*) filter(where i.active and i.below_minimum)::bigint as low_stock_count,
    count(*) filter(where i.active and i.out_of_stock)::bigint as out_of_stock_count
  from public.business_inventory_summary i
  group by i.business_id
),
cash as (
  select
    cs.business_id,
    count(*) filter(where cs.status='open')::bigint as open_cash_sessions
  from public.cash_sessions cs
  group by cs.business_id
)
select
  b.id as business_id,
  (current_timestamp at time zone b.timezone)::date as report_date,
  coalesce(f.revenue,0)::numeric(14,2) as revenue,
  coalesce(f.cogs,0)::numeric(14,2) as cogs,
  coalesce(f.sales_count,0)::bigint as sales_count,
  coalesce(f.refunds_count,0)::bigint as refunds_count,
  coalesce(f.expenses,0)::numeric(14,2) as expenses,
  coalesce(f.gross_profit,0)::numeric(14,2) as gross_profit,
  coalesce(f.net_profit,0)::numeric(14,2) as net_profit,
  coalesce(i.stock_value,0)::numeric(14,2) as stock_value,
  coalesce(i.stock_items,0)::bigint as stock_items,
  coalesce(i.low_stock_count,0)::bigint as low_stock_count,
  coalesce(i.out_of_stock_count,0)::bigint as out_of_stock_count,
  coalesce(c.open_cash_sessions,0)::bigint as open_cash_sessions
from public.businesses b
left join today_financial f
  on f.business_id=b.id
 and f.report_date=(current_timestamp at time zone b.timezone)::date
left join inventory i
  on i.business_id=b.id
left join cash c
  on c.business_id=b.id;

grant select on public.business_dashboard to authenticated;
