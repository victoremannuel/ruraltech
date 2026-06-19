# Architecture: UI/UX — Telas do App RuralTech

## Overview

App Flutter (Material 3) com mapa como tela central. Navegação principal via mapa + ações contextuais.

## Components

### Estrutura de Navegação

```
LoginScreen
└─ HomeScreen (mapa principal)
   ├─ ProfileScreen (filtros e perfil do usuário)
   ├─ EventsScreen (log de eventos da propriedade)
   ├─ RuralPropertyEditorScreen (criar/editar fazenda)
   ├─ AreaEditorScreen (criar/editar piquete)
   ├─ DeviceDetailsScreen (detalhes da coleira)
   │   ├─ GeofenceScreen (editor de geofence por coleira)
   │   ├─ HerdingScreen (operação de herding)
   │   └─ CollarLogScreen (log de eventos da coleira)
   ├─ HerdingScreen (acesso direto pelo mapa)
   └─ MapPointPickerScreen (seletor de ponto no mapa)
```

---

### Tela: LoginScreen

**Arquivo:** `screens/login_screen.dart`

**Propósito:** Autenticação do usuário.

**Elementos:**
- Campo email + campo senha
- Botão "Entrar"
- Feedback de erro inline

**Fluxo:** Login → HomeScreen

---

### Tela: HomeScreen (Mapa Principal)

**Arquivo:** `screens/dashboard_screen.dart`

**Propósito:** Dashboard principal — visualização em tempo real do rebanho na propriedade.

**Elementos do mapa:**
- Tiles OpenStreetMap
- Marcadores GPS das coleiras (atualizados em tempo real via WS ou Realtime)
- Polígonos de propriedades e piquetes
- Bússola do dispositivo (flutter_compass)
- Posição do usuário (GPS)
- Scalebar

**Painéis e controles:**
- FAB para navegar para localização do usuário
- Seletor de propriedade / área ativa (filtro contextual)
- Botão para abrir ProfileScreen (filtros de mapa)
- Botão para abrir EventsScreen
- Botão para criar nova propriedade (RuralPropertyEditorScreen)
- Tap em coleira → DeviceDetailsScreen ou ações rápidas
- Tap em polígono → detalhes do piquete / ações de área

**Estado gerenciado:**
- `_latestTelemetryByDeviceId` — posição mais recente por device
- `_selectedAreaId` / `_selectedPropertyId` — seleção ativa no mapa
- `_userPosition` + `_userHeading` — localização e bússola do usuário
- Filtro de mapa via `MapFilterService`

**Streams ativos:**
- `GatewayService.telemetryStream` — telemetria via WebSocket do gateway local
- `CloudService.streamRuralProperties` — propriedades em Realtime
- Supabase Realtime: coleiras, piquetes, telemetria latest

---

### Tela: ProfileScreen (Filtros e Perfil)

**Arquivo:** `screens/profile_screen.dart`

**Propósito:** Configurar filtros de visualização do mapa e gerenciar vínculos.

**Elementos:**
- Exibe email/uid do usuário logado
- Seletores multisseleção:
  - Propriedades visíveis no mapa
  - Piquetes visíveis
  - Coleiras visíveis
  - Gateways visíveis
- Botão "Aplicar filtros" → atualiza `MapFilterService`
- Lista de usuários (para admin)

---

### Tela: EventsScreen

**Arquivo:** `screens/events_screen.dart`

**Propósito:** Log de eventos recentes da propriedade selecionada.

**Elementos:**
- Lista de eventos ordenada por data decrescente
- Tipo, timestamp, device_id
- Preview de payload

---

### Tela: RuralPropertyEditorScreen (Editor de Fazenda)

**Arquivo:** `screens/rural_property_editor_screen.dart`

**Propósito:** Criar ou editar uma propriedade rural.

**Elementos:**
- Campo de nome da fazenda
- Seletor de owner (admin pode trocar)
- Seletor multisseleção de usuários com acesso
- **Mapa editável** com PolygonEditingMap:
  - Tap para adicionar vértice
  - Arrastar vértice para reposicionar
  - Desfazer último ponto
  - Limpar polígono
  - Importar polígono de arquivo (FilePicker: JSON/GeoJSON)
- Métricas do polígono (área em hectares, perímetro)
- Botão "Salvar" → persiste no Supabase e dispara SET_FENCE automático

**Validações:**
- Nome obrigatório
- Polígono: 3–32 pontos
- Owner não pode ser removido de user_uids

---

### Tela: AreaEditorScreen (Editor de Piquete)

**Arquivo:** `screens/area_editor_screen.dart`

**Propósito:** Criar ou editar um piquete dentro de uma propriedade.

**Elementos:**
- Seletor de propriedade
- **Mapa editável** (PolygonEditingMap) para desenhar perímetro
- Seletor de coleiras vinculadas ao piquete (LinkedDeviceSelection)
- Métricas do polígono
- Botão "Salvar" → persiste no Supabase e dispara SET_FENCE seletivo para linkedDeviceIds

**Validações:**
- Propriedade obrigatória
- Polígono: 3–32 pontos
- linkedDeviceIds: IDs numéricos > 0

---

### Tela: DeviceDetailsScreen (Detalhes da Coleira)

**Arquivo:** `screens/device_details_screen.dart`

**Propósito:** Dashboard de saúde e ações de uma coleira específica.

**Seções:**
1. **Identificação:** nome, ID, status, propriedade vinculada
2. **Posição:**
   - Lat/lon com timestamp
   - FutureBuilder para buscar posição mais recente do Supabase (property_telemetry_latest)
