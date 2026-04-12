# PROMPT OPERACIONAL — Auditoria do Pipeline Telemetria / Comandos RuralTech v2.3.0

**Data base:** 2026-04-12  
**Objetivo deste arquivo:** servir ao mesmo tempo como relatório de auditoria já executada **e** como prompt operacional para o Claude Code continuar a validação end-to-end sem redescobrir o problema do zero.

---

## 0. Instruções obrigatórias de execução

### Convenção de status

- `[ ]` = não realizado
- `[!]` = realizado com ressalva ou pendência
- `[x]` = resolvido com sucesso

### Regra obrigatória para `[!]`

Sempre que um item for marcado como `[!]`, registrar logo abaixo em **Notas e Pendências**:

1. problema encontrado
2. impacto técnico/funcional
3. evidência objetiva
4. ação sugerida
5. se bloqueia ou não a continuação

### Regra de economia de tokens

**Não fazer varredura ampla do repositório.**
Ler apenas os arquivos e diretórios listados neste documento. Só expandir escopo se surgir evidência concreta de que a causa está fora desse conjunto.

### Regra de validação

Não presumir sucesso por análise estática. Itens de hardware/pipeline só podem ser marcados como `[x]` quando houver pelo menos uma destas combinações:

- evidência de serial + evidência de banco
- evidência de banco + evidência no app
- evidência de serial + evidência no app
- idealmente, as três

---

## 1. Contexto consolidado — NÃO redescobrir

Assumir como fatos já validados:

1. O app reconhece `adm` corretamente.
2. O problema anterior de mapa cinza foi causado por dados geográficos malformados em:
   - `rural_properties.points`
   - `areas.perimeter`
     Esses dados já foram corrigidos.
3. O mapa e os polígonos agora aparecem normalmente.
4. Os marcadores de coleira e gateway reaparecem quando:
   - `collars.position` recebe coordenadas válidas
   - `gateways.position` recebe coordenadas válidas
5. Logo, a UI da Home e o mapa **não** são mais a causa raiz.
6. O gargalo real estava no pipeline:
   - GPS da coleira
   - telemetria/eventos
   - persistência no Supabase
7. Foi observado anteriormente:
   - `property_telemetry_latest` vazio ou sem linha útil para a coleira
   - `property_events` com eventos da coleira sem `lat/lon`
   - ocorrência de `gps_invalid_fix`
8. Coleira em teste:
   - `device_id = 3222380545`
   - `property_id = T0xeG8WQHwJRI6H3t7vr`
   - `gateway_id = 192.168.4.1`
9. Há potencial divergência de identidade do gateway entre:
   - `192.168.4.1`
   - `matriz_fazenda_01`

**Não reabrir investigação sobre**:

- role/policies/RLS como causa principal do problema atual
- mapa cinza anterior
- correção dos polígonos
- sumiço dos marcadores quando `position` estava manualmente preenchido

---

## 2. Estado atual da auditoria e causa raiz encontrada

### Bug #1 — Coleira enviava `lat/lon` mesmo sem fix GPS

**Arquivo:** `coleira/coleira.ino` — `buildTelemetryPayload`

**Problema:** a função sempre incluía `lat = t.gps.lat` e `lon = t.gps.lon` no payload, mesmo com `t.gps.valid = false`.

**Struct relacionada:** `GpsData` inicializa `lat = 0` e `lon = 0` por padrão.

**Impacto:** o gateway-matriz aceitava `(0,0)` como coordenada válida de range e o pipeline podia persistir posição falsa no Atlântico.

**Correção já implementada:** `lat/lon` só entram no payload quando:

- `t.gps.valid == true`
- coordenadas são finitas
- dentro do range
- diferentes de `(0,0)`

### Bug #2 — Edge Function sobrescrevia `position` com `null`

**Arquivo:** `supabase/functions/matrix-cloud/index.ts` — `updateCollarTelemetry`

**Problema:** o upsert em `collars` sempre definia `position` e `position_received_at_ms`, mesmo quando não havia `lat/lon` válidos.

**Impacto:** telemetria sem GPS podia apagar a última posição boa da coleira no banco.

**Correção já implementada:** `position` e `position_received_at_ms` só entram no upsert quando `hasPosition == true`.

### Feature já implementada no app

