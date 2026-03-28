# diag-lora-lora

Firmware de diagnostico isolado para ESP32 da coleira com o modulo LoRa.

Objetivo:
- Usar a mesma pinagem LoRa do projeto `coleira`.
- Sincronizar duas ESP32 em modo `ping-pong`, com uma transmitindo enquanto a outra escuta.
- Alternar automaticamente o sentido do teste a cada `500 ms`.
- Imprimir `envio feito com sucesso` logo apos cada envio bem-sucedido.
- Ficar em escuta entre os envios e imprimir `recebido - {texto}` quando capturar um payload textual compativel.

## Pinagem usada

- `ESP32 D5` -> `LoRa NSS/CS`
- `ESP32 D18` -> `LoRa SCK`
- `ESP32 D19` -> `LoRa MISO`
- `ESP32 D23` -> `LoRa MOSI`
- `ESP32 D14` -> `LoRa RST`
- `ESP32 D27` -> `LoRa DIO0`
- `ESP32 D33` -> `LoRa DIO1`

## Parametros LoRa

- Frequencia: `915.0 MHz`
- Bandwidth: `125 kHz`
- Spreading Factor: `9`
- Coding Rate: `7`
- Sync Word: `0x12`

## Formato do payload enviado

O sketch envia mensagens no formato:

```txt
diag-lora-lora|NODE_ID|SEQ|AAAA-MM-DD HH:MM:SS
```

## Sincronizacao do teste

- Ao iniciar, cada ESP32 entra em janelas curtas de escuta e aguarda um `backoff` derivado do proprio MAC antes de tentar assumir o primeiro envio.
- A placa que ouvir primeiro entra no papel de respondente e agenda a resposta para o proximo slot de `500 ms`.
- A placa que nao ouvir nada dentro do proprio `backoff` envia e passa a aguardar a resposta da outra.
- Quando um pacote chega, a outra agenda a resposta para o proximo slot de `500 ms`.
- Se uma resposta nao chega no prazo, o firmware volta sozinho para a fase de aquisicao e tenta recuperar a sincronizacao.

## Timestamp

- Ao iniciar, o sketch semeia o relogio com a data/hora de compilacao.
- Se quiser ajustar a hora real manualmente pelo monitor serial, envie:

```txt
TIME=AAAA-MM-DD HH:MM:SS
```

## Dependencia

```bash
arduino-cli lib install "RadioLib@6.6.0"
```

## Build

```bash
arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs diag-lora-lora
```

## Upload

```bash
arduino-cli upload -p /dev/cu.usbserial-XXXXX \
  --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs \
  --upload-property upload.speed=115200 \
  diag-lora-lora
```

## Monitor

```bash
arduino-cli monitor -p /dev/cu.usbserial-XXXXX -c baudrate=115200,dtr=off,rts=off
```
