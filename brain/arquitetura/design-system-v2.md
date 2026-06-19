# Architecture: Design System RuralTech v2

#ruraltech
#arquitetura

## Overview

Design system estabelecido em Sprint 1 do redesign. Centraliza tokens OKLCH,
tipografia (Inter Tight / Inter / JetBrains Mono) e componentes primitivos/
domínio usados por todas as novas telas.
Update context: o subgrafo `app/graphify-out-web/GRAPH_REPORT.md` atualizado em 2026-06-18 confirmou `colors.dart`, `tokens.dart`, `typography.dart` e `theme.dart` como abstrações centrais entre as comunidades do app.

Lema do handoff: "Mapa é herói, UI orbita ao redor, dados técnicos em mono".

## Components

### `app/lib/design/`

- `colors.dart` · `RTColors` — paleta neutros/primary/accent/feedback derivada
  de OKLCH. Conversor OKLCH → sRGB roda em tempo de carga (sem pacote).
- `tokens.dart` · `RTSpacing`, `RTRadius`, `RTElevation` — escala 4-based,
  raios r1–r5+rFull, shadows sh1–sh4.
- `typography.dart` · `RTTypography` — h1…monoSmall + `textTheme()` para
  Material 3. Usa `google_fonts` (^6.2.1).
- `theme.dart` · `buildRuralTechTheme()` — monta `ColorScheme` Material 3 +
  text theme + temas de AppBar/Card/Input/Button/Chip/BottomSheet.

### `app/lib/components/primitives/`

- `RTButton` — primary/accent/tonal/ghost/danger, tamanhos md/lg, estado
  loading, ícone leading + trailing.
- `RTField` — input com ícone, toggle de visibilidade, validação inline.
- `RTCard` — superfície neutra com borda sutil + sombra.
- `RTBadge` — tonal (ok/warn/danger/info/primary/accent/neutral) com dot ou
  ícone opcional; suporta fonte mono.

### `app/lib/components/domain/`

- `RTHealthHero` — card verde com gradiente, badge de status global e grid de
  subsistemas (LoRa/MPU/MLX/Fila).
- `RTTelemetryGrid` — grid 2-col de labels uppercase + valores mono.
- `RTActionRow` — substitui ListTile para ações clicáveis com ícone tonal.
- `RTEventCard` — card de evento com severidade tonal + timestamp mono +
  badge opcional "VIVO" para eventos recentes.
- `RTAuthScaffold` — shell de login com hero topográfico (painter custom) e
  sheet curvo branco.
- `RTCollarSheet` [[uiux-telas]] (Sprint 2) — `DraggableScrollableSheet` com peek/expand,
  grabber, header (título + badge ONLINE/OFFLINE), `RTTelemetryGrid` e
  `Wrap<RTButton>` de ações.

### `app/lib/components/map/` (Sprint 2)

- `RTMapControls` — stack vertical de controles de mapa (44x44 cada) com
  borda `hair`, divisor `hairSoft`, shadow `sh2`. Substitui `Column` de
  `FloatingActionButton.small` no mapa.
- `RTFilterChips` — chips horizontais animados com badge opcional de count,
  para overlays sobre o canvas do mapa.

### `app/lib/components/primitives/rt_fab.dart` (Sprint 2)

- `RTFab` — FAB extendido accent com speed-dial (rotação 45° do ícone, fade
  + translate dos `_ActionPill`). Label padrão "Novo".

### Hubs confirmados pelo grafo do app (2026-06-18)

- `RTActionRow`, `RTField`, `RTFab`, `RTCollarSheet` e `HomeShell` aparecem como hubs de comunidades relevantes no recorte web do `app/`.
- `colors.dart`, `tokens.dart`, `typography.dart` e `theme.dart` continuam atuando como eixo transversal entre telas, componentes primitivos e componentes de domínio.

## Shell (Sprint 2)

- `app/lib/screens/home_shell.dart` · `HomeShell` [[uiux-telas]] — `NavigationBar` M3 +
  `IndexedStack` preservando estado das 4 abas via `PageStorageKey` +
  `AutomaticKeepAliveClientMixin`. Tabs: Mapa / Eventos / Operações / Perfil.
- `app/lib/screens/operations_screen.dart` · `OperationsScreen` [[uiux-telas]] — hub
  operacional em cards (`RTCard` + `RTActionRow`) com seções Campo (todos) e
  Cadastros (admin).

## Flow

Telas consomem primitivos + componentes de domínio. Tokens são acessados via
`RTColors.*`, `RTSpacing.*`, `RTRadius.*`, `RTTypography.*`. `ThemeData`
derivado desses tokens garante que widgets Material padrão também herdem o
visual novo.

```
ThemeData (buildRuralTechTheme)
  ← ColorScheme(RTColors)
  ← TextTheme (RTTypography.textTheme())

Tela (Login/DeviceDetails/Events)
  ← RTAuthScaffold | RTHealthHero | RTEventCard …
      ← RTCard | RTButton | RTField | RTBadge
          ← RTColors / RTSpacing / RTRadius / RTTypography
```

## Technologies

- Flutter Material 3 (`useMaterial3: true`).
- `google_fonts` para carregar Inter Tight / Inter / JetBrains Mono sem ter
  que bundlar `.ttf` — fallback para sistema quando offline.
- OKLCH → sRGB feito in-house (sem pacote de cor externo) para manter as
  cores perceptualmente fiéis ao handoff.

## Related

- [[sprint-1-redesign-v2]]
- [[sprint-2-redesign-v2]]
- [[design_handoff_ruraltech_v2/README]]
- [[uiux-telas]]
