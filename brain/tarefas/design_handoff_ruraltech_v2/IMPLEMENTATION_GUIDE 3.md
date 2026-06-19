# Guia de implementação · RuralTech v2

## Checklist de desenvolvimento por tela

### Sprint 1: Fundações (2 semanas)

- [x] **Q1: Tokens de cor** ✅ commit `2b82b70a`
  - `lib/design/colors.dart` com RTColors + conversão OKLCH
  - Integrado ao ThemeData

- [x] **Q2: Tipografia** ✅ commit `2b82b70a`
  - Inter Tight + JetBrains Mono em `pubspec.yaml`
  - `lib/design/typography.dart` com RTTypography

- [x] **Q3: Device Details** ✅ commit `df5e5f4b`
  - RTHealthHero, RTTelemetryGrid, RTActionRow implementados
  - `device_details_screen.dart` redesenhado com tokens v2

- [x] **Q4: Eventos** ✅ commit `df5e5f4b`
  - RTEventCard com severidade, filtros por chip, empty state

- [x] **Q5: Login** ✅ commit `df5e5f4b`
  - RTAuthScaffold com hero topográfico, RTField, hint offline

---

### Sprint 2: Navegação (2 semanas)

- [x] **S1: Bottom Navigation persistente** ✅ commit `df5e5f4b`
  - HomeShell com NavigationBar M3, 4 abas preservando state

- [x] **S2a/S2b: Dashboard + RTCollarSheet** ✅ commits `df5e5f4b` + `8ce9ca31`
  - RTCollarSheet integrada no tap de marker
  - RTFilterChips, RTMapControls, RTFAB speed-dial implementados

- [x] **S3: Controles do mapa em coluna vertical** ✅ commit `df5e5f4b`
  - RTMapControls com stack vertical à direita

- [x] **S4: Bottom sheet de coleira** ✅ commit `8ce9ca31`
  - DraggableScrollableSheet com peek 180px integrada

---

### Sprint 3: Operações (2 semanas)

- [x] **S5: Arrebanhamento wizard** ✅ commit `15879c97`
  - PageView 3 páginas com RTStepper no AppBar
  - Etapa 1: seletor propriedade + lista coleiras checkbox + status dot
  - Etapa 2: mapa com HUD vértices/área + controls undo/clear
  - Etapa 3: revisão + RTConfirmLoRa + botão publicar accent
  - Novos primitivos: RTChip, RTStepper, RTConfirmLoRa

- [x] **S6: Geofence** ✅ commit `fdb2739f`
  - Tile escuro, RTMapHUD com contador, controles undo/clear/publicar
  - RTConfirmBanner integrado

- [ ] **S7: FAB com speed-dial**
  - FAB extendido "🔧 Novo"
  - Speed-dial com 4 opções (Coleira, Gateway, Área, Propriedade)
  - Transição suave
  - Cada opção navega para fluxo de criação

---

### Sprint 4: Perfil e complementos (2 semanas)

- [ ] **Redesenhar Perfil**
  - Header com avatar + identidade
  - Bloco "Filtros do mapa" com 4 linhas + toggle
  - Bloco "Conta" (dados, notificações, sincronização)
  - Colapsível para reduzir altura

- [ ] **Fluxos de cadastro**
  - Coleira: wizard 3 etapas
  - Gateway: wizard 3 etapas
  - Validação inline em ID LoRa (numérico positivo)
  - Preview final

- [ ] **Seleção de ponto**
  - Mapa full-bleed com crosshair fixo
  - Endereço geocoded flutuante
  - Botão sticky "Confirmar"

- [ ] **Log da coleira**
  - Terminal-style (fundo escuro)
  - Timestamp + tipo + payload em mono
  - Filtro por tipo + range de tempo
  - Syntax highlight leve para dados

---

## Estrutura de componentes proposta

