# Task: Auditoria Completa App + Fix Mapa Cinza

#ruraltech
#tarefas

## Context

Após login no app, a tela home aparece mas o mapa some e fica cinza.
Branch: `audit/remove-firebase-complete` (Firebase removido, Supabase completo).

## Action

### Fix 1: Mapa cinza — CONCLUÍDO ✅

**Root cause real (regressão Firebase → Supabase):**

O Firebase Auth só dispara `onAuthStateChange` em login/logout. O Supabase Auth também dispara para `initialSession`, `tokenRefreshed` e outros eventos — o que causava múltiplas chamadas a `_refreshProfile()`.

Com o código original: `if (uid == null || auth.isProfileLoading) { return blocker; }` — cada chamada ao `_refreshProfile()` setava `isProfileLoading = true` e **apagava o mapa inteiro** com um loading spinner. Quando o profile voltava, o FlutterMap era recriado do zero → cinza.

**Fix 1a** (`shouldShowBlockingHomeLoader`): O blocker só aparece uma vez (antes do primeiro render com `_lastReadyAuthKey = null`). Depois que o mapa carregou pela primeira vez, `isProfileLoading = true` não mais apaga o mapa.

**Fix 1b** (StreamBuilder keys sem `isAdmin`): Quando a role do usuário carregava ('user' → 'adm'), a key `...-${auth.isAdmin}-...` mudava → StreamBuilders destruídos → FlutterMap recriado → cinza. Removido `isAdmin` das keys. O stream é recriado internamente via `_updateStreamsIfNeeded`, mas o FlutterMap persiste.

**Fix 1c** (TileLayer subdomains): Adicionado `{s}` com `['a','b','c']` em todas as 5 TileLayers — distribui carga OSM entre os 3 CDN nodes.

**Arquivos modificados:**
- `app/lib/screens/dashboard_screen.dart` — keys, streams, shouldShowBlockingHomeLoader, TileLayer
- `app/lib/screens/map_point_picker_screen.dart` — TileLayer subdomains
- `app/lib/screens/polygon_editor_screen.dart` — TileLayer subdomains
- `app/lib/screens/geofence_screen.dart` — TileLayer subdomains
- `app/lib/widgets/polygon_editing_map.dart` — TileLayer subdomains

### Fix 2: Auditoria funcionalidades — PENDENTE

- [ ] login_screen.dart — Login/signup
- [ ] dashboard_screen.dart — Home + mapa (fix aplicado)
- [ ] device_details_screen.dart — Telemetria do dispositivo
- [ ] collar_log_screen.dart — Histórico de eventos
- [ ] area_editor_screen.dart — Editor de áreas
- [ ] events_screen.dart — Feed de eventos
- [ ] geofence_screen.dart — Cercas virtuais
- [ ] herding_screen.dart — Condução de gado
- [ ] polygon_editor_screen.dart — Editor de polígonos
- [ ] rural_property_editor_screen.dart — Cadastro de propriedades
- [ ] profile_screen.dart — Perfil

### Fix 3: Auditoria Supabase produção — PENDENTE

- [ ] Migrations aplicadas em produção (3 arquivos: firebase_to_supabase, pending_notifications, fix_rls)
- [ ] property_scope_id computado corretamente
- [ ] Índices: property_id, device_id, day_key
- [ ] RLS: has_property_access(), is_admin(), legacy_uid
- [ ] Edge functions: poll-notifications, send-push, queue-lora-command

### Fix 4: Auditoria gateway-matriz — PENDENTE

- [ ] matrix_bindings populado para cada propriedade
- [ ] queue-lora-command: 409 se matrix_queue_keys não populado — documentar pré-requisito
- [ ] Firebase RTDB ainda usado no gateway-matriz firmware (não migrado para Supabase)
- [ ] discoverGatewaysOnLocalNetwork() 120 IPs — confirmar sem UI freeze

## Status

Em andamento

## Next step

1. Testar fix do mapa no dispositivo físico
2. Continuar auditoria das telas restantes
3. Verificar Supabase produção com migrations aplicadas

## Related

[[ruraltech]]
[[requisitos]]
[[modelagem-dados-supabase]]
[[fluxos-comunicacao-ponta-a-ponta]]
[[migracao-supabase]]
[[visao-geral]]
[[uiux-telas]]
[[auditoria-total-solucao-2026-04-11]]