3. **Saúde diária (HealthCard):**
   - Data do último relatório
   - Componentes: LoRa, MPU, MLX, Fila (storage)
   - GPS: UART, NMEA, Fix, Satélites, HDOP, I2C
   - Temperatura (decigraus → °C)
   - Uptime (segundos formatado)
   - Wi-Fi OTA status
4. **Ações:**
   - Botão → GeofenceScreen
   - Botão → HerdingScreen
   - Botão → CollarLogScreen

---

### Tela: GeofenceScreen (Editor de Geofence por Coleira)

**Arquivo:** `screens/geofence_screen.dart`

**Propósito:** Definir e publicar cerca virtual para uma coleira específica.

**Elementos:**
- Mapa interativo (FlutterMap + OpenStreetMap)
- Tap para adicionar vértice (até 32)
- Polígono visualizado em verde semitransparente
- Marcadores verdes nos vértices
- Scalebar
- Botões: Desfazer | Limpar | Publicar
- Indicador de contagem: "Pontos: X/32"
- Loading da cerca salva ao abrir

**Validações:**
- Mínimo 3 pontos para publicar
- Coleira deve estar vinculada a uma propriedade
- Máximo 32 pontos

**Fluxo ao publicar:**
- `saveFence(deviceId, uid, points)` → Supabase fences
- `enqueueScopedCommand(SET_FENCE, ...)` → queue no Supabase
- Feedback: "Cerca salva e enfileirada para a matriz"

---

### Tela: HerdingScreen (Operação de Condução)

**Arquivo:** `screens/herding_screen.dart`

**Propósito:** Configurar e iniciar operação de condução de rebanho.

**Elementos:**
- Seletor de propriedade (dropdown)
- Lista de coleiras da propriedade com checkbox de seleção
- **Mapa editável** para desenhar polígono destino
- Status da operação atual (se houver operação em andamento):
  - `submitted`, `dispatching`, `awaiting_assembly`, `requested`, `completed`, `failed`, `superseded`
  - Barra de progresso por coleira
  - Cor de status (verde=concluído, vermelho=falha, laranja=superseded)
- Botão "Iniciar Herding"

**Validações:**
- Pelo menos uma coleira selecionada
- Polígono com 3–32 pontos
- Propriedade obrigatória

**Status labels:**
| Status | Label |
|---|---|
| submitted | Enviado pelo app |
| dispatching | Distribuindo para as coleiras |
| awaiting_assembly | Aguardando montagem completa |
| requested | Arrebanhamento solicitado |
| completed | Arrebanhamento concluído |
| failed | Falhou |
| superseded | Substituído por outra operação |

---

### Tela: CollarLogScreen (Log da Coleira)

**Arquivo:** `screens/collar_log_screen.dart`

**Propósito:** Histórico auditável de eventos e telemetria de uma coleira.

**Elementos:**
- Lista expandível (sanfona) de entradas:
  - **Telemetria:** lat/lon + timestamp
  - **Health diário:** flags de saúde resumidos
  - **Gravação de polígono (polygon_apply_result):**
    - Sucesso: "Sucesso na gravação do [fazenda/piquete/condução]"
    - Falha: "Falha na gravação do [tipo]"
    - Preview SVG do polígono atual na sanfona expandida
  - Outros eventos operacionais
- Toggle de auto-refresh
- Botão de refresh manual

**Tipos de entrada:**
| type | Título exibido |
|---|---|
| telemetry | Telemetria |
| health_daily | Saúde diária |
| polygon_apply_result success | Sucesso na gravação do [label] |
| polygon_apply_result failure | Falha na gravação do [label] |
| outro | kind ou "Evento" |

**Preview SVG:**
- Gerado ao expandir entrada de sucesso de polígono
- Consulta polígono atual (fences/areas/rural_properties por origin_doc_type)
- Consulta posição histórica da coleira (telemetria)
- Renderiza polígono + ponto da coleira via flutter_svg

---

### Tela: MapPointPickerScreen

**Arquivo:** `screens/map_point_picker_screen.dart`

**Propósito:** Seletor de ponto único no mapa (usado por outros editores).

**Elementos:**
- Mapa com tap para selecionar ponto
- Marcador no ponto selecionado
- Botão "Confirmar"

---

## Flow

### Jornada: Configurar Cerca de Fazenda

```
HomeScreen → RuralPropertyEditorScreen (editar polígono) → Salvar
→ Backend: SET_FENCE automático para todas as coleiras
→ CollarLogScreen: "Sucesso na gravação da fazenda" com preview SVG
```

### Jornada: Vincular Coleira a Piquete

```
HomeScreen → AreaEditorScreen (selecionar coleiras + polígono) → Salvar
→ Backend: SET_FENCE seletivo para linked_device_ids
→ CollarLogScreen: "Sucesso na gravação do piquete"
```

### Jornada: Iniciar Herding

```
HomeScreen → HerdingScreen (selecionar coleiras + desenhar destino) → Iniciar
→ Acompanhar status em tempo real na mesma tela
→ Notificação push ao completar
```

### Jornada: Diagnóstico de Saúde

```
HomeScreen → DeviceDetailsScreen → ver health flags + temperatura + uptime
→ CollarLogScreen: ver histórico de health_daily + telemetria
```

## Technologies

- Flutter Material 3
- flutter_map (mapa + OpenStreetMap)
- flutter_compass (bússola)
- geolocator (GPS do dispositivo)
- flutter_svg (preview SVG de polígonos)
- file_picker (importar polígono)
- Provider (gerenciamento de estado)

## Related

[[ruraltech]]
[[regras-negocio]]
[[fluxos-comunicacao-ponta-a-ponta]]
[[requisitos]]
[[visao-geral]]

#arquitetura #ruraltech 