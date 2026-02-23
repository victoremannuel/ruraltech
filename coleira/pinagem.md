**GPS (UART)**

1. `ESP32 D16` -> `GPS TX`
2. `ESP32 D17` -> `GPS RX`
3. `ESP32 3v` -> `GPS VCC` (ou `5v` se seu módulo exigir)
4. `ESP32 Gnd` -> `GPS GND`

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

**Sensor acelerometro/giroscopio I2C (ZX-MPU6050)**

1. `ESP32 D21` -> `MPU6050 SDA`
2. `ESP32 D22` -> `MPU6050 SCL`
3. `ESP32 3v` -> `MPU6050 VCC`
4. `ESP32 Gnd` -> `MPU6050 GND`

**Sensor de temperatura GY-906 (MLX90614, I2C - modulo 4 pinos VIN/GND/SCL/SDA)**

1. `ESP32 D21` -> `GY-906 SDA`
2. `ESP32 D22` -> `GY-906 SCL`
3. `ESP32 3v` -> `GY-906 VIN` (recomendado para manter nivel logico I2C em 3.3V)
4. `ESP32 Gnd` -> `GY-906 GND`
5. Se seu modulo tiver somente esses 4 pinos, a ligacao acima ja e suficiente.

**Endereco I2C e barramento compartilhado**

1. `GY-906/MLX90614` normalmente usa endereco `0x5A`.
2. `MPU6050` normalmente usa `0x68`.
3. Pode compartilhar o mesmo barramento I2C (`D21/D22`) sem conflito de endereco.

**Buzzer**

**Buzzer 2 pinos (passivo/ativo simples)**

1. `ESP32 D25` -> `Buzzer +` (via transistor/driver quando necessario)
2. `ESP32 Gnd` -> `Buzzer -`

**Se o buzzer for modulo de 3 pinos (S/VCC/GND), use**

1. `ESP32 D25` -> `Sinal`
2. `ESP32 3v/5v` -> `VCC` (conforme modelo)
3. `ESP32 Gnd` -> `GND`

**Pulso (TIP120 / estágio de potência)**

1. `ESP32 D26` -> `Base/Gate do driver` (via resistor)
2. `ESP32 Gnd` -> `GND do driver` (terra comum obrigatório)
3. `Fonte do atuador` -> `Carga de pulso` (conforme seu circuito de potência)

**Alimentação geral**

1. `3v` para lógica/sensores/LoRa
2. `5v` apenas para módulos que realmente pedem 5V
3. `Gnd` comum em tudo (ESP32, GPS, LoRa, sensores, driver de pulso)

**Reservados / não usar para esses componentes**

1. `Tx0` e `Rx0`: deixar para USB/Serial Monitor
2. `EN`: não usar como IO
3. `VP`, `W(VN)`, `D34`, `D35`: somente entrada (não servem para buzzer/pulso/CS)

**Pinos disponíveis na ESP32**

1. D23;
2. D22;
3. Tx0;
4. Rx0;
5. D21;
6. D19;
7. D18;
8. D5;
9. D17;
10. D16;
11. D4;
12. D2;
13. D15;
14. D22;
15. D21;
16. Vcc;
17. Gnd;
18. 5v;
19. 3v;
20. En;
21. Vp;
22. W;
23. D34;
24. D35;
25. D32;
26. D33;
27. D25;
28. D26;
29. D27;
30. D14;
31. D12;
32. D13;

**Armazenamento persistente (estado atual do firmware)**

1. Nao e necessario ligar EEPROM externa na placa para o firmware atual.
2. A fila offline (`StorageQueue`) usa `EEPROM.h` emulada na flash interna da ESP32.
3. Configuracoes operacionais (ex.: `wifi_ota_enabled`, cerca e plano) usam `Preferences` (NVS), tambem na flash interna.

**EEPROM externa I2C (opcional para expansao futura)**

Exemplo de CI: `AT24C256` (ou modulo equivalente, 3.3V).

1. `ESP32 D21` -> `EEPROM SDA`
2. `ESP32 D22` -> `EEPROM SCL`
3. `ESP32 3v` -> `EEPROM VCC`
4. `ESP32 Gnd` -> `EEPROM GND`
5. `EEPROM A0` -> `GND` (endereco 0x50)
6. `EEPROM A1` -> `GND`
7. `EEPROM A2` -> `GND`
8. `EEPROM WP` -> `GND` (habilita escrita)
9. Pull-up de `SDA/SCL` para 3.3V (tipicamente 4.7k), caso o modulo nao tenha.

**Importante sobre A0/A1/A2/WP**

1. `A0/A1/A2/WP` NAO sao pinos da ESP32.
2. Esses pinos pertencem ao CI EEPROM (AT24Cxx) ou aos pads/jumpers do modulo da EEPROM.
3. Se seu modulo expor apenas `VCC/GND/SDA/SCL`, esses sinais normalmente ja estao fixos na placa do modulo.
4. Nessa situacao, basta ligar os 4 fios (`VCC/GND/SDA/SCL`) e usar o endereco I2C padrao do modulo (geralmente `0x50`; alguns modulos podem vir em outro endereco).
5. Se o modulo tiver pad de `WP` em nivel alto por padrao, a escrita pode ficar bloqueada; ajuste o jumper/solda para permitir escrita.

**Importante**

1. O firmware atual da coleira NAO esta configurado para ler/escrever uma EEPROM I2C externa (AT24Cxx).
2. Para usar EEPROM externa de fato, sera necessario alterar o firmware para usar `Wire` + driver da EEPROM externa (ou biblioteca especifica).
