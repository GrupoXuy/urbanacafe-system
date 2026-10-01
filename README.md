# Urbana Café System

Sistema operacional e gerencial do Urbana Café: CRM + POS + caixa + estoque + compras + despesas + relatórios.

## Stack
- Next.js / React
- Supabase PostgreSQL + Auth + RLS
- Vercel

## Princípio
Uma venda confirmada deverá alimentar venda, pagamentos, caixa, estoque, CMV e indicadores sem redigitação.

## Segurança
- RLS obrigatório.
- Nunca usar service_role no navegador.
- Dados financeiros/estoque postados não devem ser apagados.
- Autorizações devem ser verificadas no banco/backend, não somente na interface.

## Estrutura
- `app/`: interface e rotas
- `lib/`: clientes e tipos
- `supabase/migrations/`: banco
- `supabase/seed.sql`: dados iniciais

## Configuração
Copie `.env.example` para `.env.local` e informe:
`NEXT_PUBLIC_SUPABASE_URL`
`NEXT_PUBLIC_SUPABASE_ANON_KEY`

Depois:
`npm install`
`npm run dev`

## Deploy
Projeto Vercel: `urbanacafe-system`
Repositório: `GrupoXuy/urbanacafe-system`
Branch de produção: `main`

A validação automatizada usa Node 22.14.0, `npm ci`, typecheck, lint e build, com dependências fixadas em `package-lock.json`.

## Próxima fase
Compras já usam RPC transacional, com atualização de estoque, custo médio e impacto de caixa em uma única transação. Os livros de vendas, compras, pagamentos, caixa, despesas e estoque ficam protegidos contra escrita direta pelo navegador.

Próximas etapas: aprofundar consumo por ficha técnica/receitas, fechamento e reconciliação de caixa, relatórios operacionais e índices das chaves estrangeiras conforme os avisos de performance do Supabase.
