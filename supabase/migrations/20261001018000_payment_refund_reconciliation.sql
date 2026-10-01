-- Urbana Café: payment-level refund ledger and daily payment reconciliation.

create table if not exists public.sale_refund_payments (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete restrict,
  method public.payment_method not null,
  amount numeric(14,2) not null check(amount>0),
  reason text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.sale_refund_payments enable row level security;

drop policy if exists sale_refund_payments_read on public.sale_refund_payments;
create policy sale_refund_payments_read on public.sale_refund_payments
for select to authenticated
using (
  exists (
    select 1
    from public.sales s
    where s.id=sale_id
      and (select public.is_business_member(s.business_id))
  )
);

create index if not exists idx_sale_refund_payments_sale_id
on public.sale_refund_payments (sale_id);

create or replace function public.refund_sale_transaction(
  p_sale_id uuid,
  p_reason text default null
)
returns public.sales
language plpgsql
security definer
set search_path=public
as $$
declare
  v_sale public.sales%rowtype;
  v_move record;
  v_payment record;
  v_business uuid;
  v_cash_refund numeric(14,2);
  v_cash_session uuid;
  v_reason text;
  v_old_status public.sale_status;
  v_reversed_count integer := 0;
begin
  select * into v_sale
  from public.sales
  where id=p_sale_id
  for update;

  if not found then raise exception 'Venda não encontrada'; end if;

  v_business:=v_sale.business_id;

  if not public.has_business_role(
    v_business,
    array['owner','manager']::public.member_role[]
  ) then
    raise exception 'Sem permissão para estornar esta venda';
  end if;

  if v_sale.status<>'completed' then
    raise exception 'Somente vendas concluídas podem ser estornadas';
  end if;

  v_old_status:=v_sale.status;
  v_reason:=nullif(trim(coalesce(p_reason,'')),'');
  if v_reason is null then v_reason:='Estorno de venda'; end if;

  select round(coalesce(sum(case when sp.method='cash' then sp.amount else 0 end),0),2)
  into v_cash_refund
  from public.sale_payments sp
  where sp.sale_id=p_sale_id;

  if v_cash_refund>0 then
    select id into v_cash_session
    from public.cash_sessions
    where business_id=v_business
      and status='open'
    order by opened_at desc
    limit 1;

    if v_cash_session is null then
      raise exception 'Abra o caixa antes de estornar uma venda recebida em dinheiro';
    end if;
  end if;

  for v_payment in
    select method,amount
    from public.sale_payments
    where sale_id=p_sale_id
    order by created_at,id
  loop
    insert into public.sale_refund_payments(
      sale_id,method,amount,reason,created_by
    )
    values(
      p_sale_id,v_payment.method,v_payment.amount,v_reason,auth.uid()
    );
  end loop;

  for v_move in
    select id,product_id,quantity,unit_cost,note
    from public.stock_movements
    where business_id=v_business
      and reference_id=p_sale_id
      and movement_type='sale'
    order by created_at,id
    for update
  loop
    if v_move.quantity>=0 then
      raise exception 'Movimento de estoque inconsistente para a venda';
    end if;

    update public.products
    set stock_quantity=stock_quantity-v_move.quantity,
        updated_at=now()
    where id=v_move.product_id
      and business_id=v_business;

    if not found then raise exception 'Produto do estorno não encontrado'; end if;

    insert into public.stock_movements(
      business_id,product_id,movement_type,quantity,unit_cost,reference_id,note,created_by
    )
    values(
      v_business,v_move.product_id,'adjustment',-v_move.quantity,v_move.unit_cost,
      p_sale_id,v_reason,auth.uid()
    );

    v_reversed_count:=v_reversed_count+1;
  end loop;

  if v_reversed_count=0 then
    raise exception 'Não existem movimentos de estoque para estornar nesta venda';
  end if;

  if v_cash_refund>0 then
    insert into public.cash_movements(
      business_id,cash_session_id,movement_type,amount,reference_id,description,created_by
    )
    values(
      v_business,v_cash_session,'refund',-v_cash_refund,p_sale_id,v_reason,auth.uid()
    );
  end if;

  perform set_config('app.allow_sale_refund','on',true);

  update public.sales
  set status='refunded',
      notes=case
        when v_sale.notes is null or trim(v_sale.notes)='' then 'Estornado: '||v_reason
        else v_sale.notes||E'\nEstornado: '||v_reason
      end,
      updated_at=now()
  where id=p_sale_id
  returning * into v_sale;

  insert into public.audit_logs(
    business_id,user_id,action,entity,entity_id,old_data,new_data
  )
  values(
    v_business,auth.uid(),'refund','sale',p_sale_id,
    jsonb_build_object('status',v_old_status,'total',v_sale.total,'cash_refund',v_cash_refund),
    jsonb_build_object(
      'status',v_sale.status,
      'reason',v_reason,
      'stock_movements_reversed',v_reversed_count,
      'payment_refunds_recorded',(select count(*) from public.sale_refund_payments where sale_id=p_sale_id)
    )
  );

  return v_sale;
end;
$$;

revoke all on function public.refund_sale_transaction(uuid,text) from public;
revoke all on function public.refund_sale_transaction(uuid,text) from anon;
grant execute on function public.refund_sale_transaction(uuid,text) to authenticated;

create or replace view public.business_payment_daily
with (security_invoker=true)
as
with gross as (
  select
    s.business_id,
    s.completed_at::date as report_date,
    sp.method,
    sum(sp.amount)::numeric(14,2) as gross_amount,
    count(distinct s.id)::bigint as transactions
  from public.sales s
  join public.sale_payments sp on sp.sale_id=s.id
  where s.status in ('completed','refunded')
    and s.completed_at is not null
  group by s.business_id,s.completed_at::date,sp.method
),
refunds as (
  select
    s.business_id,
    sr.created_at::date as report_date,
    sr.method,
    sum(sr.amount)::numeric(14,2) as refunded_amount,
    count(distinct s.id)::bigint as refunds_count
  from public.sale_refund_payments sr
  join public.sales s on s.id=sr.sale_id
  group by s.business_id,sr.created_at::date,sr.method
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

grant select on public.business_payment_daily to authenticated;
