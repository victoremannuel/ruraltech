# ruraltech

Monorepo com:
- `coleira/`: firmware ESP32 da coleira
- `gateway/`: firmware ESP32 do gateway
- `app/`: aplicativo Flutter + Firebase

## LIGAR O BRAIN

Navegue até a pasta raiz `cd ~/ruraltech`

### 1) ligar o ambiente venv

```bash
source .venv/bin/activate
```

### 2) abra o claude

```bash
claude
```

### 3) reindexar o brain

Reindexa

```bash
/graphify .
```

Ativa o cérebro e reindexa

```bash
/brain
```

## Apoio Git (commit/push/sync)

### Erro comum no push (HTTP 400)

Se aparecer algo como:

```text
error: RPC failed; HTTP 400 curl 22 The requested URL returned error: 400
send-pack: unexpected disconnect while reading sideband packet
fatal: the remote end hung up unexpectedly
Everything up-to-date
```

isso normalmente indica falha de transporte na conexão HTTP, e em alguns casos o commit pode já ter sido aplicado no remoto.

### 1) Confirmar se o push realmente chegou no remoto

```bash
git rev-parse HEAD
git ls-remote origin refs/heads/main
```

Se os hashes forem iguais, o conteúdo local já está em `origin/main`.

Comandos extras de conferência:

```bash
git status
git log --oneline -n 3
git log origin/main --oneline -n 3
```

### 2) Ajustes de estabilidade para push via HTTPS

```bash
git config --global http.version HTTP/1.1
git config --global http.postBuffer 524288000
git config --global core.compression 0
```

Depois, tente novamente:

```bash
git push origin main
```

### 3) Alternativa recomendada se HTTPS continuar falhando: SSH

```bash
git remote set-url origin git@github.com:victoremannuel/ruraltech.git
ssh -T git@github.com
git push origin main
```

### 4) Voltar configs opcionais depois de estabilizar

Se o push já estiver funcionando e você quiser limpar ajustes temporários:

```bash
git config --global --unset http.postBuffer
git config --global --unset core.compression
```

Sugestão: manter `http.version=HTTP/1.1` caso a rede continue instável para uploads maiores.

## Firmwares

### Comando de gravação

```bash
rtk bash -lc 'set -euo pipefail
COLEIRA_PORT="/dev/cu.usbserial-1420"
MATRIZ_PORT="/dev/cu.usbserial-59470049741"
FQBN="esp32:esp32:esp32:PartitionScheme=min_spiffs"

printf "\n=== PREP: cores e libs ===\n"
arduino-cli config init --overwrite || true
arduino-cli core update-index --additional-urls https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
arduino-cli core install esp32:esp32 --additional-urls https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json

arduino-cli lib install "ArduinoJson@7.4.2" || true
arduino-cli lib install "RadioLib@6.6.0" || true
arduino-cli lib install "TinyGPSPlus@1.0.3" || true
arduino-cli lib install "Adafruit MLX90614 Library@2.1.5" || true
arduino-cli lib install "MPU6050_tockn@1.5.2" || true
arduino-cli lib install "WebSockets@2.7.2" || true
arduino-cli lib install "RTClib@2.1.4" || true
arduino-cli lib install "Adafruit SSD1306@2.5.15" || true
arduino-cli lib install "Adafruit GFX Library@1.12.1" || true

printf "\n=== COLEIRA: compilando ===\n"
arduino-cli compile --fqbn "$FQBN" coleira

printf "\n=== COLEIRA: gravando em %s ===\n" "$COLEIRA_PORT"
arduino-cli upload -p "$COLEIRA_PORT" --fqbn "$FQBN" coleira

printf "\n=== MATRIZ: compilando ===\n"
arduino-cli compile --fqbn "$FQBN" gateway-matriz

printf "\n=== MATRIZ: gravando em %s ===\n" "$MATRIZ_PORT"
arduino-cli upload -p "$MATRIZ_PORT" --fqbn "$FQBN" gateway-matriz

printf "\n=== OK: coleira e matriz gravadas ===\n"'
```