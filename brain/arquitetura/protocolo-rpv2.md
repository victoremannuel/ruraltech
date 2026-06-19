# Architecture: Protocolo RPv2 (Radio Protocol v2)

#ruraltech
#arquitetura

## Overview

Protocolo binário para transmissão de cercas virtuais (SET_FENCE) via LoRa, com sessão em 3 etapas (BEGIN → POINTS → COMMIT), validação CRC32 e confirmação de aplicação real.

Substitui o envio JSON textual para comandos de cerca, oferecendo:
- Maior eficiência de bytes (overhead reduzido por chunk)
- Validação CRC32 por etapa e final
- Sessão com estado (staging em memória)
- Confirmação explícita de aplicação (`APPLY_STATUS`)
- Planner de chunking baseado em tamanho real do frame
- Seção radio-crítica na matriz sem I/O de cloud entre `BEGIN` e o estado terminal
- Retry idempotente de fragmentos, sem reaplicar pontos já aceitos
- Janela síncrona de COMMIT imediatamente após o ACK do último fragmento
- Flush cloud terminal-first, coalescido e limitado por orçamento cooperativo

## Components

### Matriz (gateway-matriz)

| Componente | Arquivo | Responsabilidade |
|---|---|---|
| `LoRaGateway` | `LoRaGateway.cpp` | Envio binário, medição de frame seguro, planner |
| `radio_proto_v2_codec` | `firmware/shared/radio_proto_v2_codec.h` | Codificação/decodificação binária |
| `radio_proto_v2_crc` | `firmware/shared/radio_proto_v2_crc.h` | Cálculo CRC32 |
| `radio_proto_v2_types` | `firmware/shared/radio_proto_v2_types.h` | Estruturas binárias on-wire |
| `radio_proto_v2_constants` | `firmware/shared/radio_proto_v2_constants.h` | Constantes do protocolo |
| `radio_proto_v2_id` | `firmware/shared/radio_proto_v2_id.h` | FNV-1a 64 para radio_command_id |
| `radio_proto_v2_reason_codes` | `firmware/shared/radio_proto_v2_reason_codes.h` | Códigos de erro/status |
| `rpv2_transport_policy` | `firmware/shared/rpv2_transport_policy.h` | Política compartilhada de retry, duplicidade e deadlines; inclui `shouldOpenFirstPointsWindow` e `shouldOpenCommitWindow` |
| `rtr_wake_policy` | `firmware/shared/rtr_wake_policy.h` | `waitingUplinkTimeoutMs(estimatedCycleMs, floor, margin)` — timeout dinâmico de espera de uplink proporcional ao ciclo real do dispositivo |
| `command_id_policy` | `firmware/shared/command_id_policy.h` | Limite canônico de 128 bytes e cópia sem truncamento silencioso |
| Fila de status diferidos | `gateway-matriz/gateway-matriz.ino` | Preserva progresso em RAM e faz flush após a seção radio-crítica |

### Coleira

| Componente | Arquivo | Responsabilidade |
|---|---|---|
| `coleira.ino` | `coleira/coleira.ino` | Recepção binária, validação, staging, apply |
| `StorageQueue` | `coleira/StorageQueue.*` | Drain transacional `peek → send → ack`, com burst limitado |

### Testes

| Teste | Arquivo | Validação |
|---|---|---|
| `rpv2_codec_test` | `firmware/tests/rpv2_codec_test.cpp` | Codificação/decodificação |
| `rpv2_crc_test` | `firmware/tests/rpv2_crc_test.cpp` | Cálculo CRC32 |
| `rpv2_fence_planner_test` | `firmware/tests/rpv2_fence_planner_test.cpp` | Planner de chunking |
| `rpv2_transport_policy_test` | `firmware/tests/rpv2_transport_policy_test.cpp` | Política de retry/duplicidade, `shouldOpenFirstPointsWindow`, `shouldOpenCommitWindow` (CI) |
| `rtr_wake_policy_test` | `firmware/tests/rtr_wake_policy_test.cpp` | `waitingUplinkTimeoutMs` (floor, dinâmico, margem) (CI) |

## Flow

