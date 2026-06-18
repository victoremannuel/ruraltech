# 02 · Dashboard / Mapa — Spec pixel-a-pixel

**Arquivo Flutter:** `app/lib/screens/dashboard_screen.dart` (ATUALMENTE 86k bytes — refatoração estrutural pendente)  
**Referência visual:** seção "05 · Telas → 02 Home · Mapa" em `RuralTech Redesign.html`

---

## Layout geral

```
┌─────────────────────────────────────┐
│ ┌─────────────────────┐ [🔔]       │  ← search bar + notif bell
│ │ 🔍 Fazenda Doce·12▾ │            │     translúcido sobre mapa
│ └─────────────────────┘             │
│ [⚫Todos·14] [●Coleiras·9] [⚠·2]    │  ← chips horizontal scroll
│                                     │
│                                  [⊡]│  ← stack vertical de
│                                  [⊙]│     map controls (right)
│         M A P A                  [◉]│     - Camadas
│      (full-bleed, 100%)             │     - GPS (locate me)
│                                     │     - Bússola
│  [pin C-017 verde]                  │
│  [pin C-088 verde]                  │
│  [pin C-042 verde, SELECIONADO]     │
│  [pin GW-01 terra/laranja]          │
│                                     │
├═════════════════════════════════════┤  ← bottom sheet peek
│ ─── (drag handle 40×4 cinza)        │
│ [🟢] Coleira C-042   [● Online]     │  ← header da sheet
│      Q. Norte · A2 · há 2 min       │
│ ┌────┬────┬────┬────┐               │  ← grid 4 telemetrias
│ │ 87%│−92 │8sat│24° │                │
│ │BAT │RSSI│GPS │TEMP│                │
│ └────┴────┴────┴────┘               │
│ [Geofence] [Conduzir] [⋯]           │  ← ações rápidas
├─────────────────────────────────────┤
│ [🗺] [🔔] [↗] [👤]                   │  ← bottom nav 4 tabs
└─────────────────────────────────────┘
```

---

## Estrutura do widget tree

```dart
Scaffold(
  body: Stack(
    children: [
      // 1. MAPA FULL-BLEED (FlutterMap em z=0)
      Positioned.fill(child: FlutterMapWidget(...)),
      
      // 2. SAFE AREA TOP — search + chips
      Positioned(top: 0, left: 0, right: 0, child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(children: [
                Expanded(child: _MapSearchBar()),
                SizedBox(width: 12),
                _NotifBell(badge: true),
              ]),
            ),
            SizedBox(height: 4),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: 16),
                children: [
                  RTFilterChip(label: 'Todos · 14', active: true, icon: Icons.layers),
                  SizedBox(width: 8),
                  RTFilterChip(label: 'Coleiras · 9', dot: RTColors.ok),
                  SizedBox(width: 8),
                  RTFilterChip(label: 'Alertas · 2', dot: RTColors.warn),
                  SizedBox(width: 8),
                  RTFilterChip(label: 'Gateways', icon: Icons.router),
                ],
              ),
            ),
          ],
        ),
      )),
      
      // 3. CONTROLES À DIREITA (stack vertical, vertical-center)
      Positioned(
        right: 12, top: 0, bottom: 0,
        child: Center(child: _MapControlsStack()),
      ),
      
      // 4. BOTTOM SHEET DRAGGABLE
      DraggableScrollableSheet(
        initialChildSize: 0.28,    // peek ~180px
        minChildSize: 0.10,         // colapsado mostra só header
        maxChildSize: 0.72,         // expandido 72%
        snap: true,
        snapSizes: [0.10, 0.28, 0.72],
        builder: (ctx, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: RTColors.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(blurRadius: 24, color: Colors.black.withOpacity(0.12))],
          ),
          child: RTCollarSheet(
            scrollController: scrollCtrl,
            collar: selectedCollar,
          ),
        ),
      ),
      
      // 5. FAB extendido (acima do nav, à direita)
      Positioned(
        right: 16, bottom: 96,  // 80 nav + 16 gap
        child: RTFab(label: 'Novo', icon: Icons.add, onPressed: ...),
      ),
    ],
  ),
  
  // 6. BOTTOM NAV (4 abas)
  bottomNavigationBar: _RTBottomNav(currentIndex: 0),
)
```

---

## Componentes auxiliares

