# RuralTech - Notas para FlutterFlow

## Telas MVP
1. LoginScreen (email/senha via Supabase Auth)
2. DashboardScreen (lista devices)
3. DeviceDetailsScreen
4. GeofenceScreen (entrada manual lat/lon)
5. HerdingScreen (gera fases simples)
6. EventsScreen (stream websocket)

## Estruturas cloud
- `/users/{uid}`: perfil básico
- `/devices/{deviceId}`: estado atual, posição, metadata
- `/fences/{deviceId}`: `points: [[lat,lon], ...]`
- `/herdingPlans/{deviceId}`: `phases: [[[lat,lon], ...], ...]`
- `/events/{eventId}`: eventos críticos e auditoria

## Actions/Requests Gateway
- WS `send_command` com payload:
```json
{"type":"send_command","device_id":3239702529,"command":"SET_FENCE","payload":{"points":[[-23.0,-46.0],[-23.1,-46.1]]}}
```
- Comandos suportados: `SET_FENCE`, `SET_HERDING_PLAN`, `SET_PARAMS`, `PING`
- Stream recebido: `telemetry`, `event`, `command_result`, `hello`

## Recriação no FlutterFlow
- Definir App State: `gatewayHost`, `messages[]`
- Criar API Call WebSocket custom action
- Bind em ListView para mensagens e tabelas cloud