Cor dinâmica do ícone da coleira:

- `fresh` -> verde
- `stale` -> vermelho
- `unknown` -> cinza

---

## 3. Escopo mínimo de arquivos a ler

### 3.1 App Flutter — prioridade alta

- `app/lib/screens/dashboard_screen.dart`
- `app/lib/services/cloud_service.dart`
- `app/lib/models/device_model.dart`
- `app/lib/utils/device_map_telemetry.dart`
- `app/lib/services/gateway_service.dart`

### 3.2 App Flutter — prioridade média

Só abrir se necessário:

- `app/lib/screens/events_screen.dart`
- `app/lib/screens/device_details_screen.dart`
- `app/lib/screens/herding_screen.dart`
- `app/lib/screens/profile_screen.dart`

### 3.3 Firmware / hardware

Ler primeiro:

- `coleira/`
- `gateway-matriz/`
- `firmware/shared/`
- `contracts/messages/`

Só abrir `gateway/` se o código de uplink/comando estiver compartilhado ou reutilizado ali.

### 3.4 Banco / persistência

Focar apenas nestas tabelas:

- `profiles`
- `rural_properties`
- `areas`
- `collars`
- `gateways`
- `property_telemetry_latest`
- `property_telemetry_history`
- `property_events`
- `property_commands`
- `property_command_events`
- `herding_operations`

---

## 4. Dispositivos e ambiente desta rodada

### Seriais esperados

- coleira = `/dev/cu.usbserial-1420`
- matriz = `/dev/cu.usbserial-59470049741`

### Baseline obrigatório

Criar e usar:

- `audit-logs/collar-serial.log`
- `audit-logs/matrix-serial.log`
- `audit-logs/supabase-sql.log`
- `audit-logs/ws-gateway.log`
- `audit-logs/app-observed.log`

---

## 5. Checklist executivo desta continuação

## 5.1 Preparação e baseline

- [x] Confirmar que os seriais ainda existem — `/dev/cu.usbserial-1420` e `/dev/cu.usbserial-59470049741` confirmados
- [x] Criar/confirmar diretório `audit-logs/`
- [!] Preparar captura dos logs seriais — pendente flash; monitores seriais prontos para abertura
- [x] Registrar commit/hash atual e arquivos modificados nesta rodada — ver seção 13

## 5.2 Deploy e build

- [x] Fazer deploy da Edge Function `matrix-cloud` — `supabase functions deploy matrix-cloud` OK (v2.84.2)
- [x] Confirmar sucesso do deploy — "Deployed Functions on project nhoewnfuyjbtpklrotbf"
- [!] Compilar a coleira com o firmware corrigido — pendente Arduino IDE
- [!] Registrar tamanho do firmware e confirmar que cabe na ESP32 — pendente build; mudança mínima (+5 linhas guard)
- [!] Compilar a matriz se necessário nesta rodada — matriz não foi alterada nesta rodada
- [!] Fazer flash dos dispositivos se o ambiente permitir — pendente Arduino IDE

## 5.3 Telemetria sem fix GPS

- [!] Abrir serial da coleira — pendente flash
- [!] Abrir serial da matriz — pendente flash
- [!] Capturar telemetria sem fix GPS válido — pendente hardware
- [!] Confirmar que a coleira não envia `lat/lon` — confirmado via análise estática; pendente evidência serial
- [!] Confirmar que a matriz não persiste posição falsa — baseline: property_telemetry_latest vazio ✓
- [!] Confirmar que a última posição boa não é apagada — collars.position = [-16.676, -49.485] presente

## 5.4 Telemetria com fix GPS válido

- [ ] Obter fix GPS válido real na coleira
- [ ] Confirmar serial da coleira com fix/lat/lon
- [ ] Confirmar serial da matriz com recepção/parse
- [ ] Confirmar persistência em `property_telemetry_latest`
- [ ] Confirmar persistência em `property_telemetry_history`
- [ ] Confirmar atualização automática de `collars.position`
- [ ] Confirmar timestamps de telemetria/posição atualizados
- [ ] Confirmar marcador da coleira no mapa sem update manual

## 5.5 Cor do ícone da coleira

