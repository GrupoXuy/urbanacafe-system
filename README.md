# Urbana Café System

Sistema operacional e gerencial do Urbana Café: CRM + POS + caixa + estoque + compras + despesas + clientes + reservas + fichas técnicas + relatórios + auditoria.

## Stack
- Next.js / React
- Supabase PostgreSQL + Auth + RLS
- Vercel
- Node 22.14.0

## Princípio

Uma operação confirmada deve alimentar os livros correspondentes sem redigitação e sem permitir alterações diretas que quebrem o histórico.

Fluxos centrais:

`Compra → estoque → custo médio → impacto financeiro`

`Venda → itens → pagamento → caixa (quando dinheiro) → estoque/receita → CMV → indicadores`

`Estorno → histórico preservado → reversão de estoque → devolução financeira conforme meio de pagamento`

## Estado atual

A base operacional principal está implementada em produção, incluindo:

- primeiro acesso e autenticação via Supabase Auth;
- isolamento por `business_id` com RLS;
- POS com cliente, mesa e meios de pagamento;
- fechamento e reconciliação de caixa;
- compras transacionais e custo médio ponderado;
- cadastro de fornecedores;
- produtos e estoque;
- fichas técnicas com consumo automático de ingredientes;
- histórico e estorno transacional de vendas;
- reservas com validação de capacidade e concorrência;
- despesas;
- relatórios financeiros, pagamentos, caixa, estoque, produtos, perdas e ajustes;
- trilha de auditoria operacional;
- migrations versionadas em `supabase/migrations/`;
- testes SQL de segurança e operação em `supabase/tests/`.

## Segurança

- RLS obrigatório nas tabelas expostas.
- Operações críticas usam RPC transacional e validação de cargo/negócio.
- Livros financeiros e de estoque não devem ser apagados ou alterados diretamente pelo navegador.
- `SUPABASE_SERVICE_ROLE_KEY` é somente servidor/backend.
- Views expostas usam `security_invoker=true` quando precisam respeitar RLS das tabelas subjacentes.
- Funções `SECURITY DEFINER` precisam validar autenticação, negócio e permissão e definir `search_path`.

## Estrutura

- `app/`: interface e rotas
- `lib/`: clientes Supabase e configuração
- `supabase/migrations/`: evolução versionada do banco
- `supabase/tests/`: smoke tests SQL
- `supabase/seed.sql`: dados iniciais
- `.github/workflows/ci.yml`: typecheck, lint e build

## Configuração

Use:

`NEXT_PUBLIC_SUPABASE_URL`

`NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`

`SUPABASE_SERVICE_ROLE_KEY` somente no ambiente servidor.

Depois:

`npm ci`

`npm run dev`

## Deploy

Projeto Vercel: `urbanacafe-system`

Repositório: `GrupoXuy/urbanacafe-system`

Branch de produção: `main`

O CI valida Node 22.14.0, instalação via `npm ci`, typecheck, lint e build. Os testes SQL existentes devem ser promovidos para a pipeline automatizada quando houver um banco de teste/branch próprio para CI.

## Próxima linha de implementação

A prioridade agora é estabilizar a operação ponta a ponta antes de aumentar o escopo visual:

1. validar cenários reais de POS, caixa, compra, estoque, reserva e estorno;
2. ampliar cobertura automatizada dos fluxos transacionais;
3. concluir a segurança das funções auxiliares expostas no schema `public`;
4. evoluir o Dashboard para usar os mesmos indicadores operacionais dos Relatórios;
5. criar configurações do negócio, parâmetros de operação e preferências;
6. depois disso, avançar para integrações externas, impressão/comandas e automações.

## Regra de evolução

Novas funcionalidades devem seguir esta ordem:

**modelo de dados → regra transacional → RLS/permissões → teste → interface → produção.**

Isso evita que a interface fique à frente da lógica real do sistema.
