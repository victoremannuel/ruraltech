# Auditoria: Pipeline Telemetria / Comandos RuralTech v2.3.0

**Data:** 2026-04-12
**Branch:** audit/remove-firebase-complete

---

## 1. Resumo Executivo

Auditoria completa do pipeline GPS → coleira → matriz → Supabase → app.
Foram identificados dois bugs críticos que impediam a persistência de posição útil, mais uma feature de cor de ícone implementada.

---

## 2. Causa Raiz

### Bug #1 — Coleira: lat/lon enviados mesmo sem fix GPS

**Arquivo:** `coleira/coleira.ino` — `buildTelemetryPayload` (linha ~1749)

**Problema:** A função sempre incluía `lat = t.gps.lat` e `lon = t.gps.lon` no payload, mesmo quando `t.gps.valid = false`.

**Struct:** `GpsData` inicializa `lat = 0` e `lon = 0` por padrão (ver `coleira/Types.h:74-75`).

**Impacto:** O gateway-matriz recebia `lat=0.0, lon=0.0` e validava range (passava, pois 0 é finito e dentro dos limites). Resultado: `property_telemetry_latest` era preenchido com coordenadas `(0°N, 0°E)` — oceano Atlântico próximo à África — ao invés de dados úteis, ou dados sem posição eram publicados.

**Correção:** Em `buildTelemetryPayload`, lat/lon só são incluídos quando `t.gps.valid == true` AND coordenadas são finitas, dentro do range, e != (0,0).

---

### Bug #2 — Edge Function: sobrescreve position com null

**Arquivo:** `supabase/functions/matrix-cloud/index.ts` — `updateCollarTelemetry` (linha ~90)

**Problema:** O upsert em `collars` sempre definia `position` (podendo ser `null`) e sempre definia `position_received_at_ms`, mesmo quando não havia lat/lon válidos.

**Impacto:** Chamadas de telemetria sem GPS apagavam a última posição boa do banco.

**Correção:** `position` e `position_received_at_ms` só são incluídos no upsert quando `hasPosition == true`.

---

## 3. Evidências por Etapa

### Fase A — Coleira

- GPS: `GpsData` inicializa `lat=0, lon=0, valid=false` (Types.h:72-75)
- `buildTelemetryPayload`: incluía lat/lon sem verificar `gps.valid` ← **BUG CORRIGIDO**
- `gps_invalid_fix` emitido quando sem fix → eventos sem posição esperados

### Fase B — Matriz

- `gateway-matriz.ino` linha ~1118: valida `isfinite(lat) && range`, MAS não rejeita (0,0)
- Com bug #1 corrigido: quando GPS inválido, lat/lon ausentes → gateway retorna sem publicar telemetria → comportamento correto
- `publishCloudLatestAndHistory` chamado apenas com lat/lon válidos

### Fase C — Supabase (Edge Function)

- `handlePropertyTelemetryLatest`: extrai `lat/lon` apenas se `typeof === "number"` ✓
- `updateCollarTelemetry`: **BUG** upsert com position=null sobrescrevia dados ← **CORRIGIDO**
- `handlePropertyEvents`: persiste lat/lon quando presentes no body ✓

### Fase D — App

- `DeviceModel.fromMap`: lê `position` como Array `[lat, lon]` para Supabase ✓
- `deviceMapTelemetrySampleFromDevice`: só cria sample quando lat/lon válidos ✓
- `resolvePreferredMapTelemetryForDevice`: prefere dado mais recente entre persisted/local ✓
- Dashboard: ícone de coleira agora usa cor dinâmica baseada em frescor ✓

---

## 4. Mudanças Realizadas

### `coleira/coleira.ino`

```cpp
// ANTES (linha 1749-1750):
doc["lat"] = t.gps.lat;
doc["lon"] = t.gps.lon;

// DEPOIS:
const bool gpsOk = t.gps.valid && isfinite(t.gps.lat) && isfinite(t.gps.lon) &&
                   t.gps.lat >= -90.0 && t.gps.lat <= 90.0 &&
                   t.gps.lon >= -180.0 && t.gps.lon <= 180.0 &&
                   (t.gps.lat != 0.0 || t.gps.lon != 0.0);
if (gpsOk) {
  doc["lat"] = t.gps.lat;
  doc["lon"] = t.gps.lon;
}
```

### `supabase/functions/matrix-cloud/index.ts`

```typescript
// ANTES: upsert sempre com position e position_received_at_ms
// DEPOIS: só inclui position e position_received_at_ms quando hasPosition == true
const hasPosition = lat != null && lon != null;
const upsertPayload: JsonMap = {
  id: collarId, device_id: collarId, property_id: propertyId,
  telemetry_received_at_ms: receivedAtMs,
};
if (hasPosition) {
  upsertPayload.position = [lat, lon];
  upsertPayload.position_received_at_ms = receivedAtMs;
}
```

### `app/lib/utils/device_map_telemetry.dart`

Adicionado:
- `enum TelemetryFreshness { unknown, fresh, stale }`
- Constante `_telemetryFreshThreshold = Duration(hours: 24)`
- Função `resolveTelemetryFreshness(DeviceModel)`: retorna freshness baseado em `positionReceivedAtMs` / `telemetryReceivedAtMs`

### `app/lib/screens/dashboard_screen.dart`

Ícone da coleira mudado de `color: Colors.red` (fixo) para cor dinâmica:
- `TelemetryFreshness.fresh` → `Colors.green`
- `TelemetryFreshness.stale` → `Colors.red`
- `TelemetryFreshness.unknown` → `Colors.grey`

---

## 5. Pendências

### Itens que requerem hardware físico conectado

- [ ] Validação end-to-end com serial aberto (coleira + matriz)
- [ ] Confirmar que collar envia telemetria sem lat/lon quando sem GPS fix
- [ ] Confirmar que `property_telemetry_latest` fica vazio quando sem GPS fix (correto após fix)
- [ ] Confirmar que `collars.position` não é sobrescrito com null após fix
- [ ] Testar GPS válido: confirmar persistência correta em todas as tabelas
- [ ] Testar pipeline de comandos: PING, SET_PARAMS, SET_FENCE, SET_HERDING_PLAN
- [ ] Validar cor verde com telemetria recente no mapa

### Identidade de gateway

- Divergência potencial entre `192.168.4.1` e `matriz_fazenda_01` não foi normalizada nesta rodada
- Requer análise ao conectar hardware

---

## 6. Queries de Validação

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
SELECT property_id, event_id, device_id, event_type, lat, lon,
       position_received_at_ms, received_at_ms
FROM property_events WHERE device_id = '3222380545'
ORDER BY received_at_ms DESC LIMIT 50;
```

---

## 7. Próximos Passos

1. Fazer deploy da Edge Function `matrix-cloud` atualizada
2. Flash da coleira com firmware corrigido
3. Conectar seriais e capturar logs em `audit-logs/`
4. Rodar queries de validação e salvar em `audit-logs/supabase-sql.log`
5. Validar marcador automático no mapa sem update manual
6. Auditar pipeline de comandos end-to-end
