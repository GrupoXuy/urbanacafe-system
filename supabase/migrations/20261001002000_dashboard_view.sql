create or replace view public.business_dashboard as
select
  s.business_id,
  current_date as report_date,
  coalesce(sum(case when s.status='completed' then s.total else 0 end),0) as revenue,
  coalesce(sum(case when s.status='completed' then s.cogs else 0 end),0) as cogs,
  count(*) filter(where s.status='completed') as sales_count
from public.sales s
group by s.business_id;