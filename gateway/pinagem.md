**Gateway comum (ESP32 DevKit V1) - pinagem de componentes**

**LoRa RFM95 (SPI)**

1. `ESP32 D5` -> `LoRa NSS/CS`
2. `ESP32 D18` -> `LoRa SCK`
3. `ESP32 D19` -> `LoRa MISO`
4. `ESP32 D23` -> `LoRa MOSI`
5. `ESP32 D14` -> `LoRa RST`
6. `ESP32 D27` -> `LoRa DIO0`
7. `ESP32 D33` -> `LoRa DIO1`
8. `ESP32 3v` -> `LoRa VCC`
9. `ESP32 Gnd` -> `LoRa GND`

**MicroSD (SPI)**

1. `ESP32 D13` -> `SD CS`
2. `ESP32 D18` -> `SD SCK`
3. `ESP32 D19` -> `SD MISO`
4. `ESP32 D23` -> `SD MOSI`
5. `ESP32 3v` -> `SD VCC` (conforme modulo)
6. `ESP32 Gnd` -> `SD GND`

**I2C compartilhado (OLED + RTC DS3231)**

1. `ESP32 D21` -> `SDA` de OLED e DS3231
2. `ESP32 D22` -> `SCL` de OLED e DS3231
3. `ESP32 3v` -> `VCC` de OLED e DS3231
4. `ESP32 Gnd` -> `GND` de OLED e DS3231

**Enderecos I2C usuais**

1. OLED SSD1306: `0x3C`
2. RTC DS3231: `0x68`

**Alimentacao geral**

1. `3v` para logica (ESP32, LoRa, I2C)
2. `5v` somente em modulos que exigirem (com cuidado de nivel logico)
3. `Gnd` comum em todos os modulos

**Reservados / evitar nesses componentes**

1. `Tx0` e `Rx0`: manter para USB/Serial Monitor
2. `EN`: nao usar como GPIO
3. `VP`, `VN`, `D34`, `D35`: apenas entrada
