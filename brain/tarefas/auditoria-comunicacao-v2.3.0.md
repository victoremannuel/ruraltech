# Task: Auditoria e Implantação do Pipeline RuralTech v2.3.0

#ruraltech
#tarefas

## Convenção de execução obrigatória

Use esta legenda em **todos** os itens do checklist e subtarefas:

- `[ ]` = não realizado
- `[!]` = realizado com ressalva ou pendência
- `[x]` = resolvido com sucesso

### Regra obrigatória para `[!]`

Sempre que marcar um item como `[!]`, registrar imediatamente a justificativa em **Notas e Pendências**, contendo:

1. o problema encontrado
2. impacto técnico/funcional
3. evidência objetiva
4. ação sugerida
5. se bloqueia ou não a continuação

### Regra de economia de tokens

**Não fazer varredura ampla do repositório.**
Ler apenas os arquivos e diretórios listados neste plano, nesta ordem.
Só expandir escopo se houver evidência concreta de que o problema está fora desse conjunto.

---

# 1) Checklist executivo

## 1.1 Preparação

- [x] Confirmar acesso ao monorepo correto
- [x] Confirmar que os dispositivos seriais estão visíveis na máquina
- [x] Confirmar portas:
  - coleira = `usbserial-1420`
  - matriz = `usbserial-59470049741`
- [x] Criar pasta local de evidências/logs da auditoria
- [x] Criar/atualizar arquivo `AUDIT_TELEMETRY_COMMAND_PIPELINE.md`

## 1.2 Contexto já validado e que NÃO deve ser redescoberto

- [x] Assumir como verdade que o papel `adm` no app já está funcionando
- [x] Assumir como verdade que o mapa da Home já foi corrigido após ajuste dos polígonos persistidos
- [x] Assumir como verdade que os ícones de coleira e gateway reaparecem quando `position` é preenchido manualmente
- [x] Assumir como verdade que o gargalo atual está no pipeline GPS/telemetria/persistência
- [x] Assumir como verdade que havia eventos persistidos sem `lat/lon`
- [x] Assumir como verdade que há ocorrência de `gps_invalid_fix`
- [x] Assumir como verdade que a UI do mapa está funcional

## 1.3 Auditoria do pipeline GPS / telemetria / eventos

- [x] Auditar geração de GPS na coleira
- [x] Auditar montagem do payload uplink da coleira
- [x] Auditar recepção LoRa na matriz
- [x] Auditar parse do uplink na matriz
- [x] Auditar persistência em `property_telemetry_latest`
- [x] Auditar persistência em `property_telemetry_history`
- [x] Auditar persistência em `property_events`
- [x] Auditar atualização automática de `collars.position`
- [x] Auditar atualização de `collars.telemetry_received_at_ms`
- [x] Auditar atualização de `collars.position_received_at_ms`
- [!] Auditar consistência de identidade de gateway (`matrixId`, `matrixGatewayId`, `gateway_id`, `gateways.id`) — pendente hardware

## 1.4 Auditoria do pipeline de comandos

- [!] Auditar criação de comandos no app — pendente hardware
- [!] Auditar persistência em `property_commands` — pendente hardware
- [!] Auditar consumo dos comandos pela matriz — pendente hardware
- [!] Auditar transmissão LoRa dos comandos — pendente hardware
- [!] Auditar recepção e aplicação na coleira — pendente hardware
- [!] Auditar ACK/NACK da coleira — pendente hardware
- [!] Auditar persistência em `property_command_events` — pendente hardware
- [!] Auditar reflexo no app — pendente hardware

## 1.5 Implementação dos ajustes

- [x] Corrigir perda de `lat/lon` no pipeline
- [x] Garantir atualização automática de `collars.position`
- [x] Garantir persistência útil em `property_telemetry_latest`
- [x] Garantir persistência útil em `property_telemetry_history`
- [x] Garantir que eventos com posição projetem `lat/lon` nas colunas achatadas
- [x] Garantir que eventos sem posição não apaguem a última posição boa
- [!] Normalizar identidade de gateway no pipeline — pendente hardware
- [x] Implementar a feature de cor do ícone da coleira por frescor da telemetria

## 1.6 Testes e validação final

