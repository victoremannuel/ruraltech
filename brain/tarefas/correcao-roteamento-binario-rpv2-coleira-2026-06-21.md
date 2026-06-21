# Task: Correcao Roteamento Binario RPv2 Coleira 2026-06-21

#ruraltech
#tarefas

## Context

Implementar na `main` o plano `ruraltech_rpv2_collar_binary_routing_crash_fix_plan.md`, corrigindo o crash `LoadProhibited` da coleira antes do `FENCE_BEGIN_ACK` sem alterar planner, CRC canonico, fragmentacao, COMMIT, APPLY_STATUS ou contratos cloud.

Continua [[protocolo-rpv2]] e [[hardening-rpv2-commit-apply-sessao-longa-32-pontos-2026-06-20]].

## Action

- [x] Carregar Graphify, brain, plano e baseline da `main`
- [x] Confirmar que a base contem o hardening `5bd8b652`
- [x] Rotear `SET_FENCE` binario RPv2 antes do parsing e auditoria JSON
- [x] Preservar binding e scope checks antes do dispatch RPv2
- [x] Inicializar `PolygonAuditContext` deterministicamente
- [x] Tornar strings do `AreaSyncLogger` null-safe
- [x] Adicionar teste host-side de regressao do roteamento
- [x] Executar `git diff --check` e suite host-side
- [ ] Compilar firmware da coleira e da matriz quando o ambiente permitir
- [x] Atualizar arquitetura, checklist e checkpoint no brain
- [ ] Validar bancada de 4, 6, 12, 25 e 32 pontos

## Status

Implementacao local concluida na `main`; build Arduino e bancada permanecem pendentes.

Update context: o caminho defeituoso foi confirmado em `applyDownlink`: payload RPv2 ainda atravessa extracao de metadata, `deserializeJson`, auditoria e log JSON antes de `applyFenceRpv2Frame`.

Update context: o early dispatch foi implementado antes de qualquer operacao JSON, com binding/scope preservados, log binario sem strings do payload e contextos de auditoria inicializados.

Update context: o `AreaSyncLogger` agora sanitiza globalmente strings nulas; a suite host-side oficial, os testes novos de roteamento/logger e `git diff --check` passaram.

## Pending

- [ ] Compilar `coleira` e `gateway-matriz` em ambiente Arduino estavel
- [ ] Gravar ambos os firmwares a partir do mesmo commit limpo
- [ ] Executar bancada de 4, 6, 12, 25 e 32 pontos
- [ ] Confirmar terminal `applied`, ausencia de reset e restauracao NVS de 32 pontos

Update context: os itens pendentes dependem do toolchain embarcado e de hardware/servicos remotos.

## Blockers

Os dois comandos `arduino-cli compile` ficaram mais de 60 segundos sem qualquer saida e foram interrompidos, repetindo o hang silencioso conhecido deste host.

Update context: o bloqueio e de validacao embarcada; a regressao host-side esta verde.

## Next step

Compilar e gravar ambos os firmwares de um commit limpo e executar a matriz de bancada, comecando por 4 pontos e encerrando em 32 pontos.

## Related

[[protocolo-rpv2]]
[[hardening-rpv2-commit-apply-sessao-longa-32-pontos-2026-06-20]]
