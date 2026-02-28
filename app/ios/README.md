# iOS (app/ios)

Plataforma iOS ativa no projeto Flutter.

## Pontos de configuracao

1. `Runner.xcodeproj`: bundle id e assinatura.
2. `Runner/GoogleService-Info.plist`: configuracao Firebase iOS.
3. `Runner/Info.plist`: permissoes e excecoes de rede local (ATS).

## Build rapido

```bash
cd /Users/victor/Downloads/code/ruraltech/app
flutter build ios --release
```