- [ ] Validar telemetria com GPS válido
- [ ] Validar telemetria com GPS inválido
- [ ] Validar eventos com posição
- [ ] Validar comandos `PING`
- [ ] Validar comandos `SET_PARAMS`
- [ ] Validar comandos `SET_FENCE`
- [ ] Validar comandos `SET_HERDING_PLAN`
- [ ] Validar marcador da coleira no mapa sem update manual
- [ ] Validar cor verde com telemetria recente
- [ ] Validar cor vermelha com telemetria stale
- [ ] Rodar testes automatizados mínimos
- [ ] Registrar conclusão no relatório de auditoria

---

# 2) Contexto consolidado para não gastar tokens

## 2.1 Estado já auditado

Tomar como fatos já confirmados:

1. O app reconhece `adm` corretamente.
2. O problema anterior de mapa cinza foi causado por dados geográficos malformados em:
   - `rural_properties.points`
   - `areas.perimeter`
     Esses dados já foram corrigidos.
3. O mapa e os polígonos agora aparecem normalmente.
4. Os marcadores de coleira e gateway reaparecem quando:
   - `collars.position` recebe coordenadas válidas
   - `gateways.position` recebe coordenadas válidas
5. Logo, a UI da Home e o mapa não são mais a causa raiz.
6. O gargalo atual é no pipeline:
   - GPS da coleira
   - telemetria/eventos
   - persistência no Supabase
7. Foi observado que:
   - `property_telemetry_latest` estava vazio/sem linha útil para a coleira
   - `property_events` continha eventos da coleira sem `lat/lon`
   - havia ocorrência de `gps_invalid_fix`
8. A coleira em teste está vinculada a:
   - `device_id = 3222380545`
   - `property_id = T0xeG8WQHwJRI6H3t7vr`
   - `gateway_id = 192.168.4.1`
9. Há potencial divergência de identidade do gateway entre:
   - `192.168.4.1`
   - `matriz_fazenda_01`

## 2.2 Não repetir estas investigações

Não reabrir investigação sobre:

- role/policies/RLS como causa principal do problema atual
- mapa cinza anterior
- correção dos polígonos
- sumiço dos marcadores quando `position` está manualmente preenchido

---

# 3) Escopo mínimo de arquivos a ler

## 3.1 App Flutter — prioridade alta

Ler primeiro e somente estes arquivos:

- `app/lib/screens/dashboard_screen.dart`
- `app/lib/services/cloud_service.dart`
- `app/lib/models/device_model.dart`
- `app/lib/utils/device_map_telemetry.dart`
- `app/lib/services/gateway_service.dart`

## 3.2 App Flutter — prioridade média

Só abrir se necessário:

- `app/lib/screens/events_screen.dart`
- `app/lib/screens/device_details_screen.dart`
- `app/lib/screens/herding_screen.dart`
- `app/lib/screens/profile_screen.dart`

## 3.3 Firmware / hardware

Ler primeiro:

- `coleira/`
- `gateway-matriz/`
- `firmware/shared/`
- `contracts/messages/`

Só abrir `gateway/` se o código de uplink/comando estiver compartilhado ou reutilizado ali.

## 3.4 Banco / persistência

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

# 4) Estratégia operacional de baixo consumo de tokens

## 4.1 Ordem de abordagem

1. Ler os arquivos mínimos do app
2. Ler os módulos mínimos da coleira
3. Ler os módulos mínimos da matriz
4. Auditar queries e persistência
5. Só então editar

## 4.2 Palavras-chave para busca localizada

Usar apenas buscas por:

- `property_telemetry_latest`
- `property_telemetry_history`
- `property_events`
- `property_command_events`
- `queue-lora-command`
- `gps_invalid_fix`
- `violation`
- `receivedAtMs`
- `position_received_at_ms`
- `lat`
- `lon`
- `writerKey`
- `matrixGatewayId`
- `gateway_id`
- `SET_FENCE`
- `SET_HERDING_PLAN`
- `SET_PARAMS`
- `PING`
- `ACK`
- `NACK`

## 4.3 Regra de parada

Ao identificar de forma inequívoca onde `lat/lon` se perdem, parar a exploração e partir para:

1. correção
2. teste
3. evidência

---

# 5) Preparação do ambiente local

## 5.1 Confirmar seriais

Executar:

