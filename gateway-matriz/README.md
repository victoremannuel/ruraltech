# Gateway Matriz Firmware (ESP32 DevKit V1)

## Objetivo
Atuar como nó central da propriedade rural, iniciando por padrão em
Wi-Fi + LoRa (e BLE quando habilitado no build) para:

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

## Pinagem de referencia (montagem)
### LoRa RFM95 (SPI)
- ESP32 D5 -> LoRa NSS/CS
- ESP32 D18 -> LoRa SCK
- ESP32 D19 -> LoRa MISO
- ESP32 D23 -> LoRa MOSI
- ESP32 D14 -> LoRa RST
- ESP32 D27 -> LoRa DIO0
- ESP32 D33 -> LoRa DIO1
- ESP32 3v -> LoRa VCC
- ESP32 Gnd -> LoRa GND

### MicroSD (SPI)
- ESP32 D13 -> SD CS
- ESP32 D18 -> SD SCK
- ESP32 D19 -> SD MISO
- ESP32 D23 -> SD MOSI
- ESP32 3v -> SD VCC
- ESP32 Gnd -> SD GND

### I2C compartilhado (OLED + DS3231)
- ESP32 D21 -> SDA de OLED e DS3231
- ESP32 D22 -> SCL de OLED e DS3231
- ESP32 3v -> VCC de OLED e DS3231
- ESP32 Gnd -> GND de OLED e DS3231

### Alimentacao geral
- 3v para logica/sensores/LoRa
- 5v apenas para modulos que realmente pedem 5V
- Gnd comum em tudo (ESP32, LoRa, SD e I2C)

### Reservados / nao usar para esses componentes
- Tx0 e Rx0: deixar para USB/Serial Monitor
- EN: nao usar como IO
- VP, VN, D34, D35: somente entrada

Consulte tambem `gateway-matriz/pinagem.md` para a lista detalhada.

## Rede App <-> Gateway Matriz
- AP local: `RuralTech-Matriz-<ID6HEX>` / `ruraltechota`
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
- Observação: em `min_spiffs`, `RT_MATRIX_BLE_ENABLED` é `0` por padrão para caber em flash.
  Para forçar BLE, defina `RT_MATRIX_BLE_ENABLED=1` em build e valide espaço.

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
arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs gateway-matriz
```
5. Grave via USB (troque `<PORTA_USB>` pelo valor da etapa anterior):
```bash
arduino-cli upload -p <PORTA_USB> --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs gateway-matriz
```
6. Valide logs no serial monitor (115200):
```bash
arduino-cli monitor -p <PORTA_USB> -c baudrate=115200
```
7. Se travar em `Connecting...`, segure `BOOT`, inicie o upload e solte quando a gravacao comecar.
8. Confirme no output de compilacao que o uso de flash fica abaixo de 100%.  
   Em `gateway-matriz`, mantenha atencao extra ao tamanho quando for forcar `RT_MATRIX_BLE_ENABLED=1`.

## Segredos de producao
- Nao commite credenciais no repositório.
- Copie o template local:
```bash
cp gateway-matriz/manual_settings.local.example.h gateway-matriz/manual_settings.local.h
```
- Preencha no arquivo local:
  - `RT_CFG_BACKHAUL_WIFI_SSID`
  - `RT_CFG_BACKHAUL_WIFI_PASS`
  - `RT_CFG_RTDB_MATRIX_ID`
  - `RT_CFG_RTDB_WRITER_KEY`

## Atualização de firmware via Wi-Fi (OTA)
- O gateway matriz inicia com OTA/Wi-Fi ativo por padrão (`wifi_ota_enabled=true`).
- Conecte no AP: `RuralTech-Matriz-<ID6HEX>` / `ruraltechota`.
- No Arduino IDE, selecione a porta de rede `ruraltech-matriz`.
- Use senha OTA: `ruraltechota`.
- `GET /status` retorna `service=gateway_matrix` e o estado atual de `wifi_ota_enabled`.

## Regra de operação
- `wifi_ota_enabled=true` (padrão) mantém Wi-Fi + LoRa (e BLE quando compilado).
- `wifi_ota_enabled=false` coloca em LoRa-only (Wi-Fi desligado e BLE, se presente, também desligado).
- A transição para LoRa-only requer comando `SET_PARAMS` marcado como administrativo (`requested_by_role=adm` ou `requested_by_admin=true`).
- `SET_PARAMS` continua podendo ser encaminhado via LoRa para coleiras/gateways alvo.

## Relay Gateway <-> Gateway
- Relay LoRa multi-hop best-effort para `TELEMETRY`, `EVENT`, `ACK`, `NACK`.
- Permite que dados cheguem até a matriz mesmo sem enlace direto.
