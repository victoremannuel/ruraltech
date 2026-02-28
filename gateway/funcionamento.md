# Funcionamento do Gateway (`gateway-1.0.0`)

## 1) Objetivo
O gateway é a ponte entre:

1. Rede LoRa (coleiras e outros gateways).
2. App local (WebSocket/HTTP via Wi-Fi).
3. Persistência local em microSD (log).

Também é o nó que pode concentrar dados para posterior envio ao backend (ex.: Firebase) por um sistema externo.

## 2) Arquitetura de módulos

1. `gateway.ino`: fluxo principal (boot, OTA, LoRa, API, relay, comandos).
2. `LoRaGateway.*`: rádio LoRa seguro com anti-replay por dispositivo.
3. `ApiServer.*`: servidor HTTP + WebSocket para o app.
4. `SdLogger.*`: log local em SD com hash chain.
5. `LoRaProtocol.*` + `CryptoEngine.*`: serialização segura dos frames LoRa.

## 3) Inicialização

1. Sobe watchdog.
2. Inicializa display OLED e RTC.
3. Sobe Wi-Fi AP (`RuralTech-Gateway-<ID6HEX>`) quando `wifi_ota_enabled=true`.
4. Sobe OTA (`ArduinoOTA`) no host `ruraltech-gateway`.
5. Inicializa API HTTP/WS, SD e LoRa.

## 4) Interfaces expostas para o app

### HTTP

1. `GET /status`: status do gateway (fw, ssid, ip, ota).
2. `GET /devices`: lista JSON dos dispositivos rastreados em memoria (ordenados por atividade recente), com `device_id`, `online`, `age_ms`, `seq`, `timestamp` e `lat/lon` quando disponivel. Aceita `?limit=<n>`.
3. `GET /logs`: ultimas linhas do buffer de logs em memoria (`text/plain`). Aceita `?limit=<n>` (padrao 30).

### WebSocket (`ws://<gateway-ip>:81`)

1. Entrada de comando do app:
   - `{"type":"send_command","device_id":<id>,"command":"SET_FENCE|SET_HERDING_PLAN|SET_PARAMS|PING","payload":{...}}`
2. Saída para app:
   - telemetria/eventos recebidos do LoRa
   - `command_result` para resultado de envio
   - `hello` ao conectar.

Fila de comandos WebSocket no firmware: 8 mensagens.

## 5) Fluxo uplink LoRa -> app

1. Recebe frame LoRa.
2. Valida e decripta.
3. Aplica anti-replay por `deviceId + seq`.
4. Se for candidato a relay (`TELEMETRY`, `EVENT`, `ACK`, `NACK`), retransmite para outros gateways.
5. Publica JSON no WebSocket para o app.
6. Registra em SD (`UL|...`).

## 6) Fluxo downlink app -> LoRa

1. Recebe `send_command` no WebSocket.
2. Interpreta `command` e payload.
3. `SET_FENCE` e `SET_HERDING_PLAN`:
   - valida dados de ponto
   - fragmenta em múltiplos frames (`chunked`) se necessário
4. `SET_PARAMS`:
   - pode aplicar localmente no próprio gateway (`target: gateway|all`)
   - pode encaminhar para coleiras (`target: collar|collars|all`)
   - `wifi_ota_enabled=false` exige marcação administrativa
     (`requested_by_role=adm` ou `requested_by_admin=true`)
5. Emite `command_result` no WebSocket e log SD (`DL|...`).

## 7) Fragmentação LoRa e limites

1. Payload JSON por frame LoRa: até `128` bytes.
2. Limite de geofence/plano no firmware:
   - até `32` pontos por polígono
   - até `8` fases por plano de condução
3. O gateway fragmenta automaticamente os comandos grandes.

## 8) Relay gateway <-> gateway

1. Habilitado por `GATEWAY_RELAY_ENABLED=true`.
2. Repassa frames `TELEMETRY`, `EVENT`, `ACK`, `NACK`.
3. Permite malha LoRa best-effort para levar dados até um gateway com acesso a computador/internet.
4. Anti-replay acompanha até `32` device IDs distintos (`LORA_REPLAY_TRACKED_DEVICES`).

## 9) Segurança e integridade

1. LoRa com AES-CTR + HMAC-SHA256 truncado.
2. Anti-replay por sequência.
3. Log em SD com hash encadeado por linha (`hash chain`), útil para auditoria lógica de integridade.

## 10) OTA e modos de operação

1. OTA ativa quando Wi-Fi/OTA habilitado.
2. `SET_PARAMS` com `wifi_ota_enabled=false` coloca gateway em modo LoRa-only
   (Wi-Fi desligado), somente quando o comando é administrativo.
3. `SET_PARAMS` com `wifi_ota_enabled=true` reativa AP + OTA + API local.
4. BLE de descoberta do app acompanha o mesmo estado:
   - `wifi_ota_enabled=true` -> BLE ativo.
   - `wifi_ota_enabled=false` -> BLE desligado.

## 11) Papel na integração com backend

O firmware atual entrega a camada local (LoRa + Wi-Fi local + log).  
O envio de dados para Firebase pode ser feito por:

1. App conectado ao WebSocket do gateway.
2. Serviço externo no computador conectado ao gateway.
3. Futuro módulo online no próprio gateway.

## 12) Observação de build

Para o firmware atual com BLE + OTA no ESP32 Dev Module, use
`PartitionScheme=min_spiffs` (1.9MB APP com OTA).
