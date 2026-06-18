# 04 · Geofence — Spec

**Arquivo Flutter:** `app/lib/screens/geofence_screen.dart`  
**Status:** Falta tile escuro + HUD translúcido + CTA destacado.

---

## Layout

```
┌─────────────────────────────────────┐
│ [status bar — branca sobre escuro] │
│ [← Geofence · C-042       ↻  ⋯  ]  │ AppBar TRANSLÚCIDA escura
├─────────────────────────────────────┤
│                                     │
│   [● 6 / 32 vértices · 1.6 km²]    │ ← HUD pill, top-center
│                                     │   bg: rgba(20,30,25,.7)
│                                     │   blur backdrop
│                                     │
│       MAPA ESCURO (night tile)      │
│                                     │
│       ◉─◉                           │
│      ╱   ╲                          │
│     ◉     ◉      ← polígono        │
│      ╲   ╱          editável       │
│       ◉─◉           vértices       │
│                     numerados      │
│                                     │
│                                     │
├─────────────────────────────────────┤
│ ┌─────────────────────────────────┐ │ ← barra translúcida
│ │ [↶ Desfazer]    [⌫ Limpar]     │ │   actions secundárias
│ └─────────────────────────────────┘ │
│                                     │
│ ⚠ Comandos LoRa são irreversíveis  │ ← banner warn
│                                     │
│ [ ▶ Publicar cerca via LoRa    → ] │ ← CTA accent ALT
└─────────────────────────────────────┘
```

---

## Pontos críticos

### 1. Tile escuro
Usar `flutter_map` com `urlTemplate` apontando para um tile dark (Carto Dark Matter ou Stadia AlidadeSmoothDark):
```dart
TileLayer(
  urlTemplate: 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
  userAgentPackageName: 'br.com.ruraltech.app',
)
```

### 2. AppBar translúcida
```dart
appBar: AppBar(
  backgroundColor: Colors.black.withOpacity(0.45),
  foregroundColor: Colors.white,
  elevation: 0,
  surfaceTintColor: Colors.transparent,
  iconTheme: IconThemeData(color: Colors.white),
  titleTextStyle: RTTypography.h3.copyWith(color: Colors.white, fontSize: 17),
  flexibleSpace: ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Container(color: Colors.transparent),
    ),
  ),
),
```
Usar `extendBodyBehindAppBar: true` para o mapa correr atrás.

### 3. HUD pill
Floating widget no top-center, abaixo da AppBar:
```dart
Positioned(
  top: kToolbarHeight + MediaQuery.of(context).padding.top + 12,
  left: 0, right: 0,
  child: Center(child: _HudPill(vertices: 6, maxVertices: 32, areaKm2: 1.6)),
)

class _HudPill extends StatelessWidget {
  Widget build(...) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(
                color: RTColors.accent, shape: BoxShape.circle,
              )),
              SizedBox(width: 8),
              Text('6 / 32 vértices · 1.6 km²',
                style: RTTypography.mono.copyWith(
                  color: Colors.white, fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### 4. Barra de ações secundárias (bottom)
Translúcida sobre o mapa, com botões fantasma:
```dart
Container(
  margin: EdgeInsets.symmetric(horizontal: 16),
  padding: EdgeInsets.all(8),
  decoration: BoxDecoration(
    color: Colors.black.withOpacity(0.5),
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: Colors.white.withOpacity(0.12)),
  ),
  child: Row(children: [
    Expanded(child: _GhostBtn(icon: Icons.undo, label: 'Desfazer')),
    SizedBox(width: 8),
    Expanded(child: _GhostBtn(icon: Icons.delete_outline, label: 'Limpar')),
  ]),
)
```

### 5. Banner warn + CTA
Logo abaixo da barra, dentro de `SafeArea(bottom: true)`:
```dart
Padding(
  padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
  child: Column(children: [
    RTConfirmLora(message: 'Comandos LoRa são irreversíveis'),
    SizedBox(height: 12),
    RTButton(
      label: 'Publicar cerca via LoRa',
      variant: RTButtonVariant.accent,
      size: RTButtonSize.lg,
      fullWidth: true,
      trailing: Icons.arrow_forward,
      onPressed: vertices.length >= 3 ? _publish : null,
    ),
  ]),
)
```

---

## Polígono editável

- Vértices em círculos brancos 12px com número interno em mono 9px
- Lado conectando vértices: linha branca tracejada 2px (dash 6, gap 4)
- Preenchimento interno: `accent` 18% opacidade
- Long-press vértice → remove
- Drag vértice → reposiciona

---

## Critério

- [ ] Tile escuro carregado
- [ ] AppBar translúcida com blur
- [ ] HUD pill flutuante mostrando contagem + km²
- [ ] Barra de actions secundárias translúcida na base
- [ ] Banner warn + CTA accent fullwidth
- [ ] CTA desabilitado se < 3 vértices
- [ ] `extendBodyBehindAppBar: true` para mapa subir atrás da AppBar
