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

`Comanda → venda aberta → edição → fechamento → pagamento + caixa + estoque + CMV`

## Estado atual

A base operacional principal está implementada em produção, incluindo:

- primeiro acesso e autenticação via Supabase Auth;
- isolamento por `business_id` com RLS;
- POS com cliente, mesa e meios de pagamento;
- comandas abertas com edição, ocupação de mesa e fechamento transacional;
- KDS operacional de cozinha/bar com roteamento por produto, prioridades, filas por estação, tempos-alvo, identificação de atraso, atualização em tempo real e indicadores de desempenho;
- impressão operacional de comandas por ticket de 80 mm;
- fechamento e reconciliação de caixa;
- compras transacionais e custo médio ponderado;
- cadastro de fornecedores;
- produtos e estoque;
- fichas técnicas com consumo automático de ingredientes;
- histórico e estorno transacional de vendas;
- ciclo de atendimento comanda → edição → cancelamento/fechamento;
- produção cozinha/bar derivada da mesma comanda, sem duplicação de pedidos;
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

## Estado de conclusão

A operação ponta a ponta principal está implementada e validada em produção: POS, comandas, caixa, compras, estoque, receitas, reservas, estornos, relatórios financeiros/pagamentos, dashboard operacional, configurações do negócio, auditoria e navegação compartilhada.

A camada de funções privilegiadas foi isolada em schema `private`, mantendo wrappers públicos `SECURITY INVOKER`. O projeto usa a convenção `proxy.ts` do Next.js 16 e Node `22.14.0` de forma determinística. O KDS operacional usa `production_tickets` como fonte única de produção, com prioridade e tempo-alvo persistidos, métricas agregadas por estação e Supabase Realtime para atualização imediata.

## Pré-entrega

A Fase Final de Pré-Entrega foi iniciada em 06/10/2026 na branch `codex/pre-delivery-urbana`, com PR #23. Foram implementados recuperação de senha, bloqueio do onboarding público após o primeiro proprietário, proteção do callback contra open redirect e gestão ampliada de acessos da equipe (convite, reenvio, redefinição, ativação/desativação e remoção preservando histórico). A regra de onboarding único também foi aplicada no banco de produção.

Validações SQL executadas em produção: segurança/RLS/operação principal, comandas e atendimento, KDS cozinha/bar, inteligência operacional do KDS e matriz de cargos/permissões — todas com **PASS**.

Checklist de aceite do proprietário: `docs/URBANA_CAFE_CHECKLIST_ACEITE.md`.

## Pendências externas

1. Ativar Leaked Password Protection no Supabase Auth.
2. Configurar um banco descartável/branch para executar os testes SQL automaticamente no CI.
3. Ativar proteção server-side da branch `main` no GitHub. A conexão GitHub disponível nesta execução não expõe essa mutação.
4. Validar backup/PITR e procedimento de recuperação conforme o plano Supabase.
5. Cadastrar e conferir os dados reais do Urbana Café e validar hardware/impressão no estabelecimento.

Esses itens não devem ser marcados como concluídos sem validação explícita.