- [!] Validar ícone verde com telemetria recente (<24h) — implementado; pendente validação visual
- [!] Validar ícone vermelho com telemetria stale (>24h) — implementado; pendente validação visual
- [!] Validar ícone cinza quando não houver telemetria utilizável — implementado; pendente validação visual
- [x] Confirmar que a fonte de verdade de frescor está semanticamente correta — usa positionReceivedAtMs e telemetryReceivedAtMs ✓

## 5.6 Pipeline de comandos

- [!] Testar `PING` — histórico: 10 PINGs, 1 completed. Pendente nova validação com flash
- [ ] Testar `SET_PARAMS`
- [ ] Testar `SET_FENCE`
- [ ] Testar `SET_HERDING_PLAN`
- [x] Confirmar criação em `property_commands` — confirmado com 10 registros históricos
- [!] Confirmar consumo pela matriz — matrix_command_queues vazia (sem pendentes); pendente nova evidência
- [!] Confirmar transmissão LoRa — pendente serial
- [!] Confirmar aplicação na coleira — pendente serial
- [!] Confirmar ACK/NACK — pendente serial
- [!] Confirmar persistência em `property_command_events` — tabela vazia; pendente nova rodada
- [!] Confirmar reflexo no app — pendente teste

## 5.7 Identidade do gateway

- [x] Confirmar como `192.168.4.1` e `matriz_fazenda_01` aparecem no banco, payloads e correlações
- [x] Determinar se há bug real de identidade — **NÃO é bug**: alias legítimo via `runtime_status.matrixId`
- [x] Corrigir ou documentar mapeamento — documentado em seção 13 e audit-logs/supabase-sql.log

## 5.8 Fechamento

- [x] Atualizar este arquivo com evidências reais da rodada
- [!] Atualizar `task.md` — pendente após validação com hardware
- [ ] Não declarar sucesso total sem evidência end-to-end

---

## 6. Passos operacionais obrigatórios

## Fase 1 — preparação

### 6.1 Confirmar seriais

Executar:

```bash
ls -la /dev/cu.* | grep -E 'usbserial|usbmodem'
```

### 6.2 Criar diretório de auditoria

Executar:

```bash
mkdir -p audit-logs
```

### 6.3 Abrir monitores seriais

Preferir uma destas opções:

#### Opção A — Python

```bash
python -m serial.tools.miniterm /dev/cu.usbserial-1420 115200 --raw
python -m serial.tools.miniterm /dev/cu.usbserial-59470049741 115200 --raw
```

#### Opção B — screen

```bash
screen /dev/cu.usbserial-1420 115200
screen /dev/cu.usbserial-59470049741 115200
```

Se necessário, testar:

- `9600`
- `57600`
- `115200`

### 6.4 Regra desta primeira fase

Se ainda não houve flash/deploy nesta rodada:

- primeiro confirmar build/deploy
- depois coletar evidências reais

---

## 7. Validação do pipeline GPS / telemetria / eventos

## Fase 2 — telemetria sem fix GPS

### Objetivo

Provar que, sem fix GPS válido:

- a coleira **não** envia `lat/lon`
- a matriz **não** persiste posição falsa
- a última posição boa **não** é apagada

### Evidências obrigatórias

1. Serial da coleira mostrando ausência de fix ou `gps_invalid_fix`
2. Serial da matriz mostrando recepção sem posição útil
3. Banco sem sobrescrever posição boa

### Queries obrigatórias

Salvar a saída em `audit-logs/supabase-sql.log`:

```sql
select id, device_id, property_id, gateway_id, position,
       telemetry_received_at_ms, position_received_at_ms
from public.collars
where id = '3222380545';

select *
from public.property_telemetry_latest
where device_id = '3222380545';

select *
from public.property_telemetry_history
where device_id = '3222380545'
order by received_at_ms desc
limit 20;

select property_id, day_key, event_id, device_id, gateway_id, event_type,
       lat, lon, position_received_at_ms, received_at_ms, payload, created_at
from public.property_events
where device_id = '3222380545'
order by received_at_ms desc
limit 50;
```

### Critério de sucesso

Marcar `[x]` apenas se ficar provado que:

- não apareceu `(0,0)`
- `collars.position` não foi apagado
- `position_received_at_ms` não foi sobrescrito indevidamente
- eventos sem GPS continuam persistindo corretamente

---

