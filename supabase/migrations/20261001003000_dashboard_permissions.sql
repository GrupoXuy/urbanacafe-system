-- Dashboard view permissions
-- Authenticated users can read the aggregate view; underlying membership access remains enforced by the source tables.
grant select on public.business_dashboard to authenticated;