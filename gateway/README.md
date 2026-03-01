# Gateway Firmware (ESP32 DevKit V1)

## Objetivo
Receber LoRa da coleira, expor REST+WebSocket para o app, logar em microSD com hash chain e exibir status em OLED.

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

## Rede App <-> Gateway
- AP local: `RuralTech-Gateway-<ID6HEX>` / `ruraltechota`
- HTTP: porta 80 (`/status`, `/devices`, `/logs`)
- WebSocket: porta 81 (json bidirecional)

## Limites LoRa e fragmentação
- Payload máximo LoRa por frame: `128 bytes`.
- O gateway fragmenta automaticamente `SET_FENCE` e `SET_HERDING_PLAN`
  em múltiplos frames quando necessário.
- Limites de firmware para a coleira:
  - Geofence: até `32` pontos.
  - Condução: até `8` fases e até `32` pontos por fase.

## Logs
- Arquivo diário no SD: `YYYY-MM-DD.log`
- Formato: `millis|hash_chain|conteúdo`

## Build
1. Abra `gateway/gateway.ino` no Arduino IDE.
2. Configure placa ESP32 Dev Module.
3. Configure `Partition Scheme` para `Minimal SPIFFS (1.9MB APP with OTA/128KB SPIFFS)`.
4. Instale bibliotecas.
5. Compile/upload.

## Upload via USB no VS Code (terminal integrado)
1. Conecte a ESP32 por USB e abra a pasta `ruraltech` no VS Code.
2. No terminal integrado, execute a preparacao inicial (uma vez por maquina):
```bash
arduino-cli config init --overwrite
arduino-cli core update-index --additional-urls https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
arduino-cli core install esp32:esp32 --additional-urls https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
arduino-cli lib install "ArduinoJson@7.4.2" "RadioLib@6.6.0" "WebSockets@2.7.2" "RTClib@2.1.4" "Adafruit SSD1306@2.5.15" "Adafruit GFX Library@1.12.1"
```
3. Descubra a porta USB da placa:
```bash
arduino-cli board list
```
4. Compile com `min_spiffs`:
```bash
arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs gateway
```
5. Grave via USB (troque `<PORTA_USB>` pelo valor da etapa anterior):
```bash
arduino-cli upload -p <PORTA_USB> --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs gateway
```
6. Valide logs no serial monitor (115200):
```bash
arduino-cli monitor -p <PORTA_USB> -c baudrate=115200
```
7. Se travar em `Connecting...`, segure `BOOT`, inicie o upload e solte quando a gravacao comecar.
8. Confirme no output de compilacao que o uso de flash fica abaixo de 100% (limite fisico da ESP32).

## Atualização de firmware via Wi-Fi (OTA)
- OTA/Wi-Fi já vem habilitado continuamente por padrão (`config.h`).
- Conecte seu PC no AP do gateway: `RuralTech-Gateway-<ID6HEX>` / `ruraltechota`.
- No Arduino IDE, selecione a porta de rede do dispositivo `ruraltech-gateway`.
- Faça upload normalmente; quando solicitado, use a senha OTA: `ruraltechota`.
- Endpoint útil: `GET /status` mostra `ota=true` e IP do AP.

## Chave remota Wi-Fi/OTA
- Via WebSocket/API ou LoRa, envie `SET_PARAMS` com payload:
  - `{"target":"all","wifi_ota_enabled":false,"requested_by_role":"adm"}` -> gateway e coleiras em LoRa-only.
  - `{"target":"all","wifi_ota_enabled":true}` -> reativa Wi-Fi/OTA e watchdog.
- Targets aceitos: `all`, `gateway`, `collars`/`collar`.
- `wifi_ota_enabled=false` só é aceito quando marcado como administrativo
  (`requested_by_role=adm` ou `requested_by_admin=true`).
- Regra de descoberta BLE:
  - gateway comum e gateway matriz: BLE onboarding fica ativo somente quando
    `wifi_ota_enabled=true`.
  - com `wifi_ota_enabled=false`, BLE também é desligado.

## Relay Gateway <-> Gateway
- Gateways fazem relay LoRa multi-hop best-effort para `TELEMETRY`, `EVENT`,
  `ACK` e `NACK`, permitindo que dados de coleiras cheguem ao gateway com
  computador/internet mesmo sem enlace direto.
