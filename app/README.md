# RuralTech App (Flutter + Firebase)

Aplicativo Flutter com Auth + Firestore + Telemetria WebSocket.

## Pré-requisitos
- Flutter SDK instalado e no `PATH`
- Xcode (iOS/macOS), Android Studio/SDK (Android), navegador (Web)
- Firebase configurado no projeto

## Setup inicial (uma vez)
```bash
cd /Users/victor/Downloads/code/ruraltech/app
flutter doctor
flutter pub get
```

## Configuração Firebase (resumo)
1. Crie/acesse o projeto Firebase.
2. Ative Authentication (email/senha).
3. Ative Cloud Firestore.
4. Gere arquivos de configuração (`google-services.json` e `GoogleService-Info.plist`).
5. Publique regras:
```bash
firebase deploy --only firestore:rules --project <seu_project_id>
```

## Executar em Debug

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

### macOS
```bash
flutter run -d macos
```

### Windows
```bash
flutter run -d windows
```

### Linux
```bash
flutter run -d linux
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

### macOS
```bash
flutter run --release -d macos
```

### Windows
```bash
flutter run --release -d windows
```

### Linux
```bash
flutter run --release -d linux
```

## Build distribuível (opcional)

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

### Ver processos de build (macOS)
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

## Telemetria do gateway
Ajuste o host em `lib/services/gateway_service.dart` (`gatewayHost`).