### `_MapSearchBar`
```dart
Container(
  height: 48,
  decoration: BoxDecoration(
    color: RTColors.bg.withOpacity(0.96),
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: RTColors.hair),
    boxShadow: [BoxShadow(blurRadius: 8, color: Colors.black.withOpacity(0.06))],
  ),
  child: Padding(
    padding: EdgeInsets.symmetric(horizontal: 14),
    child: Row(children: [
      Icon(Icons.search, size: 20, color: RTColors.inkMute),
      SizedBox(width: 10),
      Expanded(child: Text('Fazenda Doce Vale', style: RTTypography.body)),
      Container(  // count pill
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: RTColors.bgAlt,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text('12', style: RTTypography.mono.copyWith(fontSize: 11)),
      ),
      SizedBox(width: 6),
      Icon(Icons.keyboard_arrow_down, size: 18, color: RTColors.inkSoft),
    ]),
  ),
)
```

### `_MapControlsStack` (vertical)
3 botões empilhados — Camadas, GPS, Bússola. Cada um:
```dart
Container(
  width: 44, height: 44,
  margin: EdgeInsets.symmetric(vertical: 4),
  decoration: BoxDecoration(
    color: RTColors.bg,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: RTColors.hair),
    boxShadow: [BoxShadow(blurRadius: 6, color: Colors.black.withOpacity(0.08))],
  ),
  child: Icon(Icons.layers_outlined, size: 22, color: RTColors.inkSoft),
)
```

### `_RTBottomNav`
```dart
Container(
  height: 72,
  decoration: BoxDecoration(
    color: RTColors.bg,
    border: Border(top: BorderSide(color: RTColors.hairSoft)),
  ),
  child: SafeArea(
    top: false,
    child: Row(
      children: [
        _NavItem(icon: Icons.map_outlined, label: 'Mapa', active: true),
        _NavItem(icon: Icons.notifications_outlined, label: 'Eventos', badge: 2),
        _NavItem(icon: Icons.alt_route, label: 'Operações'),
        _NavItem(icon: Icons.person_outline, label: 'Perfil'),
      ],
    ),
  ),
)
```

---

## Pin de coleira (mapa)

Marker customizado:
```dart
Marker(
  width: 44, height: 56,
  point: latLng,
  child: _CollarPin(
    label: 'C-042',
    selected: true,
    status: CollarStatus.online,
  ),
)

class _CollarPin extends StatelessWidget {
  Widget build(...) {
    return Column(children: [
      // halo pulsante quando selected
      if (selected) _PulsingHalo(),
      Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          color: RTColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [BoxShadow(blurRadius: 4, color: Colors.black26)],
        ),
        child: Icon(Icons.gps_fixed, color: Colors.white, size: 14),
      ),
      Container(  // label mono
        margin: EdgeInsets.only(top: 4),
        padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          boxShadow: [BoxShadow(blurRadius: 2, color: Colors.black12)],
        ),
        child: Text(label, style: RTTypography.mono.copyWith(fontSize: 9)),
      ),
    ]);
  }
}
```

---

## Bottom sheet de coleira (`RTCollarSheet`)

Já existe — apenas garantir que o conteúdo siga essa ordem:
1. Drag handle (40×4, cinza, centralizado, top 8)
2. Row: pin verde + nome + badge online + timestamp
3. Subtitle: localização (Quadrante · Área · há X min)
4. Grid 4×1 de telemetrias (bateria, RSSI, GPS sat/HDOP, temp) — valores em mono
5. Row de ações rápidas: Geofence + Conduzir + ⋯

---

## Tokens

- `RTColors.bg` (search, controls, sheet)
- `RTColors.hair` (bordas)
- `RTColors.primary` (pins, FAB)
- `RTColors.accent` (gateway pin)
- `RTRadius.r3` (14 — search), `r5` (24 — sheet)
- `RTSpacing` 4, 8, 12, 16

---

## Critério de aceitação

- [ ] Mapa ocupa 100% da tela (z=0)
- [ ] Search bar + chips translúcidos no topo, sobre o mapa
- [ ] Controles em coluna vertical à direita (3 botões 44×44)
- [ ] Bottom sheet com 3 snap points (10%, 28%, 72%)
- [ ] Pins de coleira com halo quando selecionados
- [ ] Bottom nav persistente com 4 abas
- [ ] FAB extendido "Novo" acima do nav
- [ ] Sem AppBar tradicional — UI é orbital ao mapa
