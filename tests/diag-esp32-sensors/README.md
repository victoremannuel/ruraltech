# diag-esp32-sensors

Firmware de diagnostico isolado para ESP32 da coleira.

Objetivo:
- Varrer barramento I2C e testar MLX90614 (`0x5A..0x5D`).
- Varrer combinacoes de pinos/baud do GPS e detectar NMEA (`$`).
- Exibir monitor GPS em tempo real no serial.

## Build

```bash
arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs diag-esp32-sensors
```

## Upload

```bash
arduino-cli upload -p /dev/cu.usbserial-59470049741 \
  --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs \
  --upload-property upload.speed=115200 \
  diag-esp32-sensors
```

## Monitor

```bash
arduino-cli monitor -p /dev/cu.usbserial-59470049741 -c baudrate=115200
```
