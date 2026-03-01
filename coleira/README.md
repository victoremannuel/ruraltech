# Coleira Firmware (ESP32 DevKit V1)

## Objetivo
Firmware da coleira com telemetria, cerca virtual autônoma, condução por fases e segurança animal local.

## Bibliotecas Arduino IDE (versões sugeridas)
- RadioLib 6.6+
- TinyGPSPlus 1.0+
- ArduinoJson 7+
- Adafruit MLX90614 Library 2.1+
- MPU6050_tockn 1.5+
- ESP32 Core 3.x (mbedTLS nativo)

## Placa
- **ESP32 Dev Module** (ESP32 DevKit V1)
- **Partition Scheme:** `Minimal SPIFFS (1.9MB APP with OTA/128KB SPIFFS)` (`min_spiffs`)

## Pinos default (`config.h`)
- GPS UART: RX=16 TX=17
- LoRa RFM95: CS=5 RST=14 DIO0=27 DIO1=33
- I2C: SDA=21 SCL=22
- Buzzer: GPIO25
- Pulso/TIP120: GPIO26

## Pinagem de referência (montagem)
### GPS (UART)
- ESP32 D16 -> GPS TX
- ESP32 D17 -> GPS RX
- ESP32 3v -> GPS VCC (ou 5v se seu módulo exigir)
- ESP32 Gnd -> GPS GND

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

### Sensores I2C (MLX90614 + MPU6050 no mesmo barramento)
- ESP32 D21 -> SDA de ambos os sensores
- ESP32 D22 -> SCL de ambos os sensores
- ESP32 3v -> VCC de ambos os sensores
- ESP32 Gnd -> GND de ambos os sensores

### Buzzer
- Buzzer 2 pinos (padrao):
  - ESP32 D25 -> Buzzer +
  - ESP32 Gnd -> Buzzer -
- Se for modulo de 3 pinos (S/VCC/GND):
  - ESP32 D25 -> Sinal do buzzer
  - ESP32 Gnd -> GND buzzer
  - ESP32 3v/5v -> VCC buzzer (conforme modelo; se ativo 5V, usar transistor se necessario)

### Pulso (TIP120 / estágio de potência)
- ESP32 D26 -> Base/Gate do driver (via resistor)
- ESP32 Gnd -> GND do driver (terra comum obrigatório)
- Fonte do atuador -> Carga de pulso (conforme seu circuito de potência)

### Alimentação geral
- 3v para lógica/sensores/LoRa
- 5v apenas para módulos que realmente pedem 5V
- Gnd comum em tudo (ESP32, GPS, LoRa, sensores, driver de pulso)

### Reservados / não usar para esses componentes
- Tx0 e Rx0: deixar para USB/Serial Monitor
- EN: não usar como IO
- VP, W(VN), D34, D35: somente entrada (não servem para buzzer/pulso/CS)

Consulte tambem `coleira/pinagem.md` para observacoes de EEPROM externa I2C e detalhes de barramento.

## Segurança animal implementada
- Escalonamento obrigatório: beep nível 1 -> beep nível 2 -> pulso.
- Limite de pulsos por janela, mínimo entre pulsos.
- Sem pulso com GPS inválido/instável (HDOP/satélites).

## Build e teste
1. Abra `coleira/coleira.ino` no Arduino IDE.
2. Selecione placa ESP32 Dev Module.
3. Configure o `Partition Scheme` como `Minimal SPIFFS (1.9MB APP with OTA/128KB SPIFFS)`.
4. Instale bibliotecas listadas.
5. Compile e faça upload.
6. Serial Monitor em 115200.