```bash
ls -la /dev/cu.* | grep -E 'usbserial|usbmodem'
```

Validar:

- coleira = `/dev/cu.usbserial-1420`
- matriz = `/dev/cu.usbserial-59470049741`

## 5.2 Criar diretório de auditoria

Executar:

```bash
mkdir -p audit-logs
```

Arquivos esperados:

- `audit-logs/collar-serial.log`
- `audit-logs/matrix-serial.log`
- `audit-logs/supabase-sql.log`
- `audit-logs/ws-gateway.log`
- `audit-logs/app-observed.log`

## 5.3 Abrir monitores seriais

Executar com uma opção disponível na máquina:

### Opção A — Python

```bash
python -m serial.tools.miniterm /dev/cu.usbserial-1420 115200 --raw
python -m serial.tools.miniterm /dev/cu.usbserial-59470049741 115200 --raw
```

### Opção B — screen

```bash
screen /dev/cu.usbserial-1420 115200
screen /dev/cu.usbserial-59470049741 115200
```

Se necessário, testar:

- `9600`
- `57600`
- `115200`

## 5.4 Regra importante

Na primeira rodada:

- **não alterar firmware**
- primeiro observar e registrar evidência

---

# 6) Contrato esperado de cada etapa do pipeline

## 6.1 Coleira -> matriz

Cada uplink de telemetria/evento deve idealmente conter:

- `deviceId`
- `seq`
- `receivedAt` ou `sourceTimestampSec`
- `eventType` / `type`
- `lat`
- `lon`
- metadados de GPS:
  - `sat`
  - `hdop`
  - `gpsFixValid` ou flags equivalentes

- `gatewayId` / `matrixGatewayId` / `propertyScopeId` quando aplicável

## 6.2 Matriz -> Supabase

Quando houver posição válida, a matriz deve:

1. fazer upsert em `property_telemetry_latest`
2. inserir em `property_telemetry_history`
3. atualizar `collars.position`
4. atualizar `collars.telemetry_received_at_ms`
5. atualizar `collars.position_received_at_ms`
6. persistir `property_events` com `lat/lon` preenchidos quando o evento carregar posição

## 6.3 Supabase -> app

O app deve conseguir resolver posição da coleira por qualquer destes caminhos:

1. `collars.position`
2. `property_telemetry_latest`
3. `property_events` com `lat/lon`
4. amostra local via gateway/WebSocket

## 6.4 App -> Supabase -> matriz -> coleira

Fluxo esperado:

1. app cria comando
2. Supabase persiste em `property_commands`
3. matriz consome comando
4. matriz transmite por LoRa
5. coleira aplica
6. coleira responde ACK/NACK
7. matriz persiste em `property_command_events`
8. app reflete o status

---

# 7) Auditoria do pipeline GPS / telemetria / eventos

## Fase A — Coleira: origem do dado GPS

### Objetivo

Descobrir se a coleira:

1. nunca obtém fix
2. obtém fix e perde `lat/lon` antes do uplink
3. obtém fix e envia `lat/lon` corretamente

### Ações

- localizar no firmware da coleira:
  - inicialização do GPS
  - leitura do GPS
  - montagem do payload uplink
  - transmissão LoRa

- procurar logs/prints por:
  - `gps`
  - `fix`
  - `lat`
  - `lon`
  - `hdop`
  - `sat`
  - `nmea`
  - `invalid_fix`
  - `telemetry`
  - `uplink`

### Evidências obrigatórias

Responder com prova objetiva:

- o GPS inicializa?
- há NMEA?
- há fix válido?
- quando há fix, `lat/lon` entram na estrutura do payload?
- quando não há fix, o firmware emite `gps_invalid_fix`?
- `violation` pode ser emitido mesmo sem coordenadas?

### Se os logs atuais forem insuficientes

Adicionar logs temporários atrás de macro de debug:

```c
#define DEBUG_GPS_AUDIT 1
```

Formato sugerido:

```txt
[GPS] fix=1 lat=-16.67 lon=-49.48 sat=8 hdop=120
[UPLINK] type=telemetry seq=1234 include_pos=1 lat=-16.67 lon=-49.48
[LORA_TX] kind=telemetry bytes=87 ok=1
```

### Critério de sucesso da Fase A