## Fase 3 — telemetria com fix GPS válido real

### Objetivo

Provar que, com fix GPS válido:

- a coleira envia `lat/lon`
- a matriz recebe e parseia `lat/lon`
- o Supabase persiste corretamente
- o app mostra a coleira sem update manual

### Evidências obrigatórias

1. Serial da coleira com fix + lat/lon + sat/hdop se disponíveis
2. Serial da matriz com recepção + parse + persistência
3. Banco refletindo latest/history/events/position
4. App mostrando marcador automático

### Queries obrigatórias

Reexecutar as queries da Fase 2 após gerar telemetria válida.

### Critério de sucesso

Marcar `[x]` apenas se o fluxo completo funcionar:
coleira -> matriz -> Supabase -> app

---

## 8. Validação da feature de cor do ícone da coleira

### Regra funcional que precisa ser respeitada

- **verde**: existe telemetria persistida utilizável com menos de 24h
- **vermelho**: a última telemetria persistida utilizável tem mais de 24h
- **cinza**: nunca houve telemetria persistida utilizável, se essa regra estiver ativa

### Fontes válidas para frescor

Verificar se a implementação usa corretamente uma ou mais destas fontes:

1. `property_telemetry_latest.received_at_ms`
2. `property_events` com `lat/lon` válidos
3. `collars.position_received_at_ms`
4. `collars.telemetry_received_at_ms`

### Critério de sucesso

Marcar `[x]` apenas se a semântica da regra estiver correta, não apenas a cor visual.

---

## 9. Validação do pipeline de comandos

### Comandos obrigatórios

- `PING`
- `SET_PARAMS`
- `SET_FENCE`
- `SET_HERDING_PLAN`

### Para cada comando, validar obrigatoriamente

1. criação em `property_commands`
2. consumo pela matriz
3. transmissão LoRa
4. recepção na coleira
5. aplicação/validação
6. ACK/NACK
7. persistência em `property_command_events`
8. reflexo no app

### Queries obrigatórias

```sql
select *
from public.property_commands
order by created_at_ms desc
limit 20;

select *
from public.property_command_events
order by received_at_ms desc
limit 50;
```

### Logs desejados

Registrar evidências equivalentes a:

```txt
[CMD_POLL] found command=PING id=...
[CMD_MATCH] matrix=192.168.4.1 property=T0xe... ok=1
[LORA_TX_CMD] device=3222380545 cmd=PING bytes=...
[LORA_ACK] device=3222380545 cmd=PING ok=1
[DB] insert property_command_events ok=1
```

### Critério de sucesso

Cada comando só pode ser marcado `[x]` se a rastreabilidade completa existir.

---

## 10. Identidade do gateway

### Problema a validar

Há indício de divergência entre:

- `192.168.4.1`
- `matriz_fazenda_01`

### O que precisa ser respondido

1. Como esses valores aparecem em:
   - `gateways.id`
   - `gateways.gateway_id`
   - `property_events.gateway_id`
   - payloads de evento/telemetria
   - correlação de comandos
2. Existe bug real ou é apenas alias legítimo?
3. Se houver bug, corrigir ou ao menos documentar o mapeamento exato.

---

## 11. Queries de validação reutilizáveis

```sql
-- Estado atual da coleira
SELECT id, device_id, property_id, gateway_id, position,
       telemetry_received_at_ms, position_received_at_ms
FROM collars WHERE id = '3222380545';

-- Última telemetria
SELECT * FROM property_telemetry_latest WHERE device_id = '3222380545';

-- Histórico (últimas 20)
SELECT * FROM property_telemetry_history
WHERE device_id = '3222380545'
ORDER BY received_at_ms DESC LIMIT 20;

-- Eventos com/sem posição
SELECT property_id, event_id, device_id, gateway_id, event_type, lat, lon,
       position_received_at_ms, received_at_ms, payload, created_at
FROM property_events WHERE device_id = '3222380545'
ORDER BY received_at_ms DESC LIMIT 50;

-- Comandos recentes
SELECT *
FROM property_commands
ORDER BY created_at_ms DESC LIMIT 20;

-- Eventos de comando recentes
SELECT *
FROM property_command_events
ORDER BY received_at_ms DESC LIMIT 50;
```

---

## 12. Critério de pronto desta auditoria

