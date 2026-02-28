#line 1 "/Users/victor/Downloads/code/ruraltech/coleira/funcionamento.md"
# Funcionamento da Coleira (`coleira-1.0.0`)

## 1) Objetivo
Firmware da coleira em ESP32 para:

1. Telemetria periódica via LoRa segura.
2. Geofence autônoma com ação local (beep/pulso) mesmo sem gateway.
3. Execução de plano de condução por fases.
4. OTA via Wi-Fi quando habilitado.

## 2) Arquitetura de módulos

1. `coleira.ino`: orquestração principal (boot, loop, estados, LoRa, OTA).
2. `SensorsManager.*`: GPS + temperatura (MLX90614) + movimento (MPU6050).
3. `Geofence.*`: ponto-em-polígono e proximidade de borda.
4. `SafetyController.*`: beep e pulso com travas de segurança.
5. `HerdingController.*`: progressão de fases de condução.
6. `StateMachine.*`: modo e intervalo de operação.
7. `LoRaManager.*` + `LoRaProtocol.*` + `CryptoEngine.*`: enlace LoRa seguro.
8. `StorageQueue.*`: fila de eventos offline em EEPROM.

## 3) Fluxo de inicialização

1. Inicializa serial, watchdog e módulos base.
2. Carrega configuração persistida em NVS:
   - `wifi_ota_enabled`
   - cerca virtual
   - plano de condução
3. Liga Wi-Fi/OTA se habilitado.
4. Inicializa sensores, segurança, fila de eventos e LoRa.

## 4) Ciclo operacional (loop)

1. Atualiza sensores.
2. Aguarda intervalo conforme modo:
   - `NORMAL`: 180000 ms
   - `ALERTA`: 20000 ms
   - `CONDUCAO`: 15000 ms
3. Monta telemetria e envia uplink LoRa.
4. Avalia geofence:
   - dentro e perto da borda: `beep` nível 1 + evento `APPROACH`
   - fora da cerca: `beep` nível 2 + evento `VIOLATION`
   - violação persistente + GPS saudável + limites OK: aplica pulso leve
5. Atualiza condução por fases (quando ativa).
6. Processa downlink recebido na janela `RX_WINDOW_MS`.
7. Tenta reenviar eventos pendentes da fila EEPROM.
8. Se Wi-Fi/OTA estiver desligado, entra em deep sleep para economia.

## 5) Segurança animal

1. Escalonamento obrigatório: aviso sonoro antes de pulso.
2. Limites locais de pulso:
   - máximo de 3 pulsos por 10 minutos
   - intervalo mínimo de 120 segundos entre pulsos
   - duração do pulso de 250 ms
3. Pulso só ocorre com GPS considerado saudável (`hdop` e satélites).

## 6) Comunicação LoRa

1. Payload de aplicação por frame: até `128` bytes.
2. Estrutura de frame: `device_id`, `msg_type`, `seq`, `timestamp`, `nonce(12)`, `payload_len`, `payload`, `tag(16)`.
3. Criptografia/autenticidade: AES-CTR + HMAC-SHA256 truncado.
4. Anti-replay por `seq` monotônico.
5. A coleira ignora frames não destinados ao próprio `device_id` (ou broadcast `0`).

## 7) Comandos downlink suportados

1. `SET_FENCE`
   - formato completo: `{"points":[[lat,lon], ...]}`
   - formato fragmentado: `{"chunked":true,"part":i,"total":n,"points":[...]}`
2. `SET_HERDING_PLAN`
   - formato completo: `{"phases":[[[lat,lon], ...], ...]}`
   - formato fragmentado por fase/parte:
     `{"chunked":true,"phase_index":p,"phase_total":P,"part":i,"total":n,"points":[...]}`
3. `SET_PARAMS`
   - `{"wifi_ota_enabled": true|false}`
   - para `wifi_ota_enabled=false`, o payload deve trazer
     `requested_by_role=adm` ou `requested_by_admin=true`
4. `PING`
   - responde com `ACK` e `reason: "pong"`.

Para comandos válidos, a coleira responde `ACK`; para erro de validação/ordem de chunk, responde `NACK` com `reason`.

## 8) Persistência local

1. NVS (`Preferences`):
   - estado `wifi_ota_enabled`
   - cerca virtual
   - plano de condução
   - `seq` uplink LoRa via high-watermark (`lora_seq_hi`) para anti-replay após reboot/power-cycle
2. EEPROM:
   - ring buffer de 20 eventos críticos para reenvio posterior.

## 9) OTA/Wi-Fi

1. OTA usa porta `3232` com senha.
2. No build atual, o default está em AP forçado (`OTA_FORCE_AP_ONLY=true`).
3. SSID do AP da coleira: `RuralTech-Coleira-OTA-<ID6HEX>`.
4. `wifi_ota_enabled` pode ser alternado remotamente e persiste após reboot.
5. BLE de descoberta acompanha `wifi_ota_enabled`:
   - `true` -> BLE ativo.
   - `false` -> BLE desligado e coleira segue em LoRa-only.

## 10) Limites operacionais atuais

1. Geofence: `3..32` pontos.
2. Condução: `1..8` fases.
3. Pontos por fase de condução: `3..32`.
4. Telemetria/evento trafegam em payload LoRa de até `128` bytes; comandos grandes usam fragmentação.
5. Build recomendado no ESP32 Dev Module: `PartitionScheme=min_spiffs` (1.9MB APP com OTA).

## 11) Fluxo integrado esperado

1. App envia comando ao gateway por WebSocket.
2. Gateway fragmenta quando necessário e envia por LoRa.
3. Coleira reagrupa/aplica configuração e responde `ACK/NACK`.
4. Telemetria e eventos sobem da coleira para gateway(s) e podem seguir para app/backend.