Marcar `[x]` apenas se ficar inequívoco em qual ponto do firmware da coleira o dado GPS existe ou se perde.

---

## Fase B — Matriz: recepção, parse e persistência

### Objetivo

Descobrir se a matriz:

1. recebe `lat/lon`
2. parseia corretamente
3. persiste corretamente
4. descarta ou não projeta os campos

### Ações

Localizar no firmware da matriz:

- recepção do uplink LoRa
- parser do payload
- integração com Supabase
- persistência de:
  - `property_telemetry_latest`
  - `property_telemetry_history`
  - `property_events`
  - `collars.position`

- tratamento de `gps_invalid_fix`
- tratamento de `violation`

### Perguntas que precisam ser respondidas

1. O pacote da coleira chega à matriz?
2. Ele chega com `lat/lon`?
3. O parser extrai `lat/lon` corretamente?
4. A matriz persiste só o payload bruto?
5. A matriz preenche as colunas achatadas `lat/lon`?
6. A matriz atualiza `property_telemetry_latest`?
7. A matriz atualiza `collars.position`?
8. Há divergência de identidade entre:
   - `matrixId`
   - `matrixGatewayId`
   - `gateway_id`
   - `gateways.id`

### Logs temporários sugeridos

```txt
[LORA_RX] device=3222380545 seq=1234 bytes=91
[PARSE] type=violation lat=-16.67 lon=-49.48 fix=1
[DB] upsert property_telemetry_latest ok=1 property=T0xe...
[DB] insert property_events ok=1 lat=-16.67 lon=-49.48
[DB] update collars.position ok=1
```

### Regra de persistência obrigatória

Quando houver `lat/lon` válidos:

1. atualizar `property_telemetry_latest`
2. inserir em `property_telemetry_history`
3. atualizar `collars.position`
4. atualizar `collars.telemetry_received_at_ms`
5. atualizar `collars.position_received_at_ms`
6. se houver evento, persistir `property_events.lat/lon`

### Regra para evento sem posição

Quando houver evento sem posição:

1. persistir o evento
2. **não apagar** a última posição boa
3. **não sobrescrever** `position_received_at_ms` com `null`

### Critério de sucesso da Fase B

Marcar `[x]` apenas quando ficar provado exatamente onde `lat/lon` se perdem:

- antes do parser
- no parser
- na persistência
- na projeção para tabelas

---

## Fase C — Supabase: validar persistência real

### Queries de auditoria

Executar e salvar evidência:

#### Última telemetria

```sql
select *
from public.property_telemetry_latest
where device_id = '3222380545';
```

#### Histórico de telemetria

```sql
select *
from public.property_telemetry_history
where device_id = '3222380545'
order by received_at_ms desc
limit 20;
```

#### Eventos

```sql
select property_id, day_key, event_id, device_id, gateway_id, event_type, lat, lon, position_received_at_ms, received_at_ms, payload, created_at
from public.property_events
where device_id = '3222380545'
order by received_at_ms desc
limit 50;
```

#### Estado da coleira

```sql
select id, device_id, property_id, gateway_id, position, telemetry_received_at_ms, position_received_at_ms
from public.collars
where id = '3222380545';
```

#### Estado do gateway matriz

```sql
select id, gateway_id, property_id, position, is_matrix, binding_ready, supports_scoped_lora
from public.gateways
where id = '192.168.4.1';
```

### Resultado esperado após uplink com GPS válido

Deve haver:

- linha útil em `property_telemetry_latest`
- histórico em `property_telemetry_history`
- `property_events.lat/lon` preenchidos quando aplicável
- `collars.position` atualizado
- timestamps de telemetria/posição preenchidos

### Critério de sucesso da Fase C

Marcar `[x]` apenas se o banco refletir corretamente o que a matriz recebeu.

---

## Fase D — App: consumo da telemetria persistida

### Objetivo

Garantir que o app use corretamente a telemetria persistida para desenhar a coleira.

### Auditar

- `app/lib/services/cloud_service.dart`
- `app/lib/models/device_model.dart`
- `app/lib/utils/device_map_telemetry.dart`
- `app/lib/screens/dashboard_screen.dart`

### O que validar

1. `CloudService._deviceMapFromRow` lê:
   - `position`
   - `telemetryReceivedAtMs`
   - `positionReceivedAtMs`

