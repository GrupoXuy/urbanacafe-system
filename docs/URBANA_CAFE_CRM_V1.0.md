# Urbana Café CRM v1.0 — implementação

Objetivo: sistema único para POS, caixa, estoque, compras, CMV, despesas, lucro, clientes, reservas, funcionários e auditoria.

Regras:
1. moeda UYU; timezone America/Montevideo.
2. valores monetários em numeric(14,2), quantidades em numeric(14,3).
3. vendas, estoque e caixa postados não são apagados.
4. cancelamentos/estornos preservam histórico.
5. custo médio ponderado no estoque.
6. CMV deve ser congelado na finalização da venda.
7. lucro bruto = receita - CMV.
8. lucro líquido gerencial = lucro bruto - despesas operacionais.
9. business_id em entidades operacionais.
10. RLS em todas as tabelas expostas.
11. service_role somente no backend.
12. operações críticas devem ser transacionais via RPC/Server Action.

Módulos: Dashboard, Caixa, Vendas/POS, Estoque, Compras, Despesas, Relatórios, Clientes, Funcionários, Configurações.

Fluxo principal:
Compra -> entrada de estoque -> atualização do custo médio -> saída financeira.
Venda -> itens -> pagamento -> caixa -> baixa de estoque/receita -> CMV -> indicadores.
Fechamento de caixa -> valor esperado vs contado -> diferença justificada.
