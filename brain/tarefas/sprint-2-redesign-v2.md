# Task: Sprint 2 — Redesign RuralTech v2 (estrutural)

#ruraltech
#tarefas

## Context

Segunda fase da implementação do design handoff v2 (`brain/tarefas/design_handoff_ruraltech_v2/`).
Sprint 1 (#`sprint-1-redesign-v2`) entregou tokens + componentes primitivos +
telas de Login, Eventos e Device Details. Sprint 2 ataca os itens estruturais
(S1–S4) do `IMPLEMENTATION_GUIDE.md`: navegação persistente, split do
dashboard, controles verticais do mapa e bottom sheet arrastável.

Constraint preservada: nada da lógica operacional (LoRa, gateway, streams
Supabase, serviços) é alterado — apenas apresentação e navegação.

## Action

Itens entregues:

- **S1 — Bottom Navigation persistente**
  - Novo `app/lib/screens/home_shell.dart` com `NavigationBar` M3 + `IndexedStack`.
  - 4 abas: **Mapa** (`HomeScreen`), **Eventos** (`EventsScreen`), **Operações**
    (`OperationsScreen`, nova), **Perfil** (`ProfileScreen`).
  - `PageStorageKey` + `AutomaticKeepAliveClientMixin` em cada aba para
    preservar estado ao trocar (mapa não reinicia, streams não ressubscrevem).
  - `main.dart` agora monta `HomeShell` no `_AuthenticatedHome` (era
    `HomeScreen`).

- **S2 — Dashboard depurado (sem full split)**
  - Removido `BottomAppBar` interno do `HomeScreen` (IconButtons duplicavam a
    navegação agora provida pelo shell).
  - `_openPlusActions` (modal bottom sheet de ações) substituído por `RTFab`
    speed-dial com label "Novo", ancorado em `floatingActionButton`.
  - Ações migradas para `RTFabAction`: Novo polígono, Arrebanhamento, Incluir
    coleira (adm), Incluir gateway (adm), Reparar estado cloud (adm, tom warn),
    Incluir propriedade (adm), Vincular adm (adm). Keys preservadas.

- **S3 — Novo `OperationsScreen`**
  - `app/lib/screens/operations_screen.dart` com seções "Campo" (Novo polígono,
    Solicitar arrebanhamento) e "Cadastros" (admin-only: Nova propriedade).
  - Reaproveita `RTCard` + `RTActionRow` do Sprint 1.
  - Hint banner informando que coleira/gateway/repair ainda vivem no FAB do
    mapa (migração completa fica para sprint futura).

- **S4 — Controles verticais de mapa**
  - Novo `app/lib/components/map/rt_map_controls.dart` (`RTMapControls`).
  - Botão empilhado 44x44 com borda `hair`, divisor `hairSoft`, shadow `sh2`.
  - Substitui `Column` de `FloatingActionButton.small` (north-up, center-user)
    no `HomeScreen`.

- **S5 — Bottom sheet arrastável de coleira** (componente pronto; integração
  fica para sprint 3)
  - Novo `app/lib/components/domain/rt_collar_sheet.dart` (`RTCollarSheet`).
  - `DraggableScrollableSheet` com peek 0.24 / min 0.16 / max 0.78, grabber,
    header (título + badge ONLINE/OFFLINE + subtítulo + timestamp mono),
    `RTTelemetryGrid` e `Wrap` de `RTButton`.
  - Helper `showRTCollarSheet()` para abrir como modal.

- **Componentes auxiliares criados para sprints futuras**
  - `app/lib/components/primitives/rt_fab.dart` — FAB accent com speed-dial
    animado + `_ActionPill` (label pill branca com borda hair).
  - `app/lib/components/map/rt_filter_chips.dart` — chips horizontais
    arredondados, animados, com badge opcional de count.

## Status

Em andamento / commit pendente.

Checklist:

- [x] `home_shell.dart` criado
- [x] `main.dart` passa a usar `HomeShell`
- [x] `operations_screen.dart` criado
- [x] `rt_map_controls.dart` criado
- [x] `rt_fab.dart` criado
- [x] `rt_filter_chips.dart` criado
- [x] `rt_collar_sheet.dart` criado
- [x] `BottomAppBar` interno removido do dashboard
- [x] `_openPlusActions` substituído por `RTFab`
- [x] Coluna de FABs substituída por `RTMapControls`
- [x] Integração do `RTCollarSheet` no fluxo de tap do marker
- [ ] Split completo de `dashboard_screen.dart` (adiado — escopo grande)
- [x] Commit + push para `claude/implement-design-sprint-1-pMOiT`

## Incremento pós-commit principal

`_openDeviceMarkerActions` migrado de `ListTile` modal para `RTCollarSheet`:

- Resolve `lat/lon/lastSeenMs` priorizando o sample em memória
  (`_latestTelemetryByDeviceId`) sobre o snapshot do Firestore.
- `online` derivado de janela de 5 min sobre `lastSeenMs`.
- Telemetria exibida: coordenadas, última telemetria (relativa), satélites/HDOP
  e temperatura (quando há `dailyHealth`).
- Ações: **Comandos** (primary → `DeviceDetailsScreen`) e **Editar** (tonal →
  `_showEditDeviceDialog`).
- Helpers `_formatCoordPair` / `_formatRelativeFromMs` extraídos para reuso.

## Incremento: Geofence redesenhado (S6 parcial)

`GeofenceScreen` reescrito com os tokens v2, mantendo a lógica de
persistência (`saveFence` + `enqueueScopedCommand`):

- HUD no topo substituindo o banner `Colors.green.withValues`: ícone
  `crop_free` em `primarySoft`, título dinâmico ("Toque no mapa..." →
  "Polígono pronto para publicar"), eyebrow "VÉRTICES" + contador mono
  (`X/32`). Contador muda para `warn` quando atinge o limite.
- Vértices **numerados**: cada marker é um círculo `primaryDeep` 28×28 com
  shadow `sh2` e número JetBrains Mono centralizado (melhor edição visual
  do polígono).
- Linha do polígono passou a usar `primaryDeep` (era `Colors.green.shade700`),
  com preenchimento `primary @ 0.2`.
- Barra de ações no rodapé dentro de `SafeArea`:
  - `Desfazer` → `RTButton` ghost + ícone `undo`
  - `Limpar` → `RTButton` tonal + ícone `delete_outline`
  - `Publicar` → `RTButton` primary com `loading` state + `flex:2`
- Estado de publicação (`_isPublishing`) exibe o spinner do `RTButton`
  durante a chamada de rede e desabilita o botão.
- Keys `geofence_undo_button`, `geofence_clear_button`,
  `geofence_publish_button` preservadas.

Pendente do item S6: tile dark (MapTiler night/custom) — exige mudança
de provedor e ajuste de overlays; adiado para Sprint 4/infra.

## Incremento: Perfil redesenhado

- `ProfileScreen` reescrito com tokens v2 (bg `bgAlt`, tipografia Inter Tight,
  escala de spacing 4-based).
- Card de identidade com avatar em `primarySoft` + email + badge ADMIN/OPERADOR
  (`RTBadge` tone accent/neutral).
- 4 seções de filtro em `RTCard` + `ExpansionTile` temático (sem divisores
  default, leading icon em container `bgSubtle`, subtitle resumindo
  "N de N selecionados").
- Botões `Aplicar filtros` (primary) e `Limpar filtros` (ghost) agora ocupam
  width completo via `RTButton.fullWidth`.
- **Bug fix crítico do Sprint 2**: removido `Navigator.pop(context)` que,
  sob o novo `IndexedStack` do `HomeShell`, saía para o login. Substituído
  por `AppFeedback.success('Filtros aplicados ao mapa.')` — usuário troca de
  aba via bottom nav.
- Novo botão `Sair da conta` (danger variant) na seção "Conta", reduzindo
  dependência do AppBar do dashboard para logout.
- Keys `profile_*_section` / `profile_apply_filters_button` /
  `profile_clear_filters_button` preservadas.

## Next step

Registrar o commit Sprint 2 e empurrar para a branch. Na próxima sessão: split
do dashboard em módulos (streams, markers, FAB, controles) e migrar o modal
atual de seleção de coleira para `RTCollarSheet`.

## Related

- [[sprint-1-redesign-v2]]
- [[design-system-v2]]
- `brain/tarefas/design_handoff_ruraltech_v2/IMPLEMENTATION_GUIDE.md`
