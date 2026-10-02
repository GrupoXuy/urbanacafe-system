# Urbana Café CRM v1.0 — arquitetura e estado

## Objetivo

Sistema único para operação e gestão do Urbana Café, cobrindo POS, caixa, estoque, compras, CMV, despesas, clientes, mesas, reservas, fichas técnicas, funcionários, auditoria e relatórios.

## Regras de negócio

1. Moeda: UYU.
2. Timezone operacional: `America/Montevideo`.
3. Valores monetários: `numeric(14,2)`.
4. Quantidades: `numeric(14,3)`.
5. Vendas, estoque e caixa postados não são apagados.
6. Cancelamentos e estornos preservam o histórico e usam movimentos compensatórios.
7. Custo médio ponderado é atualizado nas entradas de estoque.
8. CMV é congelado na finalização da venda.
9. Lucro bruto = receita líquida - CMV líquido.
10. Lucro líquido gerencial = lucro bruto - despesas operacionais.
11. Entidades operacionais pertencem a um `business_id`.
12. Todas as tabelas públicas expostas usam RLS.
13. `service_role` é exclusivo do backend.
14. Operações críticas são transacionais via RPC/Server Action.
15. Pagamentos não monetários não alteram o dinheiro físico do caixa.
16. Estornos recompõem estoque quando aplicável e registram devolução financeira pelo meio de pagamento original.
17. Reservas de mesa respeitam capacidade, tenant e concorrência por horário.

## Módulos implementados

- Dashboard
- Vendas / POS
- Histórico e estorno de vendas
- Caixa e reconciliação
- Estoque
- Produtos
- Fichas técnicas / receitas
- Compras
- Fornecedores
- Despesas
- Clientes
- Mesas
- Reservas
- Relatórios financeiros e operacionais
- Funcionários
- Auditoria

## Arquitetura transacional

### Venda

`POS → create_sale_transaction → sales + sale_items + sale_payments → finalize_sale`

Na finalização:
- valida negócio, usuário, caixa, cliente, mesa e estoque;
- calcula CMV;
- consome item de estoque ou ingredientes da ficha técnica;
- registra movimentos de estoque;
- registra somente a parcela em dinheiro no livro físico de caixa;
- confirma a venda.

### Estorno

`refund_sale_transaction`

- somente venda concluída;
- motivo obrigatório por padrão;
- preserva a venda original;
- registra `sale_refund_payments`;
- recompõe estoque quando a venda teve movimento de estoque;
- registra devolução em caixa somente para pagamentos em dinheiro;
- grava auditoria;
- impede segundo estorno.

### Compra

`create_purchase_transaction → post_purchase`

- valida fornecedor e produtos do mesmo negócio;
- cria compra e itens atomicamente;
- atualiza estoque;
- calcula custo médio ponderado;
- registra saída financeira quando o pagamento é em dinheiro.

### Caixa

`open_cash_session → record_cash_movement → close_cash_session`

O fechamento compara o valor esperado do ledger com o valor contado e permite registrar observação da conferência.

### Reservas

`create_reservation_transaction → update_reservation_status`

Há validação de capacidade e proteção contra duas reservas ativas para a mesma mesa e horário.

## Relatórios

As principais fontes de leitura são:

- `business_dashboard`
- `business_financial_daily`
- `business_payment_daily`
- `business_cash_reconciliation`
- `business_inventory_summary`
- `business_product_sales_daily`
- `business_stock_movement_daily`

As visões financeiras usam o timezone configurado no negócio para consolidar datas.

## Segurança

O navegador não escreve diretamente nos livros transacionais principais. As operações críticas usam RPCs que validam:
- usuário autenticado;
- pertencimento ao negócio;
- cargo permitido;
- integridade dos registros relacionados.

Views expostas de relatórios usam `security_invoker=true` para preservar a aplicação das políticas RLS das tabelas subjacentes.

Há avisos do Supabase Advisor para funções `SECURITY DEFINER` executáveis por usuários autenticados. Eles precisam continuar sendo avaliados porque algumas dessas funções são deliberadamente endpoints RPC, enquanto `has_business_role` e `is_business_member` são helpers internos que podem ser isolados posteriormente em schema não exposto.

## Testes

Os testes SQL ficam em:

- `supabase/tests/operational_security.sql`
- `supabase/tests/inventory_operational_reports.sql`

A suíte operacional foi executada no banco do projeto e passou, incluindo:
- RLS e isolamento entre negócios;
- POS atômico;
- compras;
- custo médio;
- fichas técnicas;
- estornos;
- reconciliação financeira;
- reconciliação por meio de pagamento;
- estorno de produto sem controle de estoque.

Os testes ainda não são executados automaticamente pelo workflow principal do GitHub.

## Estado atual

A base operacional está em produção no projeto Vercel `urbanacafe-system`, ligada ao repositório `GrupoXuy/urbanacafe-system` e ao Supabase `shmkopvvjugydtfrcpar`.

## Próximas prioridades

1. Consolidar componentes compartilhados de navegação e layout.
2. Integrar testes SQL a um banco/branch próprio para CI.
3. Isolar helpers internos de autorização fora do schema exposto.
4. Evoluir Dashboard com os indicadores gerenciais já disponíveis nos relatórios.
5. Criar Configurações do negócio e parâmetros operacionais.
6. Depois, avançar para integrações externas, impressão/comandas e automações.

## Regra de evolução

Toda nova capacidade deve seguir:

**modelo de dados → regra transacional → RLS/permissões → teste → interface → produção.**

A interface não deve antecipar uma regra de negócio que ainda não esteja protegida no banco/backend.
