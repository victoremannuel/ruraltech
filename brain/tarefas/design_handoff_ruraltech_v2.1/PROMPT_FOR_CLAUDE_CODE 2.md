# Prompt para Claude Code

Cole este prompt na conversa do Claude Code, no PR/branch `claude/implement-design-sprint-1-pMOiT`.

---

## PROMPT (copiar daqui ↓)

Você implementou o Sprint 1 do redesign RuralTech v2 com sucesso — design tokens, theme, primitivos `RT*` e domain components estão corretos. Mas as **telas finais** (Login, Dashboard, Geofence, Herding, Profile) não estão batendo visualmente com os mockups da apresentação.

O problema: você implementou os componentes certos, mas a **composição de cada tela** (widget tree, hierarquia, hero/full-bleed/sheets) não reproduz o layout proposto. Não vamos refazer os componentes — eles estão certos. Vamos refazer **somente o `build()` de cada `screen_*.dart`**.

### Material de referência

No diretório `brain/tarefas/design_handoff_ruraltech_v2.1/` há:

- `README.md` — visão geral
- `RuralTech Redesign.html` — **abra no browser para ver os mockups interativos** (seção "05 · Telas")
- `specs/01_login.md` ... `specs/07_profile.md` — **spec pixel-a-pixel de cada tela** com widget tree Flutter já escrita
- `TOKENS.json` — tokens de design (já implementados, só referência)
- `components/*.jsx` — código React dos protótipos (referência visual, não copiar literal)

### Tarefa

Para cada uma das 7 telas, **refatore apenas o método `build()`** (e adicione widgets privados auxiliares no mesmo arquivo) seguindo o widget tree em `specs/NN_*.md`:

1. **`app/lib/screens/login_screen.dart`** → seguir `specs/01_login.md`
   - Adicionar hero topográfico (gradient + CustomPaint pattern + polígono ilustrativo)
   - Estender ou substituir `RTAuthScaffold` para suportar o hero
   
2. **`app/lib/screens/dashboard_screen.dart`** → seguir `specs/02_dashboard.md`
   - **CRÍTICO**: este arquivo tem 86k. Refatore SOMENTE a estrutura visual da tela principal (mapa, search, chips, controls, sheet, FAB, bottom nav). Não toque na lógica de Bluetooth/GPS/onboarding.
   - Mapa full-bleed com Stack
   - Search bar + chips translúcidos no topo
   - Map controls em coluna vertical à direita
   - DraggableScrollableSheet com 3 snap points
   - FAB extendido + bottom nav 4 abas
   
3. **`app/lib/screens/device_details_screen.dart`** → seguir `specs/03_device_details.md` (polimentos)

4. **`app/lib/screens/geofence_screen.dart`** → seguir `specs/04_geofence.md`
   - Tile escuro (Carto Dark Matter)
   - AppBar translúcida com BackdropFilter blur
   - HUD pill flutuante mostrando vértices + km²
   - Banner warn + CTA accent fullwidth

5. **`app/lib/screens/herding_screen.dart`** → seguir `specs/05_herding.md`
   - Converter para PageView com 3 etapas (Coleiras → Área-alvo → Revisar)
   - RTStepper visual no topo
   - Bottom actions com botão primário que cresce conforme avança

6. **`app/lib/screens/events_screen.dart`** → seguir `specs/06_events.md`
   - Header com 2 contadores grandes (Críticos / Informativos)
   - Chips de filtro por severidade
   - Lista de RTEventCard com tonalidade por severidade

7. **`app/lib/screens/profile_screen.dart`** → seguir `specs/07_profile.md`
   - Avatar header (iniciais + nome + email + badge papel)
   - Seção "Filtros do mapa" com 4 linhas
   - Seção "Conta" separada

### Regras de implementação

1. **Use os componentes RT\* existentes** — não crie duplicatas. Se faltar variação, **estenda** o componente existente.
2. **Use `RTColors`, `RTTypography`, `RTSpacing`, `RTRadius`** — zero hex hardcoded, zero TextStyle inline com fontSize.
3. **Não toque em lógica** — modelos, services, providers, navegação ficam como estão. Você só está mexendo na **composição visual** do `build()`.
4. **Não toque nos arquivos `lib/design/`, `lib/components/`** — eles estão corretos.
5. **Para CustomPaint** (pattern topográfico, polígono ilustrativo, seta de movimento), implemente no mesmo arquivo da tela como classe privada `_FooPainter`.
6. **Para o Dashboard**: dada a magnitude do arquivo, comece criando um **novo método** `Widget _buildNewDashboard()` ao lado do build atual, e troque o `build()` para chamá-lo. Mantenha métodos auxiliares antigos para não quebrar refs.
7. **Bottom nav**: criar em `lib/screens/home_shell.dart` se não existir; senão, atualizar.

### Validação

Para cada tela:
- [ ] Compare `build()` com widget tree na spec — devem ser estruturalmente idênticos
- [ ] Compile com `flutter analyze` sem novos warnings
- [ ] Rode no emulador, abra a tela, **screenshote**, compare com a seção correspondente em `RuralTech Redesign.html`

### Ordem de execução sugerida

1. **Profile** (mais simples, valida pattern)
2. **Events** (quase pronto)
3. **Login** (hero + CustomPaint)
4. **Device Details** (polimentos)
5. **Geofence** (tile escuro + HUD)
6. **Herding** (refatoração maior — wizard)
7. **Dashboard** (último, mais complexo — só depois das outras estarem testadas)

### Commits

Faça **um commit por tela** com mensagem padronizada:
```
refactor(screen-XX): align <screen> layout to v2.1 visual handoff

Reproduces widget tree from brain/tarefas/design_handoff_ruraltech_v2.1/specs/XX_<name>.md
```

### Quando terminar

Tire screenshot de cada tela rodando no emulador e cole no PR para revisão visual. Se algum widget tree na spec parecer ambíguo, **pare e pergunte** antes de inventar — é melhor pausar do que inventar layout.