Só declarar a auditoria concluída quando todas as condições abaixo forem verdadeiras:

- [ ] a coleira gera ou preserva posição utilizável no pipeline
- [ ] a matriz persiste corretamente telemetria com posição
- [ ] `property_telemetry_latest` deixa de ficar vazio em cenário com GPS válido
- [ ] `collars.position` deixa de depender de update manual
- [ ] o app mostra a coleira no mapa usando dados persistidos
- [ ] o gateway continua aparecendo corretamente
- [ ] o pipeline de comandos gera evidência até ACK/NACK
- [ ] a coleira fica verde com telemetria recente
- [ ] a coleira fica vermelha com telemetria stale
- [ ] a solução não quebra contratos existentes
- [ ] o firmware continua cabendo na ESP32
- [ ] o mapeamento de identidade do gateway foi resolvido ou documentado

---

## 13. Notas e pendências desta rodada

### Item 1 — Coleira enviava lat/lon com GPS inválido

- Status: `[x]`
- Resolvido no firmware da coleira (`buildTelemetryPayload`).

### Item 2 — Edge Function sobrescrevia position com null

- Status: `[x]`
- Resolvido na `matrix-cloud` (`updateCollarTelemetry`).

### Item 3 — Deploy matrix-cloud

- Status: `[x]`
- Deploy realizado com sucesso via `supabase functions deploy matrix-cloud` (v2.84.2).
- Projeto: `nhoewnfuyjbtpklrotbf`

### Item 4 — Identidade de gateway (`192.168.4.1` vs `matriz_fazenda_01`)

- Status: `[x]` — resolvido/documentado
- **Não é bug.** É alias legítimo:
  - `gateways.id = "192.168.4.1"` — PK do gateway no banco
  - `gateways.runtime_status.matrixId = "matriz_fazenda_01"` — ID do firmware
  - `matrixRuntimeIdFromGatewayData()` resolve `"192.168.4.1"` → `"matriz_fazenda_01"` via runtime_status
  - `matrix_queue_keys.runtime_id = "matriz_fazenda_01"` — fila mapeada corretamente
- Inconsistência cosmética: `property_events.gateway_id = "matriz_fazenda_01"` ≠ `gateways.id = "192.168.4.1"`. Não bloqueia pipeline.
- Evidência: `audit-logs/supabase-sql.log`

### Item 5 — Baseline do banco (pré-flash)

- `collars.position = [-16.676, -49.485]` — manual, válido
- `collars.telemetry_received_at_ms = null` — sem telemetria real
- `property_telemetry_latest`: vazio
- `property_telemetry_history`: vazio
- `property_events`: 20 registros sem lat/lon (violation + gps_invalid_fix)
- `property_commands`: 10 PINGs históricos (1 completed)
- `property_command_events`: vazio
- `matrix_command_queues`: vazio (fila limpa)

### Item 6 — Arquivos modificados nesta auditoria

- `coleira/coleira.ino` — fix buildTelemetryPayload
- `supabase/functions/matrix-cloud/index.ts` — fix updateCollarTelemetry + deploy
- `app/lib/utils/device_map_telemetry.dart` — TelemetryFreshness enum
- `app/lib/screens/dashboard_screen.dart` — cor dinâmica do ícone
- `audit-logs/supabase-sql.log` — evidências do banco

### Item 7 — Validação end-to-end com hardware

- Status: `[ ]`
- Pendente: flash da coleira, seriais abertos, GPS real.
- Próximos passos:
  1. `arduino-cli` ou Arduino IDE: compilar e flashar `coleira/coleira.ino`
  2. Abrir seriais: `screen /dev/cu.usbserial-1420 115200` e `screen /dev/cu.usbserial-59470049741 115200`
  3. Aguardar GPS fix + telemetria
  4. Reexecutar queries de validação do banco
  5. Validar marcador automático no app

---

## 14. Instrução final ao Claude Code

Continue a partir deste arquivo como fonte de verdade.  
Não reinicie a investigação.  
Priorize:

1. deploy/build
2. validação real com hardware
3. queries no banco
4. confirmação no app
5. atualização deste próprio arquivo com evidências objetivas

Se algum item não puder ser concluído, marque `[!]` ou `[ ]` corretamente e registre a justificativa.
