#line 1 "/Users/victor/Downloads/code/ruraltech/coleira/README.md"
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
