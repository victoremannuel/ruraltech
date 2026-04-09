# Android (app/android)

Plataforma Android ativa no projeto Flutter.

## Pontos de configuracao

1. `app/build.gradle.kts`: `namespace` e `applicationId` da aplicacao.
2. `key.properties`: credenciais locais de assinatura (nao versionado).
3. `../lib/config/manual_settings.dart`: bootstrap do backend Supabase no app.

## Build rapido

```bash
cd /Users/victor/Downloads/code/ruraltech/app
flutter build apk --release
flutter build appbundle --release
```
