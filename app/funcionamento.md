# Funcionamento do App (`Flutter + Firebase`)

## 1) Objetivo
Aplicativo para operação do sistema RuralTech:

1. Autenticação de usuário.
2. Gestão de propriedades, áreas, coleiras e gateways.
3. Visualização em mapa com filtros.
4. Envio de comandos para coleiras via gateway.
5. Registro de geofence e plano de condução no Firestore.

## 2) Inicialização da aplicação

1. Inicializa Firebase (`Firebase.initializeApp`).
2. Se falhar a inicialização, mostra tela de erro de bootstrap.
3. Sobe providers globais:
   - `AuthService`
   - `FirebaseService`
   - `GatewayService`
   - `BluetoothDiscoveryService`
   - `MapFilterService`
4. Tela inicial depende de login:
   - sem usuário -> `LoginScreen`
   - usuário autenticado -> `HomeScreen`

## 3) Autenticação e perfil

1. Login e cadastro por email/senha (`Firebase Auth`).
2. Documento de usuário em `/users/{uid}` é criado/carregado automaticamente.
3. Papel (`role`) suportado:
   - `user`
   - `adm`
4. Usuário admin pode alterar papel de outro usuário por email.

## 4) Regras de acesso (Firestore)

As regras implementam controle por:

1. Papel admin (`role == adm`).
2. Dono do recurso (`ownerUid` / `createdByUid`).
3. Lista de usuários vinculados (`userUids`).
4. Referência de propriedade associada (para áreas e gateways).

Coleções com regras aplicadas:

1. `users`
2. `collars`
3. `gateways`
4. `ruralProperties`
5. `areas`
6. `fences`
7. `herdingPlans`
8. `events`

## 5) Home e mapa operacional

`HomeScreen` combina streams em tempo real de:

1. Propriedades rurais.
2. Áreas.
3. Coleiras.
4. Gateways.

Funcionalidades do mapa:

1. Renderização de polígonos de propriedade e área.
2. Renderização de coleiras e gateways como marcadores.
3. Exibição de área calculada em rótulos.
4. Localização do usuário e orientação (heading) via `Geolocator`.
5. Seleção de polígono no mapa para edição.
6. Atalhos de navegação:
   - resetar orientação norte
   - centralizar no usuário.

## 6) Cadastro e edição de dados

Pelo app é possível:

1. Criar propriedade rural com polígono.
2. Criar área vinculada a propriedade.
3. Incluir/editar coleira (nome, status, posição, gateway, propriedade).
4. Incluir/editar gateway (nome, status, host, posição, propriedade).
5. Editar polígonos existentes com arrasto/inserção de pontos.
6. Escolher ponto no mapa para posicionamento de coleira/gateway.
7. Apagar registros:
   - coleira (somente `adm`)
   - gateway (somente `adm`)
   - propriedade rural (somente `adm`)
   - área ( `adm` e `user` com acesso )

## 6.1) Descoberta de dispositivos para cadastro

1. O app combina descoberta por LoRa (via gateway) e Bluetooth (BLE).
2. Se a coleira/gateway já enviar dados (id, nome, posição), o app preenche automaticamente.
3. Se for primeira inclusão, os campos continuam editáveis para preenchimento manual.
4. Regra de negócio aplicada no app:
   - coleira/gateway/gateway matriz via BLE só aparece quando o firmware sinaliza `wifi_ota_enabled=true`.
5. Na inclusão de coleira:
   - Bluetooth/Wi-Fi OTA são usados para associar a coleira ao cadastro.
   - conexão LoRa via gateway aparece como fonte opcional separada.
6. Troca de modo de conectividade:
   - padrão inicial: `wifi_ota_enabled=true` (Wi-Fi/Bluetooth/LoRa).
   - alternância para `LoRa-only` (`wifi_ota_enabled=false`) só é permitida para perfil `adm`.

## 7) Geofence e condução (integração com firmware)

### Geofence (`GeofenceScreen`)

1. Usuário desenha polígono no mapa.
2. Limite de pontos do app: `3..32`.
3. Salva em Firestore (`/fences/{deviceId}`).
4. Envia comando ao gateway:
   - `SET_FENCE` com payload `points`.

### Condução (`HerdingScreen`)

1. Gera plano de 3 fases (modelo atual da tela).
2. Salva em Firestore (`/herdingPlans/{deviceId}`).
3. Envia comando ao gateway:
   - `SET_HERDING_PLAN` com payload `phases`.

## 8) GatewayService (WebSocket com gateway)

1. Host padrão: `ws://192.168.4.1:81`.
2. Recebe mensagens do gateway e mantém buffer local (até 200).
3. Expõe estado de conexão e último erro.
4. Envio de comando padronizado:
   - `type=send_command`
   - `device_id`, `command`, `payload`.
5. Validação local antes de enviar:
   - `device_id` válido
   - `SET_FENCE`: `3..32` pontos válidos
   - `SET_HERDING_PLAN`: `1..8` fases e `3..32` pontos por fase.
6. Em erro de validação local, gera `command_result` local no feed.

## 9) Eventos e telemetria

`EventsScreen` exibe:

1. Eventos criticos persistidos no Firestore (`events`) via stream em tempo real.
2. Falhas de leitura/persistencia no fluxo de eventos, quando houver.
3. Feed para inspecao operacional com `deviceId`, tipo de evento e gateway.

Os eventos chegam do gateway via WebSocket, sao persistidos pelo app e depois lidos pelo `EventsScreen` a partir do Firestore.

## 10) Filtros de visualização

`ProfileScreen` permite filtrar o que aparece na Home por:

1. Propriedades
2. Áreas
3. Coleiras
4. Gateways

Os filtros são geridos por `MapFilterService` e aplicados em tempo real.

## 11) Fluxo ponta a ponta (app -> gateway -> coleira)

1. App conecta no gateway por WebSocket.
2. Usuário publica geofence/plano.
3. App salva referência no Firestore.
4. App envia comando ao gateway.
5. Gateway fragmenta se necessário e transmite por LoRa.
6. Coleira aplica e responde `ACK/NACK`.
7. Uplinks de telemetria/evento voltam ao app via gateway.

## 12) Limites atuais relevantes

1. Geofence no app: até `32` pontos.
2. Plano de condução no app: até `8` fases.
3. Pontos por fase: até `32`.
4. O payload LoRa por frame é `128` bytes (a fragmentação é feita no gateway).
5. Área (`AreaEditor`/edição de área): bloqueio em tempo real no `33º` ponto com aviso ao usuário.
