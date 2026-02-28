# Configuracao Manual de Ambiente

Este arquivo centraliza onde alterar configuracoes manuais para rodar o projeto em outra rede/ambiente.

## 1) Gateway matriz (ESP32)

Arquivos:
- `gateway-matriz/manual_settings.h` (defaults/publico)
- `gateway-matriz/manual_settings.local.h` (segredos, nao versionado)
- `gateway-matriz/manual_settings.local.example.h` (template)

Campos principais:
- `BACKHAUL_WIFI_SSID`
- `BACKHAUL_WIFI_PASS`
- `FIREBASE_RTDB_HOST`
- `RTDB_MATRIX_ID`
- `RTDB_WRITER_KEY`
- `AP_SSID`, `AP_PASS`
- `OTA_HOSTNAME`, `OTA_PASSWORD`

Observacao:
- Crie o arquivo local antes de compilar em producao:
  ```bash
  cp gateway-matriz/manual_settings.local.example.h gateway-matriz/manual_settings.local.h
  ```
- Preencha no arquivo local os campos sensiveis:
  - `RT_CFG_BACKHAUL_WIFI_SSID`
  - `RT_CFG_BACKHAUL_WIFI_PASS`
  - `RT_CFG_RTDB_MATRIX_ID`
  - `RT_CFG_RTDB_WRITER_KEY`
- `gateway-matriz/config.h` referencia `manual_settings.h`, que aplica override automatico do arquivo local.
- Depois de atualizar `RTDB_MATRIX_ID`/`RTDB_WRITER_KEY`, provisione no RTDB:
  ```bash
  cd /Users/victor/Downloads/code/ruraltech/app
  ./scripts/provision_matrix_writer_key.sh --project <seu_project_id>
  ```

## 2) Gateway comum (ESP32)

Arquivo: `gateway/manual_settings.h`

Campos principais:
- `AP_SSID`, `AP_PASS`
- `OTA_HOSTNAME`, `OTA_PASSWORD`

Observacao:
- `gateway/config.h` agora apenas referencia esse arquivo.

## 3) Coleira (ESP32)

Arquivo: `coleira/manual_settings.h`

Campos principais:
- `WIFI_SSID`, `WIFI_PASS` (OTA via STA)
- `OTA_HOSTNAME`, `OTA_PASSWORD`
- `OTA_AP_SSID`, `OTA_AP_PASS` (AP fallback)

Observacao:
- `coleira/config.h` agora apenas referencia esse arquivo.

## 4) App Flutter

Arquivo: `app/lib/config/manual_settings.dart`

Campos principais:
- `firebaseRtdbUrl`
- `defaultGatewayWsHost`
- `onboardingSubnets`
- `onboardingSubnetProbeLimit`

Arquivos que usam essas configuracoes:
- `app/lib/services/firebase_service.dart`
- `app/lib/services/gateway_service.dart`
- `app/lib/screens/dashboard_screen.dart`

## 5) Firebase do app (projeto)

Para trocar de projeto Firebase, continue usando:
- `flutterfire configure`

O comando atualiza arquivos gerados como:
- `app/lib/firebase_options.dart`
- `app/android/app/google-services.json`
- `app/ios/Runner/GoogleService-Info.plist`
- `app/macos/Runner/GoogleService-Info.plist`