2. `DeviceModel.fromMap` converte `position` corretamente
3. `deviceMapTelemetrySampleFromDevice()` aceita coordenadas válidas
4. `resolvePreferredMapTelemetryForDevice()` escolhe corretamente entre persisted/local
5. `dashboard_screen.dart` cria o marker da coleira sempre que houver posição resolvida

### Critério de sucesso da Fase D

Marcar `[x]` quando a coleira aparecer no mapa **sem update manual**, usando dados vindos do pipeline persistido.

---

# 8) Auditoria do pipeline de comandos

## Fase E — App -> Supabase

### Comandos obrigatórios de teste

- `PING`
- `SET_PARAMS`
- `SET_FENCE`
- `SET_HERDING_PLAN`

### O que validar

No app:

- criação correta do comando
- payload correto
- `requested_by_role`
- `requested_by_uid`
- `property_id`
- `matrix_gateway_id`
- `target_device_ids`

### Queries

```sql
select *
from public.property_commands
order by created_at_ms desc
limit 20;
```

```sql
select *
from public.property_command_events
order by received_at_ms desc
limit 50;
```

### Critério de sucesso

Marcar `[x]` quando cada comando de teste gerar registro válido em `property_commands`.

---

## Fase F — Matriz -> coleira

### O que auditar

Na matriz:

- polling/consume de `property_commands`
- filtros por `property_id`, `property_scope_id`, `matrix_gateway_id`
- transmissão LoRa do comando
- persistência do resultado

### Logs sugeridos

```txt
[CMD_POLL] found command=PING id=...
[CMD_MATCH] matrix=192.168.4.1 property=T0xe... ok=1
[LORA_TX_CMD] device=3222380545 cmd=PING bytes=...
[LORA_ACK] device=3222380545 cmd=PING ok=1
[DB] insert property_command_events ok=1
```

### Critério de sucesso

Marcar `[x]` quando houver evidência de:

1. consumo do comando
2. transmissão LoRa
3. retorno ACK/NACK
4. persistência do resultado

---

## Fase G — Coleira: aplicação do comando

### O que auditar

Na coleira:

- recepção LoRa do comando
- validação do contrato
- aplicação do comando
- retorno ACK/NACK

### Logs sugeridos

```txt
[CMD_RX] cmd=PING seq=...
[CMD_VALIDATE] ok=1
[CMD_APPLY] cmd=PING ok=1
[ACK_TX] cmd=PING ok=1
```

### Critério de sucesso

Marcar `[x]` quando a coleira provar:

- recebeu
- validou
- aplicou
- respondeu

---

# 9) Implementação da feature de cor do ícone da coleira

## Regra funcional

### Verde

A coleira deve ficar **verde** quando existir telemetria persistida utilizável com menos de 24 horas, vinda de qualquer uma destas fontes:

1. `property_telemetry_latest.received_at_ms`
2. `property_events` com `lat/lon` válidos
3. `collars.position_received_at_ms`
4. `collars.telemetry_received_at_ms`

### Vermelho

A coleira deve ficar **vermelha** quando a última telemetria persistida utilizável tiver mais de 24 horas.

### Cinza (recomendado)

Opcionalmente usar **cinza** quando nunca houve telemetria persistida utilizável.

## Implementação recomendada

Arquivos-alvo:

- `app/lib/models/device_model.dart`
- `app/lib/utils/device_map_telemetry.dart`
- `app/lib/services/cloud_service.dart`
- `app/lib/screens/dashboard_screen.dart`

## Estratégia

1. Expor no `DeviceModel` ou helper um conceito de frescor:
   - `TelemetryFreshness.unknown`
   - `TelemetryFreshness.fresh`
   - `TelemetryFreshness.stale`

2. Calcular `lastUsefulTelemetryMs` como o maior timestamp utilizável entre:
   - `positionReceivedAtMs`
   - `telemetryReceivedAtMs`
   - `property_telemetry_latest.received_at_ms`
   - último `property_event` com `lat/lon`

3. Usar limiar:

```dart
const telemetryFreshThreshold = Duration(hours: 24);
```

4. Trocar a cor fixa do ícone da coleira por cor dinâmica:
   - verde = `fresh`
   - vermelho = `stale`
   - cinza = `unknown`

