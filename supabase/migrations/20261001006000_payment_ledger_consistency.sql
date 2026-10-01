-- Ensure sale cash movement reflects only the cash portion of a sale.
create or replace function public.normalize_sale_cash_movement()
returns trigger
language plpgsql
as $$
declare
  v_cash_paid numeric(14,2);
begin
  if new.movement_type='sale' and new.reference_id is not null then
    select round(coalesce(sum(sp.amount) filter(where sp.method='cash'),0),2)
      into v_cash_paid
    from public.sale_payments sp
    where sp.sale_id=new.reference_id;

    if v_cash_paid<=0 then
      return null;
    end if;

    new.amount:=v_cash_paid;
  end if;

  return new;
end;
$$;

drop trigger if exists normalize_sale_cash on public.cash_movements;
create trigger normalize_sale_cash
before insert on public.cash_movements
for each row execute function public.normalize_sale_cash_movement();
