# Gateway Matriz Firmware (ESP32 DevKit V1)

## Objetivo
Atuar como nó central da propriedade rural, iniciando por padrão em
Wi-Fi + BLE + LoRa (com opção de LoRa-only) para:

1. Configuração local via app (HTTP/WS).
2. Comunicação LoRa com coleiras e gateways comuns.
3. Relay gateway<->gateway para levar dados até a matriz.

## Bibliotecas Arduino IDE
- RadioLib 6.6+
- ArduinoJson 7+
- WebSocketsServer (Links2004) 2.4+
- Adafruit SSD1306 2.5+
- Adafruit GFX 1.11+
- RTClib 2.1+
- SD (core)

## Placa
- ESP32 Dev Module
- Partition Scheme: `Minimal SPIFFS (1.9MB APP with OTA/128KB SPIFFS)` (`min_spiffs`)

## Pinos default (`config.h`)
- LoRa CS=5 RST=14 DIO0=27 DIO1=33
- SD CS=13
- OLED/DS3231 I2C SDA=21 SCL=22

## Rede App <-> Gateway Matriz
- AP local: `RuralTech-Matriz` / `ruraltechota`
- HTTP: porta 80 (`/status`, `/devices`, `/logs`)
- WebSocket: porta 81 (json bidirecional)

## Limites LoRa e fragmentação
- Payload máximo LoRa por frame: `128 bytes`.
- Fragmentação automática de `SET_FENCE` e `SET_HERDING_PLAN`.
- Limites de firmware para coleira:
  - Geofence: até `32` pontos.
  - Condução: até `8` fases e até `32` pontos por fase.

## Logs
- Arquivo diário no SD: `YYYY-MM-DD.log`
- Formato: `millis|hash_chain|conteúdo`

## Build
1. Abra `gateway-matriz/gateway-matriz.ino` no Arduino IDE.
2. Configure placa ESP32 Dev Module.
3. Configure `Partition Scheme` para `Minimal SPIFFS (1.9MB APP with OTA/128KB SPIFFS)`.
4. Instale bibliotecas.
5. Compile/upload.

## Atualização de firmware via Wi-Fi (OTA)
- O gateway matriz inicia com OTA/Wi-Fi ativo por padrão (`wifi_ota_enabled=true`).
- Conecte no AP: `RuralTech-Matriz` / `ruraltechota`.
- No Arduino IDE, selecione a porta de rede `ruraltech-matriz`.
- Use senha OTA: `ruraltechota`.
- `GET /status` retorna `service=gateway_matrix` e o estado atual de `wifi_ota_enabled`.

## Regra de operação
- `wifi_ota_enabled=true` (padrão) mantém Wi-Fi/BLE/LoRa ativos.
- `wifi_ota_enabled=false` coloca em LoRa-only (Wi-Fi e BLE desligados).
- A transição para LoRa-only requer comando `SET_PARAMS` marcado como administrativo (`requested_by_role=adm` ou `requested_by_admin=true`).
- `SET_PARAMS` continua podendo ser encaminhado via LoRa para coleiras/gateways alvo.

## Relay Gateway <-> Gateway
- Relay LoRa multi-hop best-effort para `TELEMETRY`, `EVENT`, `ACK`, `NACK`.
- Permite que dados cheguem até a matriz mesmo sem enlace direto.
