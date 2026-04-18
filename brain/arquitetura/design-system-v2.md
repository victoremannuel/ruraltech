# Architecture: Design System RuralTech v2

#ruraltech
#arquitetura

## Overview

Design system estabelecido em Sprint 1 do redesign. Centraliza tokens OKLCH,
tipografia (Inter Tight / Inter / JetBrains Mono) e componentes primitivos/
domínio usados por todas as novas telas.

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
- [[design_handoff_ruraltech_v2/README]]
- [[uiux-telas]]
