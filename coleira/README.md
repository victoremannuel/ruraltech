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
3. Instale bibliotecas listadas.
4. Compile e faça upload.
5. Serial Monitor em 115200.

## Protocolo LoRa
- Estrutura: `device_id, msg_type, seq, timestamp, nonce(12), payload_len, payload, auth_tag(16)`.
- Criptografia: AES-CTR + HMAC-SHA256 truncado (16 bytes).
- Anti-replay: `seq` monotônico validado no receptor.
