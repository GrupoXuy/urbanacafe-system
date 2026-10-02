-- Urbana Café: align daily financial reporting with business timezone and dashboard source of truth.

create or replace view public.business_financial_daily
with (security_invoker=true)
as
with completed_sales as (
  select
    s.business_id,
    (s.completed_at at time zone b.timezone)::date as report_date,
    sum(s.total)::numeric(14,2) as revenue,
    sum(s.cogs)::numeric(14,2) as cogs,
    count(*)::bigint as sales_count
  from public.sales s
  join public.businesses b on b.id=s.business_id
  where s.status in ('completed','refunded')
    and s.completed_at is not null
  group by s.business_id,(s.completed_at at time zone b.timezone)::date
),
refunded_sales as (
  select
    s.business_id,
    (s.updated_at at time zone b.timezone)::date as report_date,
    (-sum(s.total))::numeric(14,2) as revenue,
    (-sum(s.cogs))::numeric(14,2) as cogs,
    count(*)::bigint as refunds_count
  from public.sales s
  join public.businesses b on b.id=s.business_id
  where s.status='refunded'
  group by s.business_id,(s.updated_at at time zone b.timezone)::date
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
    cm.business_id,
    (cm.created_at at time zone b.timezone)::date as report_date,
    sum(cm.amount) filter(where cm.amount>0)::numeric(14,2) as cash_in,
    abs(sum(cm.amount) filter(where cm.amount<0))::numeric(14,2) as cash_out
  from public.cash_movements cm
  join public.businesses b on b.id=cm.business_id
  group by cm.business_id,(cm.created_at at time zone b.timezone)::date
),
dates as (
  select business_id,report_date from completed_sales
  union
  select business_id,report_date from refunded_sales
  union
  select business_id,report_date from expenses
  union
  select business_id,report_date from cash
)
select
  d.business_id,
  d.report_date,
  (coalesce(cs.revenue,0)+coalesce(rs.revenue,0))::numeric(14,2) as revenue,
  (coalesce(cs.cogs,0)+coalesce(rs.cogs,0))::numeric(14,2) as cogs,
  coalesce(cs.sales_count,0)::bigint as sales_count,
  coalesce(e.expenses,0)::numeric(14,2) as expenses,
  coalesce(c.cash_in,0)::numeric(14,2) as cash_in,
  coalesce(c.cash_out,0)::numeric(14,2) as cash_out,
  (
    coalesce(cs.revenue,0)+coalesce(rs.revenue,0)
    -coalesce(cs.cogs,0)-coalesce(rs.cogs,0)
  )::numeric(14,2) as gross_profit,
  (
    coalesce(cs.revenue,0)+coalesce(rs.revenue,0)
    -coalesce(cs.cogs,0)-coalesce(rs.cogs,0)
    -coalesce(e.expenses,0)
  )::numeric(14,2) as net_profit,
  coalesce(rs.refunds_count,0)::bigint as refunds_count
from dates d
left join completed_sales cs
  on cs.business_id=d.business_id and cs.report_date=d.report_date
left join refunded_sales rs
  on rs.business_id=d.business_id and rs.report_date=d.report_date
left join expenses e
  on e.business_id=d.business_id and e.report_date=d.report_date
left join cash c
  on c.business_id=d.business_id and c.report_date=d.report_date;

create or replace view public.business_payment_daily
with (security_invoker=true)
as
with gross as (
  select
    s.business_id,
    (s.completed_at at time zone b.timezone)::date as report_date,
    sp.method,
    sum(sp.amount)::numeric(14,2) as gross_amount,
    count(distinct s.id)::bigint as transactions
  from public.sales s
  join public.businesses b on b.id=s.business_id
  join public.sale_payments sp on sp.sale_id=s.id
  where s.status in ('completed','refunded')
    and s.completed_at is not null
  group by s.business_id,(s.completed_at at time zone b.timezone)::date,sp.method
),
refunds as (
  select
    s.business_id,
    (sr.created_at at time zone b.timezone)::date as report_date,
    sr.method,
    sum(sr.amount)::numeric(14,2) as refunded_amount,
    count(distinct s.id)::bigint as refunds_count
  from public.sale_refund_payments sr
  join public.sales s on s.id=sr.sale_id
  join public.businesses b on b.id=s.business_id
  group by s.business_id,(sr.created_at at time zone b.timezone)::date,sr.method
),
keys as (
  select business_id,report_date,method from gross
  union
  select business_id,report_date,method from refunds
)
select
  k.business_id,
  k.report_date,
  k.method,
  coalesce(g.gross_amount,0)::numeric(14,2) as gross_amount,
  coalesce(r.refunded_amount,0)::numeric(14,2) as refunded_amount,
  (coalesce(g.gross_amount,0)-coalesce(r.refunded_amount,0))::numeric(14,2) as net_amount,
  coalesce(g.transactions,0)::bigint as transactions,
  coalesce(r.refunds_count,0)::bigint as refunds_count
from keys k
left join gross g
  on g.business_id=k.business_id
 and g.report_date=k.report_date
 and g.method=k.method
left join refunds r
  on r.business_id=k.business_id
 and r.report_date=k.report_date
 and r.method=k.method;

create or replace view public.business_dashboard
with (security_invoker=true)
as
select
  b.id as business_id,
  (current_timestamp at time zone b.timezone)::date as report_date,
  coalesce(f.revenue,0)::numeric(14,2) as revenue,
  coalesce(f.cogs,0)::numeric(14,2) as cogs,
  coalesce(f.sales_count,0)::bigint as sales_count
from public.businesses b
left join public.business_financial_daily f
  on f.business_id=b.id
 and f.report_date=(current_timestamp at time zone b.timezone)::date;

grant select on public.business_dashboard to authenticated;
grant select on public.business_financial_daily to authenticated;
grant select on public.business_payment_daily to authenticated;
