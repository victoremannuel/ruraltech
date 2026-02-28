# Message Contract Fixtures

Fixtures de contrato entre `app`, `gateway`, `gateway-matriz` e `coleira`.

- `hello.json`: handshake websocket ao conectar.
- `telemetry.json`: uplink de telemetria publicado pelo gateway.
- `event.json`: evento critico publicado pelo gateway.
- `ack.json`: ACK LoRa recebido da coleira.
- `nack.json`: NACK LoRa recebido da coleira.
- `command_result_ok.json`: resposta de envio de comando com sucesso.
- `command_result_error.json`: resposta de envio de comando com falha.

Esses arquivos sao usados como baseline de regressao no CI.