## Critérios de aceite

- coleira com telemetria < 24h = verde
- coleira com telemetria > 24h = vermelho
- coleira sem telemetria = cinza ou conforme decisão final de UX
- testes cobrindo as 3 condições

---

# 10) Normalização de identidade de gateway

## Problema a auditar

Há indício de identidade divergente entre:

- `192.168.4.1`
- `matriz_fazenda_01`

## Regra alvo

Definir um identificador canônico persistido e usá-lo consistentemente em:

- `gateways.id`
- `gateway_id` dos eventos
- correlação de telemetria
- correlação de comandos
- correlação de ACK/NACK

## Ação mínima aceitável

Se a unificação total não for possível nesta rodada:

1. documentar claramente o mapeamento
2. criar helper de normalização
3. aplicar o helper nos pontos críticos do fluxo

---

# 11) Sequência obrigatória de execução

## Etapa 1 — observação pura

- [!] abrir serial da coleira — seriais detectados, flash pendente
- [!] abrir serial da matriz — seriais detectados, flash pendente
- [!] capturar logs sem alterar firmware — causa raiz identificada via análise de código
- [!] registrar queries iniciais do banco — pendente hardware

## Etapa 2 — localizar a perda de `lat/lon`

- [x] provar se a coleira gera `lat/lon` — BUG encontrado: coleira enviava lat=0,lon=0 quando GPS inválido
- [x] provar se a matriz recebe `lat/lon` — matriz valida range mas não rejeita (0,0) — coberto pelo fix da coleira
- [x] provar se a matriz persiste `lat/lon` — edge function corrigida para não sobrescrever posição boa

## Etapa 3 — corrigir a persistência

- [x] corrigir atualização de `property_telemetry_latest` — lat/lon só incluídos com GPS válido
- [x] corrigir atualização de `property_telemetry_history` — idem (mesmo path)
- [x] corrigir atualização de `collars.position` — updateCollarTelemetry não sobrescreve com null
- [x] corrigir projeção de `lat/lon` em `property_events` — edge function já projeta quando presentes

## Etapa 4 — validar pipeline end-to-end de telemetria

- [ ] gerar telemetria real
- [ ] confirmar gravação no banco
- [ ] confirmar marcador automático no app

## Etapa 5 — auditar comandos

- [ ] testar `PING`
- [ ] testar `SET_PARAMS`
- [ ] testar `SET_FENCE`
- [ ] testar `SET_HERDING_PLAN`

## Etapa 6 — implementar cor dinâmica do ícone

- [x] implementar cálculo de frescor — `resolveTelemetryFreshness()` em device_map_telemetry.dart
- [x] alterar cor do ícone — verde/vermelho/cinza no dashboard
- [ ] cobrir com teste

## Etapa 7 — regressão final

- [ ] validar Home
- [ ] validar Events
- [ ] validar comandos
- [ ] validar coleira sem update manual
- [ ] validar verde/vermelho da coleira
- [ ] registrar conclusão

---

# 12) Artefatos obrigatórios de saída

## 12.1 Relatório

Atualizar ou criar:

- `AUDIT_TELEMETRY_COMMAND_PIPELINE.md`

Conteúdo mínimo:

1. resumo executivo
2. causa raiz encontrada
3. evidências por etapa
4. mudanças realizadas
5. pendências
6. próximos passos

## 12.2 Logs

Salvar evidências em:

- `audit-logs/collar-serial.log`
- `audit-logs/matrix-serial.log`
- `audit-logs/supabase-sql.log`
- `audit-logs/app-observed.log`

## 12.3 Código

Entregar patch mínimo, sem mudanças desnecessárias.

## 12.4 Testes

Atualizar ou criar os testes mínimos necessários.

---

# 13) Critério de pronto

Marcar a tarefa como concluída somente se todas estas condições forem verdadeiras:

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
- [ ] todas as ressalvas foram registradas em Notas e Pendências

---

## Related

[[ruraltech]]
[[visao-geral]]
[[fluxo-comandos]]
[[fluxos-comunicacao-ponta-a-ponta]]
[[modelagem-dados-supabase]]
[[migracao-supabase]]
[[auditoria-comunicacao-v2.3.1]]
[[auditoria-comunicacao-v2.3.2]]
[[AUDIT_TELEMETRY_COMMAND_PIPELINE]]

