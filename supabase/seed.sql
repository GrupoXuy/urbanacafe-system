insert into public.businesses(name,legal_name,currency,timezone)
values ('Urbana Café','Urbana Café y Resto','UYU','America/Montevideo')
on conflict do nothing;

insert into public.categories(business_id,name)
select id,'Bebidas' from public.businesses where name='Urbana Café'
on conflict do nothing;

insert into public.categories(business_id,name)
select id,'Comidas' from public.businesses where name='Urbana Café'
on conflict do nothing;

insert into public.categories(business_id,name)
select id,'Insumos' from public.businesses where name='Urbana Café'
on conflict do nothing;