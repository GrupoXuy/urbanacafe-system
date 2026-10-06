# Urbana Café — Checklist de Aceite do Proprietário

## 1. Identificação
**Negócio:** Urbana Café  
**Sistema:** Urbana Café System  
**Ambiente:** Produção  
**URL:** https://urbanacafe-system.vercel.app  
**Proprietário:** ____________________________________  
**Data do aceite:** ____ / ____ / ______

## 2. Gate técnico — Grupo X
| Item | Status |
|---|---|
| Build Vercel | ✅ Validado nos ciclos anteriores; PR atual em validação |
| Node 22.x na Vercel | ✅ Configurado |
| Supabase ativo/saudável | ✅ Validado |
| RLS/funções transacionais | ✅ Testados |
| Operação/RLS principal | ✅ PASS |
| Comandas e atendimento | ✅ PASS |
| KDS cozinha/bar | ✅ PASS |
| Inteligência operacional KDS | ✅ PASS |
| Matriz de cargos/permissões | ✅ PASS |
| Onboarding após primeiro proprietário | ✅ Aplicado no banco |
| Recuperação de senha | ✅ Implementada |
| Gestão de acessos | ✅ Implementada |
| Callback sem open redirect | ✅ Implementado |

## 3. Configuração real do Urbana Café
| Item | Conferência |
|---|---|
| Nome comercial | ☐ |
| Razão social | ☐ |
| Moeda | ☐ |
| Fuso horário | ☐ |
| Catálogo completo | ☐ |
| Categorias | ☐ |
| Preços | ☐ |
| Fichas técnicas/receitas | ☐ |
| Custos médios | ☐ |
| Estoque inicial | ☐ |
| Estoque mínimo | ☐ |
| Mesas/capacidade | ☐ |
| Fornecedores | ☐ |
| Equipe/cargos | ☐ |
| Capacidade KDS cozinha | ☐ |
| Capacidade KDS bar | ☐ |

**Regra:** nenhum dado operacional real deve ser inventado. Esses campos dependem da conferência do estabelecimento.

## 4. POS e vendas
☐ Abrir caixa.  
☐ Registrar venda.  
☐ Associar cliente/mesa quando aplicável.  
☐ Testar dinheiro.  
☐ Testar débito/crédito/transferência.  
☐ Confirmar caixa, estoque, histórico e KDS quando aplicável.  

## 5. Comandas
☐ Abrir comanda.  
☐ Adicionar/editar itens.  
☐ Enviar à produção.  
☐ Validar KDS.  
☐ Marcar preparo/pronto.  
☐ Fechar e pagar.  
☐ Confirmar liberação da mesa.  

## 6. KDS
☐ Cozinha.  
☐ Bar.  
☐ Fila.  
☐ Prioridade.  
☐ Tempo-alvo.  
☐ Atraso.  
☐ Pressão da fila.  
☐ Capacidade por estação.  
☐ Previsão de atraso.  
☐ Alertas.  
☐ Atualização em tempo real em dois dispositivos.  

## 7. Caixa
☐ Fundo inicial.  
☐ Venda em dinheiro.  
☐ Entrada/retirada.  
☐ Despesa em dinheiro.  
☐ Conferência do esperado.  
☐ Contagem física.  
☐ Fechamento.  
☐ Diferença.  
☐ Relatório de reconciliação.  

## 8. Estoque/compras/receitas
☐ Compra.  
☐ Entrada no estoque.  
☐ Custo médio.  
☐ Ficha técnica.  
☐ Consumo automático.  
☐ Perda/desperdício.  
☐ Inventário/ajuste.  

## 9. Estorno
☐ Estornar venda.  
☐ Confirmar reversão de estoque.  
☐ Confirmar devolução financeira conforme pagamento.  
☐ Confirmar histórico/auditoria preservados.  

## 10. Reservas
☐ Criar.  
☐ Confirmar.  
☐ Associar mesa.  
☐ Validar capacidade.  
☐ Concluir/cancelar.  

## 11. Usuários e segurança
☐ Login do proprietário.  
☐ Recuperação de senha.  
☐ Convite.  
☐ Reenvio de convite.  
☐ Alteração de cargo.  
☐ Ativar/desativar.  
☐ Remover acesso preservando histórico.  
☐ Gerente sem poder alterar proprietário.  
☐ Pelo menos um proprietário ativo.  
☐ Acesso conforme o cargo.  

## 12. Hardware
☐ Impressora térmica 80 mm.  
☐ Ticket legível no papel real.  
☐ KDS na tela oficial.  
☐ Rede/Wi-Fi estável.  
☐ Navegador oficial definido.  
☐ PC/tablet oficial validado.  
☐ Sessão/recarga validada.  

## 13. Relatórios
☐ Dashboard.  
☐ Vendas.  
☐ Financeiro.  
☐ Caixa.  
☐ Estoque.  
☐ Produtos.  
☐ Perdas/ajustes.  
☐ Reconciliação.  
☐ Indicadores KDS.  

## 14. Aprovação
**Pendências aceitas:**  
__________________________________________________________________  
__________________________________________________________________

**Proprietário — nome:** ___________________________________________

**Assinatura:** __________________________________  **Data:** ____ / ____ / ______

**Responsável Grupo X:** ___________________________________________

**Assinatura:** __________________________________  **Data:** ____ / ____ / ______

## 15. Critério formal de aceite
O sistema será considerado formalmente aceito quando os dados reais estiverem conferidos, o fluxo POS → pagamento → caixa/estoque → KDS for validado no equipamento real, o fechamento de caixa for validado, os acessos reais estiverem carregados, impressão/rede forem validadas e o proprietário assinar este checklist.

## Controles externos ainda pendentes
- Leaked Password Protection no Supabase Auth.
- Banco/branch descartável para SQL tests automáticos no GitHub Actions.
- Proteção server-side da branch main no GitHub.
- Backup/PITR e recuperação conforme o plano Supabase.
- Dados reais e validação física no estabelecimento.
