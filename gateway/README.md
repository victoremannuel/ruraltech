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

## Pinos default (`config.h`)
- LoRa CS=5 RST=14 DIO0=27 DIO1=33
- SD CS=13
- OLED/DS3231 I2C SDA=21 SCL=22

## Rede App <-> Gateway
- AP local: `RuralTech-Gateway` / `ruraltech123`
- HTTP: porta 80 (`/status`, `/devices`, `/logs`)
- WebSocket: porta 81 (json bidirecional)

## Logs
- Arquivo diário no SD: `YYYY-MM-DD.log`
- Formato: `millis|hash_chain|conteúdo`

## Build
1. Abra `gateway/gateway.ino` no Arduino IDE.
2. Configure placa ESP32 Dev Module.
3. Instale bibliotecas.
4. Compile/upload.

## Atualização de firmware via Wi-Fi (OTA)
- OTA já vem habilitado no firmware (`config.h`).
- Conecte seu PC no AP do gateway: `RuralTech-Gateway` / `ruraltechota`.
- No Arduino IDE, selecione a porta de rede do dispositivo `ruraltech-gateway`.
- Faça upload normalmente; quando solicitado, use a senha OTA: `ruraltechota`.
- Endpoint útil: `GET /status` mostra `ota=true` e IP do AP.
