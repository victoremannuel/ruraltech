# Task: Sprint 1 · Redesign RuralTech v2

#ruraltech
#tarefas

## Context

Sprint 1 do redesign handoff (`brain/tarefas/design_handoff_ruraltech_v2/`).
Foco: **fundações** — tokens de design, tipografia e redesenho de 3 telas
(Login, Device Details e Eventos).

Branch: `claude/implement-design-sprint-1-pMOiT`.

## Action

Implementar os 5 quick wins de Sprint 1 mantendo a lógica operacional:

- [x] **Q1 — Tokens OKLCH** · `app/lib/design/colors.dart`, `tokens.dart`
  - Conversor OKLCH → sRGB em tempo de carga (sem dependência externa).
  - Classes `RTColors`, `RTSpacing`, `RTRadius`, `RTElevation`.
- [x] **Q2 — Tipografia** · `app/lib/design/typography.dart`
  - Inter Tight (display), Inter (body), JetBrains Mono (técnico).
  - Dependência nova: `google_fonts: ^6.2.1`.
  - `RTTypography` com escala h1–monoSmall + `textTheme()` para Material 3.
- [x] **Q3 — Device Details** · `app/lib/screens/device_details_screen.dart`
  - `RTHealthHero` (card verde com breakdown LoRa/MPU/MLX/Fila).
  - `RTTelemetryGrid` (coordenadas, HDOP, RSSI em mono).
  - `RTActionRow` substitui `ListTile` nas ações (Geofence, Condução, Log).
- [x] **Q4 — Eventos** · `app/lib/screens/events_screen.dart`
  - `RTEventCard` com ícone tonal por severidade (danger/warn/ok/info).
  - Header com contadores críticos vs informativos.
  - Filtros em chip (`Todos`, `Críticos`, `Informativos`).
  - Empty/error states redesenhados.
- [x] **Q5 — Login** · `app/lib/screens/login_screen.dart`
  - `RTAuthScaffold` com hero gradient terra→floresta e padrão topográfico.
  - `RTField` com ícone, toggle de senha e validação inline (email/6 chars).
  - Dica de operação offline em banner accent.
- [x] **Theme** · `app/lib/design/theme.dart` + `app/lib/main.dart`
  - `buildRuralTechTheme()` ancora todos os widgets Material 3.
  - Removido o theme inline antigo em `main.dart`.

## Componentes criados

```
app/lib/
├── design/
│   ├── colors.dart       (RTColors + conversor OKLCH)
│   ├── tokens.dart       (RTSpacing, RTRadius, RTElevation)
│   ├── typography.dart   (RTTypography)
│   └── theme.dart        (buildRuralTechTheme)
└── components/
    ├── primitives/
    │   ├── rt_button.dart
    │   ├── rt_field.dart
    │   ├── rt_card.dart
    │   └── rt_badge.dart
    └── domain/
        ├── rt_health_hero.dart
        ├── rt_telemetry_grid.dart
        ├── rt_action_row.dart
        ├── rt_event_card.dart
        └── rt_auth_scaffold.dart
```

## Status

✅ **Concluído** — 5/5 quick wins + theme + componentes primitivos.

Não houve refatoração de `dashboard_screen.dart` nem de `geofence`/`herding` —
esses itens pertencem a Sprint 2/3 (itens S1–S7 do backlog).

## Next step

Sprint 2: bottom nav persistente + refatoração do `dashboard_screen.dart` +
controles de mapa em coluna vertical + bottom sheet dinâmica de coleira.

## Related

- [[design_handoff_ruraltech_v2/README]]
- [[arquitetura-design-system-v2]]
