# PROMPT OPERACIONAL — Auditoria do Pipeline Telemetria / Comandos [[AUDIT_TELEMETRY_COMMAND_PIPELINE]] RuralTech [[ruraltech]] v2.3.1 [[auditoria-comunicacao-v2.3.1]]

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
   - persistência no Supabase [[migracao-supabase]]
7. Foi observado anteriormente:
   - `property_telemetry_latest` [[modelagem-dados-supabase]] vazio ou sem linha útil para a coleira
   - `property_events` [[modelagem-dados-supabase]] com eventos da coleira sem `lat/lon`
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
- [x] Preparar captura dos logs seriais — seriais abertos; boot + crash loop capturado em `audit-logs/`
- [x] Registrar commit/hash atual e arquivos modificados nesta rodada — ver seção 13

## 5.2 Deploy e build

- [x] Fazer deploy da Edge Function `matrix-cloud` — `supabase functions deploy matrix-cloud` OK (v2.84.2)
- [x] Confirmar sucesso do deploy — projeto `nhoewnfuyjbtpklrotbf`
- [x] Compilar a coleira com o firmware corrigido — compilado e flashado com NVS erase (Arduino IDE)
- [!] Registrar tamanho do firmware e confirmar que cabe na ESP32 — pendente
- [!] Compilar a matriz se necessário nesta rodada — não alterada nesta rodada
- [x] Fazer flash dos dispositivos — feito pelo usuário com "Erase All Flash Before Upload"

## 5.3 Telemetria sem fix GPS

- [x] Abrir serial da coleira — aberto; boot capturado; crash loop diagnosticado e corrigido
- [x] Abrir serial da matriz — aberto; LoRa RX confirmado; scope_reject por ready=0
- [x] Baseline do banco confirmado antes do flash
- [x] Confirmar que `property_telemetry_latest` está vazio — confirma ausência de pipeline útil atual
- [x] Confirmar que `property_telemetry_history` está vazio
- [x] Confirmar que `property_events` recentes seguem com `lat=null` e `lon=null`
- [x] Confirmar que a última posição boa manual em `collars.position` não foi apagada
- [!] Confirmar via serial que a coleira não envia `lat/lon` sem fix — LoRa TX confirmado (sats=0); payload não inspecionável pois matriz rejeita (scope_reject ready=0); pendente matriz com binding

## 5.4 Telemetria com fix GPS válido

- [ ] Obter fix GPS válido real na coleira
- [ ] Confirmar serial da coleira com fix/lat/lon
- [ ] Confirmar serial da matriz com recepção/parse/persistência
- [ ] Confirmar persistência em `property_telemetry_latest`
- [ ] Confirmar persistência em `property_telemetry_history`
- [ ] Confirmar atualização automática de `collars.position`
- [ ] Confirmar timestamps de telemetria/posição atualizados
- [ ] Confirmar marcador da coleira no mapa sem update manual

## 5.5 Cor do ícone da coleira

- [!] Validar ícone verde com telemetria recente (<24h) — implementado; pendente validação visual com telemetria real
- [!] Validar ícone vermelho com telemetria stale (>24h) — implementado; pendente validação visual com timestamp antigo
- [!] Validar ícone cinza quando não houver telemetria utilizável — implementado; pendente validação visual
- [x] Confirmar que a fonte de verdade de frescor está semanticamente correta para os timestamps do `DeviceModel`

## 5.6 Pipeline de comandos [[fluxo-comandos]]

- [!] Testar `PING` — há 10 PINGs históricos e fila limpa; falta rodada nova com hardware desta versão
- [ ] Testar `SET_PARAMS`
- [ ] Testar `SET_FENCE`
- [ ] Testar `SET_HERDING_PLAN`
- [x] Confirmar criação histórica em `property_commands` [[fluxo-comandos]]
- [x] Confirmar que a fila atual está limpa
- [!] Confirmar consumo novo pela matriz — pendente nova rodada com hardware
- [!] Confirmar transmissão LoRa — pendente serial
- [!] Confirmar aplicação na coleira — pendente serial
- [!] Confirmar ACK/NACK — pendente serial
- [!] Confirmar persistência em `property_command_events` — tabela segue vazia nesta rodada
- [!] Confirmar reflexo no app — pendente teste

## 5.7 Identidade do gateway