---

# 14) Notas e Pendências

---

### Item 1 — Coleira envia lat=0,lon=0 quando GPS inválido

- Referência: `coleira/coleira.ino:1749-1750` → `buildTelemetryPayload`
- Status: `[!]` → **CORRIGIDO**

**Problema encontrado:**
`buildTelemetryPayload` incluía `doc["lat"] = t.gps.lat` e `doc["lon"] = t.gps.lon` sem verificar `t.gps.valid`. Quando sem fix, `GpsData` defaults para `lat=0, lon=0`.

**Evidência:**
`coleira/Types.h:74-75`: `double lat = 0;` / `double lon = 0;`
`gateway-matriz.ino:1118-1121`: validação só rejeita não-finito ou fora de range. (0,0) passa.

**Impacto:**
`property_telemetry_latest` gravado com coordenadas (0°N, 0°E). Coleira não aparecia no mapa da fazenda (marcador fora da área).

**Correção aplicada:**
Adicionado guard em `buildTelemetryPayload`: lat/lon só incluídos quando `t.gps.valid && isfinite && range && != (0,0)`.

**Bloqueia continuação?** Não — corrigido.

**Próximo passo:** Flash na coleira, validar que telemetria sem GPS não publica mais posição.

---

### Item 2 — Edge Function sobrescreve collars.position com null

- Referência: `supabase/functions/matrix-cloud/index.ts` → `updateCollarTelemetry:90-98`
- Status: `[!]` → **CORRIGIDO**

**Problema encontrado:**
O upsert em `collars` sempre incluía `position: null` e `position_received_at_ms: receivedAtMs` mesmo quando sem lat/lon.

**Evidência:**
```typescript
const position = lat != null && lon != null ? [lat, lon] : null;
const update = await admin.from("collars").upsert({
  ..., position, position_received_at_ms: receivedAtMs  // null sobrescreve!
});
```

**Impacto:**
Quando uma coleira enviava telemetria sem GPS (após correção do bug #1, isso seria impossível pelo fluxo normal, mas possível por chamadas diretas), a última boa posição seria apagada.

**Correção aplicada:**
`position` e `position_received_at_ms` só adicionados ao upsert quando `hasPosition == true`.

**Bloqueia continuação?** Não — corrigido.

---

### Item 3 — Validação end-to-end pendente (requer hardware)

- Referência: Etapas 4, 5, 7 do checklist
- Status: `[!]`

**Problema encontrado:**
As etapas de validação com GPS real, comandos, e regressão final requerem a coleira e a matriz conectadas e operando. Não foi possível validar via análise estática de código.

**Evidência:**
Seriais detectados (`/dev/cu.usbserial-1420` e `/dev/cu.usbserial-59470049741`), mas flash do firmware corrigido ainda não realizado.

**Impacto:**
Não confirma empiricamente a correção. Pode haver issues adicionais não identificados via código.

**Correção aplicada ou sugerida:**
Conectar, fazer flash, abrir seriais, executar queries SQL de auditoria.

**Bloqueia continuação?** Sim — para marcar a tarefa como concluída.

**Próximo passo recomendado:**
1. Deploy da Edge Function: `supabase functions deploy matrix-cloud`
2. Flash da coleira com firmware corrigido via Arduino IDE
3. Monitorar seriais conforme seção 5.3 do plano
4. Executar queries da seção 7 (Fase C) e salvar em `audit-logs/supabase-sql.log`

---

### Item 4 — Identidade de gateway não normalizada

- Referência: `192.168.4.1` vs `matriz_fazenda_01`
- Status: `[!]`

**Problema encontrado:**
Potencial divergência de identidade entre `gateway_id = 192.168.4.1` (IP) e `matrixGatewayId` (nome). Não foi possível confirmar o mapeamento sem dados reais do banco.

**Impacto:**
Pode causar falha na correlação de comandos se a matriz procura por `matrixGatewayId` e o banco tem `gateway_id = 192.168.4.1`.

**Bloqueia continuação?** Não bloqueia esta rodada. Pode bloquear pipeline de comandos.

**Próximo passo:** Executar query no banco e verificar `gateways.id` e `gateways.gateway_id` para a matriz em uso.
