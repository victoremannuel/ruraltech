# Task: Estabilização do Transporte RPv2 2026-06-19

#ruraltech
#tarefas

## Context

Implementar o plano `ruraltech_rpv2_transport_implementation_plan.md` para tornar o transporte `SET_FENCE` determinístico entre a matriz e a coleira, eliminando trabalho de cloud durante a seção crítica RPv2 e preservando retry, auditoria e segurança.

Continua o trabalho de [[rpv2-points-fragment-handoff-2026-04-27]] e segue a arquitetura [[protocolo-rpv2]].

## Action

- [x] Confirmar baseline e preservar alterações preexistentes
- [x] Instrumentar latência ACK -> próximo fragmento na matriz
- [x] Implementar seção radio-crítica RPv2 na matriz
- [x] Implementar fila fixa de status diferidos e flush pós-sessão
- [x] Bloquear cloud, polling e telemetria durante a seção crítica
- [x] Implementar retry de fragmentos na matriz
- [x] Tornar recepção duplicada de fragmentos idempotente na coleira
- [x] Configurar janelas RPv2 e grace period de retry na coleira
- [x] Limpar sessão incompleta após expiração do retry
- [x] Endurecer drain de eventos e adicionar diagnóstico de heap
- [x] Adicionar ou atualizar testes host-side
- [ ] Compilar firmware da matriz
- [ ] Compilar firmware da coleira
- [x] Executar validações estáticas e testes automatizados
- [x] Documentar evidências, pendências de bancada e resultado final

## Status

Implementação local concluída; validação física e compilação Arduino permanecem pendentes.

Update context: matriz e coleira alteradas, testes host-side aprovados e Graphify atualizado em 2026-06-19.

Validações concluídas:
- `git diff --check`
- testes de contrato, stream e anti-replay
- codec, CRC e planner RPv2
- diagnóstico RTR e prioridade do fast path
- nova política `rpv2_transport_policy`

Blocker:
- `arduino-cli compile` de matriz e coleira foi interrompido após repetir o hang silencioso histórico deste host, sem saída por mais de 45 segundos.

## Next step

Compilar e gravar ambos os firmwares em host estável, executar a bancada de 6 pontos e comprovar `fragment 1 ACK -> fragment 2 TX/RX/ACK`, flush pós-seção crítica e ausência de heap assert.

## Related

[[ack-to-rpv2-fast-handoff-2026-04-26]]
[[fluxo-comandos]]