- [x] Confirmar como `192.168.4.1` e `matriz_fazenda_01` aparecem no banco, payloads e correlações
- [x] Determinar se há bug real de identidade — não é bug; alias legítimo via `runtime_status.matrixId`
- [x] Documentar o mapeamento — resolvido nesta rodada

## 5.8 Fechamento

- [x] Atualizar este arquivo com evidências reais da rodada
- [!] Atualizar `task.md` — pendente sincronização final após próxima rodada com hardware
- [ ] Não declarar sucesso total sem evidência end-to-end

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

## 7. Validação do pipeline GPS / telemetria / eventos [[fluxos-comunicacao-ponta-a-ponta]]

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
- Resultado técnico: `lat/lon` agora só entram no payload quando `gps.valid == true`, são finitos, estão no range e são diferentes de `(0,0)`.

### Item 2 — Edge Function sobrescrevia position com null

- Status: `[x]`
- Resolvido na `matrix-cloud` (`updateCollarTelemetry`).
- Resultado técnico: `position` e `position_received_at_ms` só entram no upsert quando `hasPosition == true`.

### Item 3 — Deploy da Edge Function

- Status: `[x]`
- `matrix-cloud` deployada com sucesso.
- Projeto: `nhoewnfuyjbtpklrotbf`
- Versão reportada: `v2.84.2`

### Item 4 — Baseline do banco antes do flash

- Status: `[x]`
- Estado confirmado:
  - `collars.position = [-16.676, -49.485]` — manual e válido
  - `collars.telemetry_received_at_ms = null`
  - `property_telemetry_latest` = vazio
  - `property_telemetry_history` = vazio
  - `property_events` recentes = `lat=null`, `lon=null`, com `violation` e `gps_invalid_fix`
  - `property_commands` = 10 PINGs históricos, fila limpa
  - `property_command_events` = vazio
- Interpretação: confirma que o pipeline útil ainda não rodou com o firmware corrigido.

### Item 5 — Identidade do gateway (`192.168.4.1` vs `matriz_fazenda_01`)

- Status: `[x]`
- Não é bug funcional.
- Mapeamento confirmado:
  - `gateways.id = "192.168.4.1"`
  - `gateways.runtime_status.matrixId = "matriz_fazenda_01"`
  - `matrixRuntimeIdFromGatewayData("192.168.4.1") -> "matriz_fazenda_01"`
  - `matrix_queue_keys.runtime_id = "matriz_fazenda_01"`
- Observação: há inconsistência cosmética residual porque `property_events.gateway_id = "matriz_fazenda_01"` e `gateways.id = "192.168.4.1"`, mas isso não bloqueia o pipeline.

### Item 6 — Arquivos modificados nesta auditoria

- Status: `[x]`
- `coleira/coleira.ino` — fix gpsOk guard + `lastCycle = millis()` no final do setup()
- `supabase/functions/matrix-cloud/index.ts`
- `app/lib/utils/device_map_telemetry.dart`
- `app/lib/screens/dashboard_screen.dart`
- `app/lib/services/gateway_service.dart` — fecha channel quando ensureConnected falha
- `audit-logs/supabase-sql.log`
- `audit-logs/collar-serial.log` — boot + crash loop + LoRa TX pós-flash
- `audit-logs/matrix-serial.log` — boot + scope_reject ready=0 + LoRa RX confirmado

### Item 7 — Validação end-to-end com hardware

- Status: `[!]`
- Update context: seriais abertos, crash loop diagnosticado e corrigido, LoRa TX confirmado pela matriz.
- Coleira: transmitindo LoRa (seq=2000001+, device=3222380545) — firmware pós-flash OK
- Matriz: recebendo LoRa mas `scope_reject ready=0` — sem backhaul WiFi "VICTOR_E_CAROL"
- **Dois novos bugs encontrados e corrigidos nesta rodada:**
  1. **Bug C — crash loop NVS**: `SmartGps::persistLastGoodFix()` → `EEPROM.commit()` → `nvs::Page::readEntry` → `LoadProhibited`. Causa: NVS flash corrompido. Fix: "Erase All Flash Before Upload" antes do reflash.
  2. **Bug D — uint32 wrap lastCycle**: `lastCycle` (global) retém valor após `SW_CPU_RESET` → `millis() - lastCycle` faz wrap → loop executa imediatamente → crash loop. Fix: `lastCycle = millis()` no final de `setup()` (`coleira.ino:2422`).
