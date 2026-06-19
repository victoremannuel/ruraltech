# 03 · Device Details — Spec

**Arquivo Flutter:** `app/lib/screens/device_details_screen.dart`  
**Status:** Próximo do mockup, ajustes de polimento.

---

## Layout

```
┌─────────────────────────────────────┐
│ [← Coleira C-042                ⋯ ] │ AppBar simples
├─────────────────────────────────────┤
│                                     │
│ ┌───────────────────────────────┐   │
│ │ [🟢] SAÚDE DA COLEIRA         │   │ ← Hero card
│ │      Todos sistemas OK         │   │   gradient verde
│ │                                │   │   primarySoft → bg
│ │ Última saúde reportada às     │   │
│ │ 14:32 · 25/04                 │   │
│ │                                │   │
│ │ ┌────┬────┬────┬────┐         │   │
│ │ │LoRa│MPU │MLX │Fila│         │   │
│ │ │ OK │ OK │ OK │ OK │         │   │
│ │ └────┴────┴────┴────┘         │   │
│ │                                │   │
│ │ ● Online · ID 042 · há 2 min  │   │
│ └───────────────────────────────┘   │
│                                     │
│ ┌───────────────────────────────┐   │
│ │ ÚLTIMA POSIÇÃO                │   │ ← TelemetryGrid
│ │ Coordenadas                    │   │
│ │ −23.284731, −46.592088        │   │ mono, emphasis
│ │ Registro na matriz             │   │
│ │ 25/04/2026 14:32:18           │   │ mono
│ └───────────────────────────────┘   │
│                                     │
│ ┌───────────────────────────────┐   │
│ │ GPS E BARRAMENTO              │   │ ← TelemetryGrid 2-col
│ │ UART GPS  OK    NMEA   OK     │   │
│ │ Fix       OK    Sat    8      │   │
│ │ HDOP      1.2   I2C    3      │   │
│ └───────────────────────────────┘   │
│                                     │
│ ┌───────────────────────────────┐   │
│ │ AÇÕES OPERACIONAIS            │   │ ← Card com 3 RTActionRow
│ │ ─────────────────────────────  │   │
│ │ [⊡] Configurar Geofence    [›]│   │
│ │     Desenhar perímetro no mapa │   │
│ │ ─────────────────────────────  │   │
│ │ [↗] Plano de Condução      [›]│   │
│ │     Arrebanhar para área-alvo  │   │
│ │ ─────────────────────────────  │   │
│ │ [📋] Abrir log da coleira  [›]│   │
│ │     Mensagens recebidas (324)  │   │
│ └───────────────────────────────┘   │
│                                     │
└─────────────────────────────────────┘
```

---

## Ajustes necessários

A implementação atual já tem essa estrutura. Polimentos:

1. **Hero card** (`RTHealthHero`):
   - Confirmar gradient sutil de `RTColors.primarySoft` → `RTColors.bg` no fundo do card
   - Emoji 🟢 deve ser `Container` circular verde com Icon ✓ branco — não emoji
   - Pills "OK"/"Falha" dos componentes em mono 11px, fundo `okSoft`/`dangerSoft`

2. **Telemetry Grid**:
   - Coordenadas em **mono** com letter-spacing -0.01
   - Valores `emphasis: true` em 14px InterTight 600
   - Labels uppercase 11px com letter-spacing 0.06em

3. **Action Rows**:
   - Ícone leading dentro de container 40×40 com `bgAlt` background
   - Title 15px medium, description 12.5px inkSoft
   - Trailing chevron `Icons.chevron_right` 18px inkMute
   - Estado disabled: opacity 0.5, ícone em inkMute

4. **Spacing entre cards**: `RTSpacing.x3` (12px), não x4

---

## Tokens

- Background da tela: `RTColors.bgAlt`
- Cards: `RTColors.bg` com border `hairSoft`
- Hero gradient: `primarySoft` → `bg` (vertical, 30% opacity blend)
- Mono em coordenadas, timestamps, ID
