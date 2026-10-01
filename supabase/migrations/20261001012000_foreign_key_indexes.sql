-- Urbana Café: indexes for foreign keys reported by Supabase database advisor.
-- Composite indexes whose first key already covers a foreign key are not duplicated.

create index if not exists idx_audit_logs_business_id on public.audit_logs (business_id);
create index if not exists idx_audit_logs_user_id on public.audit_logs (user_id);

create index if not exists idx_cash_movements_cash_session_id on public.cash_movements (cash_session_id);
create index if not exists idx_cash_movements_created_by on public.cash_movements (created_by);

create index if not exists idx_cash_sessions_opened_by on public.cash_sessions (opened_by);
create index if not exists idx_cash_sessions_closed_by on public.cash_sessions (closed_by);

create index if not exists idx_customers_business_id on public.customers (business_id);

create index if not exists idx_expenses_created_by on public.expenses (created_by);

create index if not exists idx_products_category_id on public.products (category_id);

create index if not exists idx_purchase_items_purchase_id on public.purchase_items (purchase_id);
create index if not exists idx_purchase_items_product_id on public.purchase_items (product_id);

create index if not exists idx_purchases_business_id on public.purchases (business_id);
create index if not exists idx_purchases_supplier_id on public.purchases (supplier_id);
create index if not exists idx_purchases_created_by on public.purchases (created_by);

create index if not exists idx_recipe_items_recipe_id on public.recipe_items (recipe_id);
create index if not exists idx_recipe_items_ingredient_product_id on public.recipe_items (ingredient_product_id);

create index if not exists idx_recipes_business_id on public.recipes (business_id);

create index if not exists idx_reservations_business_id on public.reservations (business_id);
create index if not exists idx_reservations_customer_id on public.reservations (customer_id);
create index if not exists idx_reservations_table_id on public.reservations (table_id);

create index if not exists idx_sale_items_sale_id on public.sale_items (sale_id);
create index if not exists idx_sale_items_product_id on public.sale_items (product_id);

create index if not exists idx_sale_payments_sale_id on public.sale_payments (sale_id);

create index if not exists idx_sales_cash_session_id on public.sales (cash_session_id);
create index if not exists idx_sales_customer_id on public.sales (customer_id);
create index if not exists idx_sales_table_id on public.sales (table_id);
create index if not exists idx_sales_opened_by on public.sales (opened_by);

create index if not exists idx_stock_movements_product_id on public.stock_movements (product_id);
create index if not exists idx_stock_movements_created_by on public.stock_movements (created_by);

create index if not exists idx_suppliers_business_id on public.suppliers (business_id);