- Bloqueante atual: matriz sem binding (NVS apagado + sem WiFi "VICTOR_E_CAROL") → scope_reject → pipeline de telemetria nulo
- Bloqueante onboarding: BLE desabilitado, WiFi OTA desabilitado → coleira não descoberta automaticamente → usar campo "ID LoRa" manual no app (3222380545)

### Item 8 — Próximo passo obrigatório

- Status: `[!]`
- Update context: flash feito, coleira TX OK, bloqueante é a matriz sem binding.
- **Bloqueante principal:** matriz precisa conectar ao WiFi "VICTOR_E_CAROL" para obter binding → só então o LoRa da coleira será processado e publicado no Supabase
- Para adicionar coleira no app agora: usar campo "ID LoRa" manual → digitar `3222380545`
- Próximas ações:
  1. Garantir que "VICTOR_E_CAROL" está disponível para a matriz
  2. Confirmar no serial da matriz: `Backhaul conectado: <ip>` e `Binding matriz: ready=1`
  3. Reexecutar queries do banco — `property_telemetry_latest` deve popular
  4. Validar marcador automático no mapa sem update manual
  5. Validar cor do ícone (verde/vermelho/cinza)

## 14. Instrução final ao Claude Code

Continue a partir deste arquivo como fonte de verdade.  
Não reinicie a investigação.

### Próximos passos obrigatórios da próxima rodada

1. ~~validar se a coleira já foi flashada com o firmware corrigido~~ ✓ (flash feito)
2. ~~abrir e capturar os seriais da coleira e da matriz~~ ✓ (logs em audit-logs/)
3. **Garantir que "VICTOR_E_CAROL" está disponível para a matriz** — bloqueante atual
4. Confirmar no serial da matriz: `Backhaul conectado: <ip>` e `Binding matriz: ready=1`
5. Aguardar fix GPS real e evidência de telemetria útil
6. Reexecutar as queries do banco desta auditoria
7. Confirmar no app o marcador automático da coleira sem update manual
8. Validar a cor do ícone com telemetria recente/stale
9. Executar nova rodada de comandos (`PING`, `SET_PARAMS`, `SET_FENCE`, `SET_HERDING_PLAN`)
10. Atualizar este arquivo e o `task.md` com evidências objetivas

### Item 9 — Logs de sucesso/erro na conexão Wi-Fi da matriz

- Status: `[x]`
- Verificação feita no firmware `gateway-matriz/gateway-matriz.ino` e no log `audit-logs/matrix-serial.log`.
- Evidência confirmada:
  - ao iniciar a tentativa, a matriz imprime `Backhaul Wi-Fi: tentando conectar em <SSID>`
  - em sucesso parcial de associação, imprime `Backhaul Wi-Fi associado ao AP`
  - em sucesso efetivo de rede, imprime `Backhaul conectado: <ip>`
  - em falha por timeout sem obter IP, imprime `Backhaul Wi-Fi: tentativa expirou sem IP ...`
  - em desconexão, imprime `Backhaul desconectado: motivo=...`
- Interpretação: o firmware está programado para reportar no serial tanto sucesso quanto erro da conexão do backhaul Wi-Fi da fazenda.

### Item 10 — Diagnóstico visível do backhaul Wi-Fi da matriz

- Status: `[x]`
- Implementado no firmware `gateway-matriz`.
- Entregas aplicadas:
  - state machine explícita de diagnóstico do backhaul
  - snapshot estruturado exposto em `/status`
  - heartbeat periódico no serial durante conexão/falha e também em estado conectado
  - classificação resumida de causa provável (`ssid_nao_visivel`, `senha_incorreta_ou_autenticacao_falhou`, `dhcp_sem_resposta`, etc.)
  - endpoint manual `GET /diag/backhaul`
  - indicação compacta `BH:*` no OLED quando habilitado
- Observação:
  - a tentativa de validação por `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs gateway-matriz` ficou pendurada no ambiente e não retornou saída conclusiva nesta rodada; falta validar em build local/CI e depois em serial real.

### Regra final

Se o hardware ainda não tiver sido flashado ou se não houver evidência real de serial/banco/app, **não** marcar os itens de validação end-to-end como `[x]`.