```
lib/
├── design/
│   ├── colors.dart          (RTColors)
│   ├── typography.dart      (RTTextTheme)
│   └── tokens.dart          (spacing, radius, elevation)
│
├── components/
│   ├── primitives/
│   │   ├── rt_button.dart
│   │   ├── rt_chip.dart
│   │   ├── rt_badge.dart
│   │   ├── rt_field.dart
│   │   ├── rt_card.dart
│   │   ├── rt_sheet.dart
│   │   ├── rt_stepper.dart
│   │   ├── rt_empty_state.dart
│   │   └── rt_loading_skeleton.dart
│   │
│   ├── map/
│   │   ├── rt_map_scaffold.dart
│   │   ├── rt_marker.dart
│   │   ├── rt_map_controls.dart
│   │   ├── rt_poly_editor.dart
│   │   ├── rt_map_hud.dart
│   │   ├── rt_filter_chips.dart
│   │   └── rt_map_tile_style.dart
│   │
│   └── domain/
│       ├── rt_collar_sheet.dart
│       ├── rt_health_hero.dart
│       ├── rt_telemetry_grid.dart
│       ├── rt_event_card.dart
│       ├── rt_gateway_card.dart
│       ├── rt_property_picker.dart
│       ├── rt_confirm_lora.dart
│       └── rt_auth_scaffold.dart
│
├── screens/
│   ├── login_screen.dart       (redesenhada)
│   ├── home_screen.dart        (novo wrapper com bottom nav)
│   ├── dashboard_screen.dart   (refatorada)
│   ├── events_screen.dart      (redesenhada)
│   ├── profile_screen.dart     (redesenhada)
│   ├── device_details_screen.dart (redesenhada)
│   ├── geofence_screen.dart    (redesenhada)
│   ├── herding_screen.dart     (convertida para wizard)
│   └── ...others
```

---

## Checklist de testes

Para cada tela implementada:

- [ ] **Visual**
  - [ ] Cores correspondem aos tokens
  - [ ] Tipografia em escalas corretas
  - [ ] Spacing segue escala 4-based
  - [ ] Touch targets ≥ 44px

- [ ] **Responsividade**
  - [ ] Tela pequena (5.5")
  - [ ] Tela média (6.1")
  - [ ] Tela grande (6.7")

- [ ] **Interatividade**
  - [ ] Tap registra (feedback háptico se possível)
  - [ ] Long-press funciona onde esperado
  - [ ] Drag smooth sem lag
  - [ ] Loading states visíveis

- [ ] **Offline**
  - [ ] Hint de offline aparece em login
  - [ ] Dados cached carregam
  - [ ] Retry visível para operações LoRa

- [ ] **Acessibilidade**
  - [ ] Labels descritivos em TalkBack
  - [ ] Contraste WCAG AA mínimo
  - [ ] Texto escalável sem quebra

---

## Notas de implementação

### Colors: Conversão OKLCH → Flutter

```dart
// OKLCH para Dart Color
Color oklch(double lightness, double chroma, double hue) {
  // Conversão matemática OKLCH → sRGB
  // Implementação pode usar biblioteca como "oklch_to_rgb"
  // ou conversão manual via OKLab
  return Color.fromARGB(255, r, g, b);
}

// Exemplo
final bgColor = oklch(0.985, 0.004, 95);
```

### Tipografia: Material 3 customizado

```dart
final textTheme = GoogleFonts.interTightTextTheme(
  TextTheme(
    displayLarge: GoogleFonts.interTight(fontSize: 56, fontWeight: FontWeight.w700),
    // ... resto da escala
  ),
).apply(
  bodyColor: RTColors.ink,
  displayColor: RTColors.ink,
);
```

### Bottom Navigation com state preservation

```dart
class HomeScreen extends StatefulWidget {
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final List<Widget> _pages = [
    DashboardScreen(),
    EventsScreen(),
    OperationsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageStorage(
        bucket: PageStorageBucket(),
        child: _pages[_selectedIndex],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (idx) => setState(() => _selectedIndex = idx),
        // items...
      ),
    );
  }
}
```

---

## Performance

- Lazy load imagens no mapa (especialmente em dispositivos antigos)
- Memoize builders de listas longas
- Debounce busca em 300ms
- Usar `const` para widgets que não mudam

---

## Links úteis

- [Material 3 Flutter](https://m3.material.io/)
- [FlutterMap docs](https://docs.fleaflet.dev/)
- [Google Fonts Flutter](https://pub.dev/packages/google_fonts)
- [OKLCH color converter](https://oklch.com/)

---

## Próxima fase

Após implementação de todos os sprints, avaliar:
- Performance em dispositivo real (4G, 3G, offline)
- Usabilidade em campo (sol, luva, reação do operador)
- Dados de telemetria (RSSI, GPS, bateria) renderizam corretamente
- Feedback de LoRa (publicar cerca, arrebanhamento) é claro e confirmado

Iterar conforme feedback de UX testing.
