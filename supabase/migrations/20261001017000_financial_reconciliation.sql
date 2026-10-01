-- Urbana Café: financial reconciliation and period-stable daily reporting.

create or replace view public.business_financial_daily
with (security_invoker=true)
as
with completed_sales as (
  select
    business_id,
    completed_at::date as report_date,
    sum(total)::numeric(14,2) as revenue,
    sum(cogs)::numeric(14,2) as cogs,
    count(*)::bigint as sales_count
  from public.sales
  where status='completed'
    and completed_at is not null
  group by business_id,completed_at::date
),
refunded_sales as (
  select
    business_id,
    updated_at::date as report_date,
    (-sum(total))::numeric(14,2) as revenue,
    (-sum(cogs))::numeric(14,2) as cogs,
    count(*)::bigint as refunds_count
  from public.sales
  where status='refunded'
  group by business_id,updated_at::date
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

create or replace view public.business_cash_reconciliation
with (security_invoker=true)
as
select
  cs.id as cash_session_id,
  cs.business_id,
  cs.opened_at,
  cs.closed_at,
  cs.status,
  cs.opening_amount::numeric(14,2) as opening_amount,
  round(coalesce(sum(cm.amount),0),2)::numeric(14,2) as calculated_expected,
  cs.counted_amount::numeric(14,2) as counted_amount,
  case
    when cs.counted_amount is null then null
    else round(cs.counted_amount-round(coalesce(sum(cm.amount),0),2),2)
  end::numeric(14,2) as calculated_difference,
  round(coalesce(sum(cm.amount) filter(where cm.movement_type='sale'),0),2)::numeric(14,2) as cash_sales,
  abs(round(coalesce(sum(cm.amount) filter(where cm.movement_type='refund'),0),2))::numeric(14,2) as cash_refunds,
  abs(round(coalesce(sum(cm.amount) filter(where cm.movement_type='expense'),0),2))::numeric(14,2) as cash_expenses,
  round(coalesce(sum(cm.amount) filter(where cm.movement_type='deposit' and cm.description<>'Abertura de caixa'),0),2)::numeric(14,2) as deposits,
  abs(round(coalesce(sum(cm.amount) filter(where cm.movement_type='withdrawal'),0),2))::numeric(14,2) as withdrawals,
  round(coalesce(sum(cm.amount) filter(where cm.movement_type='adjustment'),0),2)::numeric(14,2) as adjustments,
  count(cm.id)::bigint as movement_count
from public.cash_sessions cs
left join public.cash_movements cm on cm.cash_session_id=cs.id
where (select public.has_business_role(
  cs.business_id,
  array['owner','manager','cashier','analyst']::public.member_role[]
))
group by cs.id,cs.business_id,cs.opened_at,cs.closed_at,cs.status,cs.opening_amount,cs.counted_amount;

grant select on public.business_cash_reconciliation to authenticated;