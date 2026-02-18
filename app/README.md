# App RuralTech (Flutter + Firebase)

## MVP entregue
- Login (Firebase Auth email/senha)
- Dashboard com dispositivos Firestore
- Detalhes do device
- Cadastro/publicação de geofence
- Geração/publicação de plano de condução
- Stream de telemetria/eventos por WebSocket do gateway

## Pré-requisitos
- Flutter 3.22+
- Firebase projeto configurado

## Configuração Firebase
1. Crie projeto Firebase.
2. Ative Auth (email/senha).
3. Crie Firestore.
4. Publique `firestore.rules`.
5. Adicione `google-services.json` e/ou `GoogleService-Info.plist`.

## Rodar
```bash
cd app
flutter pub get
flutter run
```

## IP do gateway
No `GatewayService`, ajuste `gatewayHost` (default `ws://192.168.4.1:81`).

## Estrutura amigável ao FlutterFlow
- `lib/models`
- `lib/services`
- `lib/screens`
- `lib/widgets`