### Sessão RPv2 (Matriz → Coleira)

```
1. BEGIN
   Matriz: radio_command_id = FNV-1a 64(property_id + fence_hash)
           fence_crc = CRC32(points array)
           frame = {type: BEGIN, radio_command_id, pointCount, fence_crc, header_crc}
   → LoRa TX
   ← ACK/NACK da coleira (CRC OK, staging preparado)

2. POINTS (chunk 0..N-1)
   Matriz: planner calcula chunks com overhead real
           frame = {type: POINTS, chunk_index, points[], chunk_crc}
   → LoRa TX (N frames)
   ← ACK/NACK por chunk
   Timeout: retransmite o mesmo fragmento até 3 tentativas.
   Duplicata já aceita: responde ACK sem anexar pontos novamente.

3. COMMIT
   Coleira: após o ACK final, abre janela síncrona de 10 s para COMMIT.
            Valida binding, scope, tipo externo, header, tipo interno,
            radio_command_id e session_nonce antes de reutilizar applyDownlink.
   Matriz: frame = {type: COMMIT, fence_crc}
   → LoRa TX
   ← APPLY_STATUS (success=true/false, reasonCode)

4. Resultado
   Matriz: persiste property_commands com:
           transport=radio_fence_v2
           transportState=pending|sending|waiting|applied|failed
           reasonCode=<codigo>
```

### Seção radio-crítica e deferral de cloud

Após o `RTR_PAGE_ACK`, a matriz entra em `RPV2_RADIO_CRITICAL_ENTER` antes do
`FENCE_BEGIN`. Atualizações de transporte ficam em uma fila fixa de 16 entradas;
`rtdbWrite`, publicação de resultado e eventos não executam nesse intervalo.

Ao concluir ou abortar, a guarda emite `RPV2_RADIO_CRITICAL_EXIT` e tenta um
único item. Todos os call sites normais usam orçamento 1, com máximo absoluto 2,
slice de 750 ms e intervalo mínimo de 250 ms. O watchdog é alimentado antes e
depois de cada publicação. Status terminal do comando ativo tem prioridade;
estados intermediários repetitivos são coalescidos, enquanto ACKs de fragmentos
permanecem distintos. Após publicar o terminal, intermediários supersededidos do
mesmo comando/dispositivo são removidos para impedir regressão cloud.

Cada item registra tentativas e próximo instante elegível;
falhas usam backoff de 1 s, 3 s, 10 s e depois 30 s, sem `delay()` e sem hot
loop. O item só é removido após publicação completa, e o contexto do command ID
deve coincidir com o comando ativo. Se o backhaul estiver indisponível, o
comando ativo permanece retido até que o estado terminal possa ser publicado.

Command IDs de cloud são preservados em buffers fixos de 128 bytes na matriz e
na coleira. Overflow é rejeitado com `command_id_too_long`; não há truncamento
silencioso nos estados ativos, sessões de wake, feedback ou fila diferida.

### Pump unificado de recepção (coleira) — Class-A-like

A partir de 2026-06-19, a recepção síncrona da sessão RPv2 na coleira é dirigida
por um **único loop iterativo plano**, `runRpv2SessionReceivePump(sessionId,
scopeId, pageAckTxAtMs)`, que substitui as 3 funções aninhadas anteriores
(`waitForRpv2BeginImmediatelyAfterPageAck`, `waitForRpv2PointsImmediatelyAfterAck`,
`waitForRpv2CommitImmediatelyAfterAck`).

Motivação: a recursão `applyDownlink → handler → próxima janela` deixava lacunas
entre estágios. A transição `BEGIN_ACK → POINTS#1` **não tinha janela**: a coleira
enviava `BEGIN_ACK_TX` e voltava ao loop principal, não escutando quando a matriz
disparava `FENCE_POINTS#1` → `points_retry_exhausted`. Mesma classe do gap
`POINTS→COMMIT` corrigido antes.

