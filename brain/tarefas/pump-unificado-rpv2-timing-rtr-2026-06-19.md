# Task: Pump Unificado RPv2 + Timing RTR 2026-06-19

#ruraltech
#tarefas

## Context

Correção E2E da comunicação App → Coleiras (`SET_FENCE` → `applied`). No bench `59295c0` os 3 comandos falharam: 2× `waiting_uplink_timeout` (morreram no RTR) e 1× `points_retry_exhausted` (chegou a `RPV2_BEGIN_ACK_TX` mas nunca recebeu `FENCE_POINTS#1`).

Continua [[estabilizacao-transporte-rpv2-2026-06-19]] e [[rpv2-points-fragment-handoff-2026-04-27]]; segue [[protocolo-rpv2]].

### Causas-raiz confirmadas

1. **Coleira (primária):** o branch `FENCE_BEGIN` de `applyFenceRpv2Frame()` enviava `BEGIN_ACK_TX` e retornava **sem abrir janela de RX** para `FENCE_POINTS#1`. Mesma classe de bug já corrigida em `POINTS→COMMIT` no `59295c0`, agora na transição `BEGIN_ACK→POINTS#1`.
2. **Matriz (secundária):** `reschedulePendingWakeForFreshUplink()` exigia `FAST_PAGE_DEADLINE_MS=300ms` de frescor do uplink para paginar; latência real ~1119ms → hint sempre stale → churn `PAGING_WAITING_UPLINK` → `waiting_uplink_timeout` a 180s.

### Decisão de arquitetura

Em vez de só adicionar a janela faltante, **unificar as 3 janelas síncronas aninhadas (BEGIN/POINTS/COMMIT) num único pump iterativo plano** `runRpv2SessionReceivePump()` — elimina a classe de bug e o risco de recursão/stack. Fundamentado em LoRaWAN Class A / Symphony Link (RX ancorada na própria TX do nó). Detalhe em [[protocolo-rpv2]].

## Action

### Part A — Coleira (pump unificado)
- [x] `shouldOpenFirstPointsWindow()` em `rpv2_transport_policy.h`
- [x] Campo `lastAckTxAtMs` na struct `Rpv2FenceSessionState`
- [x] Gravar `lastAckTxAtMs` após cada `sendRpv2Ack` (BEGIN, POINTS, duplicate)
- [x] Remover chaining de `applyFenceRpv2Frame` (POINTS branch)
- [x] Nova `runRpv2SessionReceivePump(sessionId, scopeId, pageAckTxAtMs)` — loop plano, stage derivado do estado, deadline re-ancorado em `lastAckTxAtMs`
- [x] Teto de segurança `RPV2_SESSION_MAX_MS = 60000` em config.h
- [x] Remover `waitForRpv2BeginImmediatelyAfterPageAck` / `waitForRpv2PointsImmediatelyAfterAck` / `waitForRpv2CommitImmediatelyAfterAck`
- [x] Logs `RPV2_FIRST_POINTS_RX_WINDOW_BEGIN/END` (novo) + preservar nomes por estágio

### Part B — Matriz (timing RTR)
- [x] `WAKE_HINT_FRESHNESS_MS = 2500` em `radio_transport_v1_constants.h`
- [x] Usar `WAKE_HINT_FRESHNESS_MS` no freshness gate (no lugar de `FAST_PAGE_DEADLINE_MS`)
- [x] `FAST_PAGE_DEADLINE_MS` permanece só em `computeFastPathMetric` (diagnóstico)
- [x] Novo `rtr_wake_policy.h` com `waitingUplinkTimeoutMs(estimatedCycleMs, floor, margin)` (só `<stdint.h>`)
- [x] Timeout dinâmico em `PAGING_WAITING_UPLINK` via `estimatedCycleMs` de `devicePresence`

### Part C — Testes + CI
- [x] Casos `shouldOpenFirstPointsWindow` em `rpv2_transport_policy_test.cpp`
- [x] Novo `rtr_wake_policy_test.cpp`
- [x] CI `pr-quality.yml` roda `rtr_wake_policy_test`
- [x] Todos os 5 testes host-side passam (`g++ -std=c++17 -Wall -Wextra -pedantic`)

### Pendente
- [x] Compilar firmware coleira (arduino-cli via rtk) — **flash 60% / RAM 21%**, exit 0
- [ ] Compilar firmware matriz (em andamento)
- [ ] Bench físico 6 pontos (2 chunks) → `applied`

## Status

Implementação local concluída e testes host-side aprovados (5/5). Coleira compilada com sucesso (flash 60%, RAM 21%) — o pump não aumentou footprint (removeu 2 funções). Compilação da matriz e bench físico pendentes.

## Next step

Compilar ambos firmwares; bench de 6 pontos validando `RPV2_BEGIN_ACK_TX → RPV2_FIRST_POINTS_RX_WINDOW_BEGIN → RPV2_POINTS_RX#1 → #2 → RPV2_STAGE_COMPLETE → RPV2_COMMIT_RX → RPV2_CRC_OK → RPV2_SESSION_COMPLETE` e Supabase `status=applied`, `device_results.3222380545.ok=true`, sem `waiting_uplink_timeout`/`points_retry_exhausted`.

## Related

[[estabilizacao-transporte-rpv2-2026-06-19]]
[[protocolo-rpv2]]
[[rpv2-points-fragment-handoff-2026-04-27]]
[[ack-to-rpv2-fast-handoff-2026-04-26]]
