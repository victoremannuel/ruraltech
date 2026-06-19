# 05 · Herding (Arrebanhamento) — Spec

**Arquivo Flutter:** `app/lib/screens/herding_screen.dart` (49k bytes — refatorar como wizard)  
**Status:** Falta wizard 3 etapas, mapa com origem→alvo, sheet de revisão.

---

## Estrutura: PageView de 3 páginas

```dart
class HerdingScreen extends StatefulWidget {
  @override State<HerdingScreen> createState() => _HerdingScreenState();
}

class _HerdingScreenState extends State<HerdingScreen> {
  final _pageCtrl = PageController();
  int _step = 0;
  Set<String> _selectedCollars = {};
  List<LatLng> _targetPolygon = [];
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(_step == 0 ? Icons.close : Icons.arrow_back),
          onPressed: () => _step == 0 ? Navigator.pop(context) : _back(),
        ),
        title: Text('Arrebanhamento'),
      ),
      body: Column(children: [
        // Stepper visual (3 barras horizontais)
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: RTStepper(
            currentStep: _step,
            steps: ['Coleiras', 'Área-alvo', 'Revisar'],
          ),
        ),
        
        Expanded(
          child: PageView(
            controller: _pageCtrl,
            physics: NeverScrollableScrollPhysics(),
            children: [
              _StepCollars(
                selected: _selectedCollars,
                onChanged: (s) => setState(() => _selectedCollars = s),
              ),
              _StepTarget(
                polygon: _targetPolygon,
                onChanged: (p) => setState(() => _targetPolygon = p),
              ),
              _StepReview(
                collars: _selectedCollars,
                polygon: _targetPolygon,
                onPublish: _publish,
              ),
            ],
          ),
        ),
        
        // Barra inferior com botões
        SafeArea(child: _BottomActions(...)),
      ]),
    );
  }
}
```

---

## Etapa 1: Coleiras (lista + filtros)

```
[Filtro: Todas ▾] [Filtro: Lote Norte ▾]
─────────────────────────────────
[☑] [🟢] C-017  Lote Norte · A2
[☑] [🟢] C-042  Lote Norte · A2  
[☑] [🟢] C-088  Lote Norte · B1
[☐] [🟢] C-091  Lote Sul · A1
...
─────────────────────────────────
3 coleiras selecionadas
```

Use `CheckboxListTile` substituído por `RTToggleRow` customizado.

---

## Etapa 2: Área-alvo (mapa)

```
[mapa com:]
- ◯ origem: cluster das coleiras selecionadas (verde)
- ─→ seta tracejada animada (origem → centro do alvo)
- ◈ área-alvo (polígono editável, accent 18% fill)

Toolbar inferior:
[↶] [⌫]  ← undo, clear
```

Reutilizar `RTPolyEditor` (se já existe) ou implementar seguindo o mesmo padrão de Geofence.

Animação da seta: `AnimationController` repetindo, traço tracejado com `dashOffset` mudando.

---

## Etapa 3: Revisar (sheet de confirmação)

```
3 coleiras · Lote Norte
[🟢C-017] [🟢C-042] [🟢C-088]   ← chips com IDs

ÁREA-ALVO
0.42 km² · 6 vértices · ~120m de distância

⚠ Comandos LoRa são irreversíveis
   Após publicar, as coleiras receberão pulsos
   sonoros guiando o rebanho até a área alvo.

[Voltar]    [▶ Publicar arrebanhamento via LoRa]
```

---

## Bottom actions (cresce conforme avança)

```dart
Widget _BottomActions(int step) {
  return Container(
    padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
    decoration: BoxDecoration(
      color: RTColors.bg,
      border: Border(top: BorderSide(color: RTColors.hairSoft)),
    ),
    child: Row(children: [
      if (step > 0) Expanded(
        flex: 1,
        child: RTButton(label: 'Voltar', variant: RTButtonVariant.ghost, onPressed: _back),
      ),
      if (step > 0) SizedBox(width: 12),
      Expanded(
        flex: step == 0 ? 1 : 2,  // cresce conforme avança
        child: RTButton(
          label: step < 2 ? 'Continuar' : 'Publicar arrebanhamento',
          variant: step == 2 ? RTButtonVariant.accent : RTButtonVariant.primary,
          trailing: Icons.arrow_forward,
          onPressed: _canAdvance ? _next : null,
        ),
      ),
    ]),
  );
}
```

---

## Critério

- [ ] PageView com 3 páginas, sem swipe horizontal (NeverScrollable)
- [ ] RTStepper visual no topo refletindo `_step`
- [ ] Etapa 1: lista de coleiras com toggle, count no rodapé
- [ ] Etapa 2: mapa com poly editor + seta animada origem→alvo
- [ ] Etapa 3: sheet de revisão com chips, métricas, banner warn
- [ ] Bottom actions: botão primário cresce conforme avança (flex 1→2)
- [ ] Etapa 3: CTA é `accent` (terra), não primary (verde)