## Upload via USB no VS Code (terminal integrado)
1. Conecte a ESP32 por USB e abra a pasta `ruraltech` no VS Code.
2. No terminal integrado, execute a preparacao inicial (uma vez por maquina):
```bash
arduino-cli config init --overwrite
arduino-cli core update-index --additional-urls https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
arduino-cli core install esp32:esp32 --additional-urls https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
arduino-cli lib install "ArduinoJson@7.4.2" "RadioLib@6.6.0" "TinyGPSPlus@1.0.3" "Adafruit MLX90614 Library@2.1.5" "MPU6050_tockn@1.5.2"
```
3. Descubra a porta USB da placa:
```bash
arduino-cli board list
```
4. Compile com a mesma particao exigida pelo firmware (`min_spiffs`):
```bash
arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs coleira
```
5. Grave via USB (troque `<PORTA_USB>` pelo valor da etapa anterior, ex: `/dev/cu.usbserial-1410`):
```bash
arduino-cli upload -p <PORTA_USB> --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs coleira
```
6. Valide logs no serial monitor (115200):
```bash
arduino-cli monitor -p <PORTA_USB> -c baudrate=115200
```
7. Se travar em `Connecting...`, segure `BOOT`, inicie o upload e solte quando a gravacao comecar.
8. Confirme no output de compilacao que o uso de flash fica abaixo de 100% (limite fisico da ESP32).

## Atualização de firmware via Wi-Fi (OTA)
- OTA já vem habilitado no firmware (`config.h`).
- A coleira mantém OTA/Wi-Fi ativo continuamente por padrão.
- Ela tenta conectar no Wi-Fi:
  - SSID: `RuralTech-Gateway`
  - Senha: `ruraltechota`
- Se nao conectar no Wi-Fi acima, ela cria AP fallback:
  - SSID: `RuralTech-Coleira-OTA-<ID6HEX>`
  - Senha: `ruraltechota`
- Para testes de bancada, voce pode forcar AP direto ajustando
  `OTA_FORCE_AP_ONLY=true` em `config.h`.
- No Arduino IDE selecione a porta de rede `ruraltech-coleira` e faça upload.
- Senha OTA: `ruraltechota`.

## Chave remota Wi-Fi/OTA via LoRa
- A coleira aceita `SET_PARAMS` com payload JSON:
  - `{"wifi_ota_enabled": true}` ativa Wi-Fi/OTA e watchdog.
  - `{"wifi_ota_enabled": false,"requested_by_role":"adm"}` desativa
    Wi-Fi/OTA e watchdog (modo LoRa-only).
- `wifi_ota_enabled=false` só é aceito quando marcado como administrativo
  (`requested_by_role=adm` ou `requested_by_admin=true`).
- O estado de `wifi_ota_enabled` fica persistido em NVS e sobrevive a reboot.
- Regra de descoberta BLE:
  - BLE onboarding fica ativo apenas quando `wifi_ota_enabled=true`.
  - ao desativar Wi-Fi/OTA (`wifi_ota_enabled=false`), BLE também desliga.

## Comandos LoRa aplicados localmente
- `SET_FENCE` com `{"points":[[lat,lon], ...]}` (3..32 pontos).
- `SET_HERDING_PLAN` com `{"phases":[[[lat,lon], ...], ...]}` (1..8 fases).
- `SET_PARAMS` com `{"wifi_ota_enabled": true|false}`.
- A coleira responde com `ACK`/`NACK` (inclui `cmd`, `cmd_seq` e `reason` em falha).
- `SET_FENCE` e `SET_HERDING_PLAN` também aceitam formato fragmentado (`chunked`)
  enviado automaticamente pelo gateway quando o payload excede 128 bytes.

## Persistência local (NVS)
- Cerca (`SET_FENCE`) é salva e restaurada no boot.
- Plano de condução (`SET_HERDING_PLAN`) é salvo e restaurado no boot.
- Progresso de fase da condução também é salvo a cada troca/finalização.

## Protocolo LoRa
- Estrutura: `device_id, msg_type, seq, timestamp, nonce(12), payload_len, payload, auth_tag(16)`.
- Criptografia: AES-CTR + HMAC-SHA256 truncado (16 bytes).
- Anti-replay: `seq` monotônico validado no receptor.