O pump deriva o estágio do estado da sessão a cada iteração:
- `WAIT_BEGIN` enquanto `!session.active` → janela `RPV2_BEGIN_IMMEDIATE_RX_WINDOW_MS` (3 s), ancorada em `pageAckTxAtMs`.
- `WAIT_POINTS` enquanto `!stageComplete` → `RPV2_POINTS_IMMEDIATE_RX_WINDOW_MS` (10 s), re-ancorada em `lastAckTxAtMs`. O primeiro fragmento loga `RPV2_FIRST_POINTS_RX_WINDOW_BEGIN/END`.
- `WAIT_COMMIT` após `stageComplete` → `RPV2_COMMIT_IMMEDIATE_RX_WINDOW_MS` (10 s), re-ancorada em `lastAckTxAtMs`.

Cada janela é **re-ancorada na última TX** (`lastAckTxAtMs`, novo campo em
`Rpv2FenceSessionState`, gravado após cada `sendRpv2Ack`) — padrão LoRaWAN Class A /
Symphony Link: a RX abre logo após a própria TX do nó. `applyFenceRpv2Frame` volta
a ser "processa 1 frame → ACK → atualiza estado", sem abrir janelas. Um único
`LoRaFrame` por iteração (pilha plana, sem recursão). Teto de segurança global
`RPV2_SESSION_MAX_MS` (60 s). Watchdog alimentado a cada iteração. Sem cloud I/O
no pump.

### Timeout e recovery da coleira

A janela imediata de pontos é configurável e usa 10 segundos na bancada.
Quando expira, a sessão preserva contexto mínimo por um grace period limitado.
Ao final desse prazo, staging e modo RTR são limpos sem ativar cerca incompleta.

Após o último ACK de pontos, a coleira abre uma janela imediata de COMMIT de
10 segundos. Se o COMMIT não chegar, mantém somente a espera limitada por mais
15 segundos; ao expirar, encerra a sessão com `commit_wait_timeout`, em vez de
aguardar todo o wake lock.

### Timing do RTR na matriz (paging de nó dormindo)

O agendador de wake (`RtrWakeOrchestrator`) pagina o dispositivo só após um uplink
recente provar que está acordado. Dois ajustes (2026-06-19):

- **Freshness gate desacoplado do soft-deadline diagnóstico:** o gate de paginação
  usa `WAKE_HINT_FRESHNESS_MS = 2500` (não mais `FAST_PAGE_DEADLINE_MS = 300`). A
  latência real uplink→page é ~1119 ms, então o limiar de 300 ms tornava o hint
  sempre stale → churn `PAGING_WAITING_UPLINK` → `waiting_uplink_timeout`.
  `FAST_PAGE_DEADLINE_MS` permanece apenas como métrica em `computeFastPathMetric`.
- **Timeout de espera de uplink dinâmico:** no estado `PAGING_WAITING_UPLINK`, o
  timeout vem de `rtrwakepolicy::waitingUplinkTimeoutMs(estimatedCycleMs, floor=180s,
  margin=30s)` = `max(floor, 2×cycle + margin)`, usando `estimatedCycleMs` da
  presença do dispositivo — proporcional ao duty cycle/deep sleep real, em vez de
  um valor fixo.

### Estruturas Binárias

**BEGIN (22 bytes on-wire):**
```
type: u8 (0x01)
radio_command_id: u64 (FNV-1a 64)
pointCount: u16
fence_crc: u32 (CRC32 dos pontos)
header_crc: u32 (CRC32 do header)
```

**POINTS (variável, máx ~100 bytes úteis):**
```
type: u8 (0x02)
chunk_index: u8 (0..254)
points_count: u8
points: array de int40_t (lat*1e7, lon*1e7) → 10 bytes por ponto
chunk_crc: u32
```

**COMMIT (10 bytes):**
```
type: u8 (0x03)
chunk_index: u8 (0xFF = final)
fence_crc: u32
header_crc: u32
```

**ACK/NACK (6 bytes):**
```
type: u8 (0x10=ACK, 0x11=NACK)
radio_command_id: u64 (eco)
stage: u8 (BEGIN|POINTS|COMMIT)
reasonCode: u8 (apenas NACK)
```

**APPLY_STATUS (10 bytes):**
```
type: u8 (0x12)
radio_command_id: u64 (eco)
success: u8 (0/1)
reasonCode: u8
crc: u32
```

