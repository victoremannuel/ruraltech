# iOS (app/ios)

Plataforma iOS ativa no projeto Flutter.

## Pontos de configuracao

1. `Runner.xcodeproj`: bundle id e assinatura.
2. `Runner/Info.plist`: permissoes e excecoes de rede local (ATS).
3. `../lib/config/manual_settings.dart`: bootstrap do backend Supabase no app.

## Build rapido

```bash
cd /Users/victor/Downloads/code/ruraltech/app
flutter build ios --release
```
