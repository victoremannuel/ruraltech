# Task: Estabilização de Commit Window e Flush Slicing RPv2 2026-06-19

#ruraltech
#tarefas

## Context

Implementar na `main` o plano `ruraltech_rpv2_commit_window_flush_slicing_plan.md` sobre o baseline `b1730c8b`, corrigindo o handoff do ACK do último fragmento para `FENCE_COMMIT` e tornando o flush cloud cooperativo e seguro para watchdog.

Continua [[correcao-command-id-flush-rpv2-2026-06-19]] e segue [[protocolo-rpv2]].

## Action

- [x] Confirmar `main` limpa e baseline validado
- [x] Carregar Graphify, brain e plano completo
- [x] Inventariar janela imediata de POINTS e manutenção da sessão na coleira
- [x] Implementar janela imediata de COMMIT após ACK final
- [x] Implementar timeout limitado de espera por COMMIT
- [x] Adicionar política de flush cooperativo e orçamento temporal
- [x] Priorizar status terminal e coalescer estados intermediários
- [x] Limitar todos os call sites normais a um item por slice
- [x] Adicionar testes host-side
- [x] Executar validações e compilar matriz e coleira
- [x] Atualizar Graphify e documentação do brain

Update context: implementação concluída na `main`, com janela imediata de COMMIT, grace timeout, fila terminal-first, coalescing e flush de um item por slice.

## Status

Implementação concluída na `main`; validação física e confirmação do estado terminal no Supabase permanecem pendentes.

Update context: testes host-side e `git diff --check` passaram; matriz compilou com 73% flash/29% RAM e coleira com 60% flash/21% RAM.

## Pending

- [ ] Executar bench físico com cerca de 6 pontos e confirmar `RPV2_COMMIT_RX_WINDOW_BEGIN`, `RPV2_CRC_OK` e `RPV2_SESSION_COMPLETE`
- [ ] Confirmar ausência de `task_wdt`, reset ou reboot durante o flush
- [ ] Confirmar estado terminal `applied` no Supabase usando o command ID completo

Update context: estes itens dependem de hardware conectado e serviços remotos.

## Blockers

Nenhum bloqueio de implementação. O fechamento operacional depende do bench físico e da consulta ao Supabase.

Update context: o ambiente local validou contratos e builds, mas não substitui o teste ponta a ponta com rádio.

## Next step

Gravar matriz e coleira com o mesmo build e executar o roteiro físico e de Supabase descrito no plano.

Update context: próximo passo movido da implementação local para validação operacional.

## Related

[[fluxo-comandos]]