### Planner de Chunking

O planner calcula quantos pontos cabem em cada chunk testando payloads candidatos reais:

```cpp
// Pseudocódigo do planner
for (candidate_count = max_points; candidate_count > 0; candidate_count--) {
    build_test_chunk(candidate_count);
    frame_size = measure_safe_frame_size(test_chunk);
    if (frame_size <= LORA_MAX_PAYLOAD) {
        return candidate_count; // cabe
    }
}
return 0; // nem um ponto cabe
```

**Overhead por chunk:**
- `type` (1B) + `chunk_index` (1B) + `points_count` (1B) + `chunk_crc` (4B) = 7B fixos
- Pontos: 10 bytes cada (int40_t lat + int40_t lon)
- Máximo útil: ~12 pontos por chunk (dependendo do perfil LoRa)

## Data Flow

```
App (SET_FENCE JSON)
  ↓
Supabase Edge Function (queue-lora-command)
  ↓
Supabase property_commands + RTDB matrixCommandQueues
  ↓
Matriz (polling/stream)
  ↓
Normalização do payload (points em cascata)
  ↓
Planner RPv2 (calcula chunks)
  ↓
Sessão binária BEGIN → POINTS → COMMIT (LoRa)
  ↓
Coleira (valida CRC, staging, apply)
  ↓
APPLY_STATUS binário
  ↓
Matriz persiste resultado (transport=radio_fence_v2)
  ↓
Supabase propertyEvents / propertyCommandEvents
  ↓
App (Realtime)
```

## Technologies

- **LoRa SX127x**: RF 915MHz, SF7-9, bandwidth 125-250kHz
- **CRC32**: Polynomial 0xEDB88320 (IEEE)
- **FNV-1a 64**: Hash para radio_command_id
- **int40_t**: Coordenadas lat/lon * 1e7 (5 bytes cada)
- **EEPROM/Flash**: Staging de pontos em memória (coleira)

## Risks

| Risco | Mitigação |
|---|---|
| Perda de chunk no ar | ACK/NACK por etapa, timeout de retransmissão |
| CRC falha | Staging descartado, sessão resetada |
| Memória insuficiente | NACK com reasonCode, aborta sessão |
| Timeout de etapa | `no_ack_timeout`, reasonCode persistido |
| Ponto não cabe no frame | Planner falha com `fence_single_point_chunk_too_large` |
| Cloud bloqueia próximo fragmento | Status diferido em RAM e flush pós-sessão |
| COMMIT chega logo após o ACK final fora da escuta normal | Janela síncrona de COMMIT com validação completa e grace timeout |
| Lacuna de escuta entre estágios (ex.: `BEGIN_ACK → POINTS#1`) | Pump unificado que re-ancora a janela em cada TX, sem janelas aninhadas |
| Paging falha por hint stale com nó dormindo | `WAKE_HINT_FRESHNESS_MS=2500` e timeout de espera de uplink proporcional ao ciclo |
| ACK perdido causa reenvio | Fragmento anterior é ACKado idempotentemente |
| Heap instável no drain de eventos | Burst limitado e consumo somente após TX |
| Command ID longo perde correlação cloud | Política compartilhada de 128 bytes e cópia estrita |
| Falha cloud causa hot loop no flush | Retry cooperativo com due time e backoff limitado |
| Flush acumulado dispara watchdog | Um item por slice, limite temporal, gap mínimo e feed antes/depois da publicação |
| Intermediário antigo sobrescreve terminal | Prioridade terminal e limpeza de estados supersededidos após sucesso |
| Registro de auditoria maior colide com GPS na EEPROM | Fila versionada v3 com 8 slots, mantendo o limite reservado |

## Related

[[fluxos-comunicacao-ponta-a-ponta]]
[[fluxo-comandos]]
[[regras-negocio]]
[[padroes-implementacao]]
[[estabilizacao-transporte-rpv2-2026-06-19]]
[[estabilizacao-commit-window-flush-slicing-rpv2-2026-06-19]]
[[pump-unificado-rpv2-timing-rtr-2026-06-19]]

#arquitetura #ruraltech
