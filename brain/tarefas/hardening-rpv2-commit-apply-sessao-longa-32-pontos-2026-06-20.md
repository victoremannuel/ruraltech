# Task: Hardening RPv2 COMMIT APPLY para Sessao Longa de 32 Pontos 2026-06-20

#ruraltech
#tarefas

## Context

Implementar na `main` o plano `ruraltech_rpv2_long_session_commit_apply_hardening_plan.md` sobre o baseline `3600def5`, preservando o planner bounded-first de 5 pontos por fragmento e endurecendo o handoff final de sessões com ate 7 fragmentos.

Continua [[hardening-planner-rpv2-32-pontos-2026-06-19]] e [[protocolo-rpv2]].

## Action

- [x] Carregar Graphify, brain, plano e baseline da `main`
- [x] Adicionar politica compartilhada de timeout e tentativas por quantidade de fragmentos
- [x] Instrumentar ACK final ate COMMIT, tentativas de COMMIT e espera de APPLY_STATUS
- [x] Implementar retry explicito de COMMIT na matriz
- [x] Aceitar APPLY_STATUS terminal valido durante a espera de COMMIT_ACK
- [x] Escalar a espera de COMMIT na coleira para sessoes longas
- [x] Tornar COMMIT duplicado idempotente apos aplicacao
- [x] Preservar falha estruturada e fila diferida radio-critica
- [x] Expandir testes host-side e executar regressao
- [ ] Compilar matriz e coleira quando o ambiente permitir
- [x] Atualizar arquitetura, checklist e checkpoint no brain

## Status

Implementacao local concluida na `main`; builds Arduino e validacao fisica permanecem pendentes.

Update context: politica dinamica, retry COMMIT, APPLY_STATUS antecipado seguro, cache idempotente e diagnosticos implementados em 2026-06-20.

Update context: em 2026-06-21, a `main` e `origin/main` foram auditadas no commit `2a2e8088`; o hardening permanece em `5bd8b652`, a suite host-side oficial passou integralmente e o worktree permaneceu limpo.

Concluido:
- timeouts COMMIT_ACK de 6/9/12 s e APPLY_STATUS de 10/12/15 s por quantidade de fragmentos;
- 2 tentativas de COMMIT para sessoes curtas e 3 para sessoes com 6 ou mais fragmentos;
- grace da coleira de 15/22/30 s alem da janela imediata de 10 s;
- teto global da sessao estendido ate o deadline de COMMIT;
- COMMIT duplicado reapresenta ACK e APPLY_STATUS sem nova persistencia;
- APPLY_STATUS durante COMMIT_ACK exige sessao ja validada, sucesso, CRC e pontos esperados;
- estado `commit_retry_pending` coalescido na fila diferida;
- suite host-side completa e `git diff --check` passaram.

## Pending

- [ ] Executar bancada fisica de 6, 12, 25 e 32 pontos
- [ ] Repetir 32 pontos apos deep sleep
- [ ] Confirmar terminal `applied` no Supabase

Update context: itens operacionais dependem de hardware e servicos remotos.

## Blockers

Builds de `gateway-matriz` e `coleira` foram interrompidos apos 60 segundos sem qualquer saida, repetindo o hang silencioso conhecido deste host.

Update context: o bloqueio e de validacao do ambiente Arduino, nao de implementacao host-side.

Update context: o bloqueio foi reproduzido novamente em 2026-06-21 nos dois sketches, sem saida do `arduino-cli` por mais de 60 segundos.

## Next step

Compilar em host Arduino estavel, gravar ambos os firmwares do mesmo commit e executar bancadas de 6, 12, 25 e 32 pontos.

## Related

[[hardening-planner-rpv2-32-pontos-2026-06-19]]
[[protocolo-rpv2]]
