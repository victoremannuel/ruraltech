# RuralTech App (Flutter + Supabase)

Aplicativo Flutter com `Supabase Auth`, `Postgres`, `Realtime` e telemetria via WebSocket local do gateway.

Plataformas suportadas neste projeto: `iOS`, `Android` e `Web`.

## Pré-requisitos
- Flutter SDK instalado e no `PATH`
- Xcode (iOS), Android Studio/SDK (Android), navegador (Web)
- Projeto Supabase configurado

## Setup inicial (uma vez)
```bash
cd /Users/victor/Downloads/code/ruraltech/app
flutter doctor
flutter pub get
```

## Configuração Supabase (resumo)
1. Crie/acesse o projeto Supabase.
2. Configure Auth por email/senha.
3. Ajuste `SUPABASE_URL` e `SUPABASE_ANON_KEY` por `--dart-define` ou em `lib/config/manual_settings.dart`.
4. Publique schema e functions:
```bash
../app/scripts/deploy_supabase.sh --project-ref <seu_project_ref>
```
5. Provisione a `writerKey` da matriz na fila cloud:
```bash
./scripts/provision_matrix_writer_key.sh \
  --url https://<seu_project_ref>.supabase.co \
  --service-role-key <service_role_key>
```
Observação:
- O script lê `RT_CFG_RTDB_MATRIX_ID`, `RT_CFG_RTDB_WRITER_KEY` e `RT_CFG_RTDB_QUEUE_KEY` de `../gateway-matriz/manual_settings.local.h`.
- Se o arquivo local não existir, copie de `../gateway-matriz/manual_settings.local.example.h`.

## Executar em Debug

`debug` é o padrão do `flutter run`.

### iOS (simulador)
```bash
flutter devices
flutter run -d "iPhone 16e"
```

### iOS (iPhone físico)
```bash
flutter devices
flutter run -d "VEST"
```

### Android
```bash
flutter devices
flutter run -d <android_device_id>
```

### Web (Chrome)
```bash
flutter run -d chrome
```

## Executar em Profile

### iOS (simulador ou físico)
```bash
flutter run --profile -d "iPhone 16e"
flutter run --profile -d "VEST"
```

### Android
```bash
flutter run --profile -d <android_device_id>
```

### Web (Chrome)
```bash
flutter run --profile -d chrome
```

## Executar em Release

### iOS
```bash
flutter run --release -d "VEST"
```

### Android
```bash
flutter run --release -d <android_device_id>
```

### Web
```bash
flutter build web --release
```

## Build distribuível (opcional)

Antes do release Android, configure assinatura:
```bash
cp android/key.properties.example android/key.properties
```
Depois edite `android/key.properties` com keystore real (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`).

### Android APK
```bash
flutter build apk --release
```

### Android App Bundle
```bash
flutter build appbundle --release
```

### iOS (arquivo para distribuição via Xcode)
```bash
flutter build ios --release
```

## Hot reload / restart
Com `flutter run` em execução:
- `r` = hot reload
- `R` = hot restart
- `q` = sair

## Quando demorar/travar: diagnóstico rápido

### Ver processos de build Apple (`xcodebuild`)
```bash
ps -axo pid,etime,%cpu,command | grep xcodebuild | grep -v grep
```

Interpretação:
- `%cpu > 0`: build está ativo
- `%cpu ~0 por vários minutos`: provável travamento

### Ver processo Flutter
```bash
ps -axo pid,etime,%cpu,command | grep flutter | grep -v grep
```

### Ver uso de CPU em tempo real
```bash
top -o cpu -stats pid,command,cpu | head -30
```

## Limpeza e rebuild (quando necessário)

### Limpeza padrão
```bash
flutter clean
flutter pub get
```

### iOS completo (pods + derived data)
```bash
pkill -f xcodebuild
pkill -f flutter
rm -rf ~/Library/Developer/Xcode/DerivedData/*
cd ios
pod deintegrate
pod install
cd ..
flutter run -d "VEST" --device-timeout 180
```

## Comandos úteis

### Listar devices
```bash
flutter devices
```

### Ver emuladores
```bash
flutter emulators
```

### Análise estática
```bash
flutter analyze
```

### Testes
```bash
flutter test
```

## Rodar via Xcode (iOS)
```bash
open ios/Runner.xcworkspace
```
No Xcode:
1. Selecione target `Runner`
2. Selecione device
3. `Cmd + R` para Run

## Backend do app
- Bootstrap do Supabase: `lib/main.dart`
- Configuração manual: `lib/config/manual_settings.dart`
- Camada de acesso cloud: `lib/services/firebase_service.dart` (compatibilidade interna)
