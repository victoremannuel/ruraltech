---
name: design
description: skill de design do app do projeto ruraltech.
---

# SKILL · RuralTech v2 Design System & UI Implementation

> **Quando usar esta skill:** sempre que for solicitado criar, alterar, refatorar ou revisar QUALQUER tela, componente, widget ou elemento visual do app RuralTech (`app/lib/`). Esta skill é a fonte de verdade para o redesign v2.

---

## 1. Princípios fundamentais (NÃO VIOLE)

### 1.1 Hierarquia de fontes de verdade

Quando houver qualquer ambiguidade visual, consulte nesta ordem:

1. **Tokens em `app/lib/design/`** (`colors.dart`, `typography.dart`, `tokens.dart`, `theme.dart`)
2. **Specs em `brain/tarefas/design_handoff_ruraltech_v2.1/specs/NN_*.md`**
3. **Mockups interativos em `brain/tarefas/design_handoff_ruraltech_v2.1/RuralTech Redesign.html`** (abrir no browser)
4. **Componentes RT\* já existentes em `app/lib/components/`**

**Nunca invente cores, tamanhos, raios, espaçamentos, fontes ou tons.** Se algo não existe nos tokens, crie no token (`design/colors.dart` ou `design/tokens.dart`) e use a partir de lá. Hex hardcoded e `TextStyle(fontSize: ...)` inline no meio de telas são proibidos.

### 1.2 Nunca toque em lógica para mudar visual

Os pontos a seguir NUNCA devem ser modificados em uma tarefa de design/UI:
- `app/lib/services/**`
- `app/lib/models/**`
- `app/lib/utils/cloud_compat.dart`
- Schemas Supabase, contratos LoRa, firmware

Se uma mudança visual exigir nova prop/estado/callback, crie wrapper/adapter local na tela ou estenda o componente RT\* — **não modifique a service**.

### 1.3 Componentes RT\* são fonte de verdade

Antes de criar qualquer widget novo, verifique se já existe em:

```
app/lib/components/primitives/   → rt_button, rt_chip, rt_badge, rt_field, rt_card, rt_stepper, rt_fab
app/lib/components/map/          → rt_filter_chips, rt_map_controls
app/lib/components/domain/       → rt_action_row, rt_auth_scaffold, rt_collar_sheet,
                                    rt_confirm_lora, rt_event_card, rt_health_hero,
                                    rt_telemetry_grid
```

**Regras:**
- Se existe e cobre o caso → use diretamente
- Se existe e está perto → **estenda** com nova variant/prop, mantendo retrocompatibilidade
- Se não existe → crie em `components/primitives/` ou `components/domain/` seguindo o padrão dos vizinhos

Nunca duplique lógica de um RT\* dentro de uma screen.

---

## 2. Tokens canônicos

### 2.1 Cores (`RTColors` — `app/lib/design/colors.dart`)

```
NEUTROS (quentes, terra)
  bg          oklch(.985 .004 95)   → fundo principal (creme)
  bgAlt       oklch(.965 .008 95)   → painel, search bar, controls
  bgSubtle    oklch(.945 .012 95)   → fundo de seções/scaffolds
  hairSoft    oklch(.92 .006 150)   → divisor leve
  hair        oklch(.90 .008 150)   → borda padrão
  inkMute     oklch(.58 .010 150)   → texto desabilitado, chevrons
  inkSoft     oklch(.38 .015 150)   → texto secundário/labels
  ink         oklch(.18 .015 150)   → texto primário

PRIMÁRIO (floresta) — ações principais, navegação ativa, pins de coleira
  primarySoft oklch(.94 .04 150)
  primary     oklch(.42 .11 150)
  primaryDeep oklch(.30 .10 150)
  onPrimary   oklch(.99 .003 95)

ACCENT (terra) — operações LoRa críticas, pins gateway, polígonos editáveis
  accentSoft  oklch(.93 .05 70)
  accent      oklch(.62 .14 55)
  onAccent    oklch(.99 .003 95)

FEEDBACK
  ok / okSoft        verde       saúde, online, gateway online
  warn / warnSoft    amarelo     bateria baixa, atenção, banner LoRa
  danger / dangerSoft vermelho   crítico, fora geofence, falha
  info / infoSoft    azul        informativo, sincronização

HERO (login)
  heroStart   accent (terra)
  heroEnd     primary (floresta)
  heroInk     branco quase puro
```

**REGRAS DE USO:**
- Verde `primary` = ação, navegação, pin coleira
- Terra `accent` = comando LoRa, gateway, alerta seletivo
- **NUNCA** use `primary` (verde) em CTA de operação LoRa irreversível — use `accent`
- **NUNCA** use `accent` (terra) em navegação primária

### 2.2 Tipografia (`RTTypography` — `app/lib/design/typography.dart`)

| Estilo | Família | Tamanho | Peso | Tracking | Uso |
|---|---|---|---|---|---|
| `h1` | Inter Tight | 56 | 700 | -0.04em | Display único |
| `h2` | Inter Tight | 36 | 700 | -0.03em | Título de tela (Eventos, Perfil) |
| `h3` | Inter Tight | 22 | 600 | -0.02em | Título de card, AppBar |
| `eyebrow` | Inter | 12 | 600 | +0.08em UPPERCASE | Header de seção |
| `body` | Inter | 15 | 400 | 0 | Texto padrão |
| `bodySmall` | Inter | 13 | 500 | 0 | Subtítulos, descrições |
| `label` | Inter | 14 | 600 | 0 | Botões, chips |
| `mono` | JetBrains Mono | 13 | 600 | -0.01em | IDs LoRa, coords, RSSI, HDOP, timestamps |
| `monoSmall` | JetBrains Mono | 10-11 | 600 | 0 | Badges técnicos, labels de pin |

**REGRAS DE USO:**
- Todo dado técnico (ID coleira, lat/lon, RSSI, HDOP, sat count, RTT, timestamps com formato `dd/MM/yyyy HH:mm:ss`) → **mono**
- Eyebrows são SEMPRE uppercase com tracking +0.08em — não recriar com `.toUpperCase()` em texto comum
- Display fonts (h1/h2/h3) → SEMPRE Inter Tight, NUNCA Inter
- Botões → `label` (Inter 14 600), nunca `body`

### 2.3 Espaçamento (`RTSpacing`)

Escala base 4-multiplo:

```
x1  =  4
x2  =  8
x3  = 12
x4  = 16   ← padding padrão de tela e card
x5  = 20
x6  = 24   ← gap entre seções
x7  = 32
x8  = 48
x9  = 64
```

**REGRAS:**
- Padding interno de tela: `x4` (16) lateral
- Padding interno de card: `x4` (16) all
- Gap entre cards consecutivos: `x3` (12)
- Gap entre seções (eyebrow + content): `x6` (24) acima, `x2` (8) abaixo do eyebrow
- Gap entre campos de formulário: `x4` (16)
- Gap entre label e CTA principal: `x6` (24)
- **Nunca** use múltiplos não-divisíveis por 4 (5, 7, 13, 18px proibidos exceto raios/elevação)

### 2.4 Raios (`RTRadius`)

```
r1   6   → badges, pills pequenos, label de pin no mapa
r2  10   → ícones tonais (40×40 com icon dentro)
r3  14   → cards, buttons padrão, search bar, fields
r4  18   → cards hero
r5  24   → bottom sheets, modais, top de scaffold com hero
rFull 999 → chips, FAB, avatares, status pills
```

### 2.5 Elevação

Sombras suaves, sempre com tinta preta translúcida (nunca colorida):

```
sh1  0 1px 2px  rgba(0,0,0,.04)   → cards em lista (quase nada)
sh2  0 2px 6px  rgba(0,0,0,.08)   → controls flutuantes sobre mapa
sh3  0 4px 12px rgba(0,0,0,.12)   → FAB, popovers
sh4  0 8px 24px rgba(0,0,0,.16)   → bottom sheets expandidos, modais
```

**Cards padrão NÃO devem ter sombra** — só borda `hairSoft`. Sombra é só para floating widgets sobre mapa.

---

## 3. Layout patterns por tipo de tela

### 3.1 Tela com mapa (Dashboard, Geofence, Herding etapa 2, Map Point Picker)

**Estrutura obrigatória:**

```dart
Scaffold(
  extendBodyBehindAppBar: true,        // mapa sobe atrás da AppBar
  appBar: _TranslucentAppBar(...),     // só se necessário; senão omitir AppBar
  body: Stack(
    children: [
      Positioned.fill(child: FlutterMap(...)),  // ─ z=0: mapa full-bleed
      _TopFloatingChrome(),                      // ─ z=1: search/chips/HUD no topo
      Positioned(right: 12, top: 0, bottom: 0,   // ─ z=2: controles à direita
        child: Center(child: _MapControlsStack())),
      _BottomFloatingChrome(),                   // ─ z=3: barra/sheet inferior
    ],
  ),
)
```

**Regras absolutas:**
- Mapa SEMPRE full-bleed (não margem, não card)
- UI orbital — SafeArea, padding 16, shadows sh2/sh3
- Controles em coluna vertical à direita (44×44 cada, gap 8, NUNCA horizontais)
- AppBar sobre mapa = translúcida com `BackdropFilter` blur 12-16
- Tile escuro (Carto Dark Matter) para Geofence (operação focada/sol forte)
- Tile claro (OSM padrão) para Dashboard/Herding/Picker
- Bottom sheet em mapa SEMPRE com radius `r5` no topo, `sh4`, drag handle 40×4 em `inkMute` no topo

### 3.2 Tela de formulário/lista vertical (Login, Profile, Device Details, Add Collar)

**Estrutura:**

```dart
Scaffold(
  backgroundColor: RTColors.bgAlt,   // bgAlt para listas, bg para formulários
  appBar: AppBar(...),               // padrão Material 3 com tema
  body: ListView(  // ou CustomScrollView com slivers
    padding: EdgeInsets.fromLTRB(x4, x3, x4, x8),
    children: [
      RTCard(child: ...),
      SizedBox(height: x3),
      _SectionHeader('TÍTULO DA SEÇÃO'),  // eyebrow
      RTCard(child: Column([row1, Divider, row2, ...])),
    ],
  ),
)
```

**Regras:**
- Background da tela: `bgAlt` (não `bg`) para criar contraste com cards
- Cards têm fundo `bg`, borda `hairSoft`, radius `r3`
- Eyebrow: padding lateral 20, top 24, bottom 8
- Cards consecutivos com 12px de gap
- Divisor dentro de card: `Divider(color: hairSoft, height: 1, indent: 60)` (indent vira do alinhamento do conteúdo, não do ícone)

### 3.3 Tela de fluxo multi-etapa (Herding, Add Collar, Add Gateway)

```dart
Scaffold(
  appBar: AppBar(
    leading: IconButton(
      icon: Icon(_step == 0 ? Icons.close : Icons.arrow_back),
      onPressed: _step == 0 ? () => Navigator.pop(context) : _back,
    ),
    title: Text('Título do fluxo'),
  ),
  body: Column([
    Padding(
      padding: EdgeInsets.fromLTRB(x4, x2, x4, x4),
      child: RTStepper(currentStep: _step, steps: ['A', 'B', 'C']),
    ),
    Expanded(child: PageView(
      controller: _pageCtrl,
      physics: NeverScrollableScrollPhysics(),  // navegação só por botões
      children: [_Step1(), _Step2(), _Step3()],
    )),
    SafeArea(child: _BottomActions()),
  ]),
)
```

**Regras:**
- Step 0 → leading = `Icons.close` (sair do fluxo)
- Step > 0 → leading = `Icons.arrow_back` (voltar uma etapa, NÃO popar)
- PageView SEM swipe horizontal (`NeverScrollableScrollPhysics`) — avanço só por botão
- Bottom actions: na step 0 só "Continuar" full-width; nas demais, "Voltar" (flex 1, ghost) + "Continuar/Publicar" (flex 2, primary/accent)
- Última etapa: CTA é `accent` (não primary), com banner warn `RTConfirmLora` acima

### 3.4 Tela de detalhe técnico (Device Details, Collar Log)

- Hero card no topo com gradient sutil `primarySoft → bg` (vertical, blend 30%)
- Grids de telemetria 2-col com labels uppercase 11px e valores em mono
- Lista de ações operacionais em card único com RTActionRow + Divider entre

---

## 4. Padrões obrigatórios para elementos recorrentes

### 4.1 Bottom Navigation (em telas raiz dentro de `home_shell.dart`)

```dart
Container(
  height: 72,
  decoration: BoxDecoration(
    color: RTColors.bg,
    border: Border(top: BorderSide(color: RTColors.hairSoft)),
  ),
  child: SafeArea(top: false, child: Row([
    _NavItem(icon: Icons.map_outlined, label: 'Mapa',       index: 0),
    _NavItem(icon: Icons.notifications_outlined, label: 'Eventos', index: 1, badge: 2),
    _NavItem(icon: Icons.alt_route, label: 'Operações',     index: 2),
    _NavItem(icon: Icons.person_outline, label: 'Perfil',   index: 3),
  ])),
)
```

- Aba ativa: ícone preenchido (Icons.map em vez de Icons.map_outlined) + label primary + dot 4px abaixo
- Aba inativa: ícone outlined + label inkSoft
- Badge: círculo `danger` 16×16 com count em mono 10px branco, top-right do ícone
- Touch target: cada item ≥ 56×72

### 4.2 AppBar

**Padrão (sobre fundo claro):**
- bg: transparent (theme cuida)
- foreground: `ink`
- title: `h3` 18px
- elevation 0, scrolledUnderElevation 0
- centerTitle: false (alinhado à esquerda)

**Translúcida (sobre mapa):**
```dart
AppBar(
  backgroundColor: Colors.black.withOpacity(0.45),
  foregroundColor: Colors.white,
  elevation: 0,
  flexibleSpace: ClipRect(child: BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
    child: Container(color: Colors.transparent),
  )),
)
```

### 4.3 Botões — quando usar cada variant

| Variant | Cor | Uso |
|---|---|---|
| `primary` | verde primary | Ação principal não-destrutiva: Entrar, Salvar, Continuar, Confirmar coleira |
| `accent` | terra accent | **Operação LoRa irreversível**: Publicar geofence, Publicar arrebanhamento, Enviar comando |
| `ghost` | transparente, texto primary | Ação secundária: Voltar, Cancelar, Criar conta |
| `tonal` | primarySoft | Ação contextual sem urgência: Ver mais, Filtrar |
| `danger` | danger | Destrutivo confirmado: Excluir, Sair |

**Tamanhos:**
- `RTButtonSize.lg` (h=56, padding 24h) → CTA principal de tela
- `RTButtonSize.md` (h=48, padding 20h) → padrão (default)
- `RTButtonSize.sm` (h=36, padding 12h) → inline em cards

**Loading state:** `RTButton(label: '...', loading: true)` — substitui label por spinner 18px no `onPrimary`/`onAccent`. Disable interação durante loading.

**Trailing icon:** botões de ação que avançam fluxo (Entrar, Continuar, Publicar) levam `trailing: Icons.arrow_forward`.

### 4.4 Confirmação LoRa (sempre presente antes de operação irreversível)

```dart
Column([
  RTConfirmLora(
    message: 'Comandos LoRa são irreversíveis. Confirme antes de publicar.',
  ),
  SizedBox(height: x3),
  RTButton(
    variant: RTButtonVariant.accent,
    size: RTButtonSize.lg,
    fullWidth: true,
    label: 'Publicar via LoRa',
    trailing: Icons.arrow_forward,
    onPressed: ...,
  ),
])
```

**REGRA INVIOLÁVEL:** toda operação que envia comando LoRa (geofence, herding, comando direto a coleira/gateway) DEVE:
1. Mostrar `RTConfirmLora` antes do CTA
2. Usar `accent` variant no CTA
3. Após sucesso, mostrar `AppFeedback.success` com texto ações + opção "Acompanhar"
4. Se falhar, `AppFeedback.error` com texto explicativo (não exception raw)

### 4.5 Status & Saúde

| Item | Padrão |
|---|---|
| Online dot | Container 8×8 circle `ok`, com `pulseAnimation` se ativo nos últimos 60s |
| Offline dot | Container 8×8 circle `inkMute` |
| Bateria normal (>30%) | Mono em `ink` |
| Bateria baixa (<30%) | Mono em `warn` + ícone `Icons.battery_alert` |
| Bateria crítica (<10%) | Mono em `danger` + ícone pulsante |
| RSSI bom (>-80) | Mono em `ok` |
| RSSI fraco (<-100) | Mono em `warn` |
| RSSI ruim (<-110) | Mono em `danger` |
| GPS sem fix | Texto "Sem fix" em `warn` |
| GPS com fix | "X sat · HDOP Y.Y" em mono |

### 4.6 Empty states

```dart
Center(child: Column(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    Container(
      width: 80, height: 80,
      decoration: BoxDecoration(
        color: RTColors.bgAlt,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.X_outlined, size: 36, color: RTColors.inkMute),
    ),
    SizedBox(height: x4),
    Text('Título do estado', style: RTTypography.h3),
    SizedBox(height: x2),
    Text('Descrição em 1-2 linhas máx.',
      textAlign: TextAlign.center,
      style: RTTypography.bodySmall.copyWith(color: RTColors.inkSoft)),
    SizedBox(height: x5),
    if (action != null) RTButton(label: action, variant: ghost, ...),
  ],
))
```

NUNCA empty state com 1 linha de texto cinza no meio da tela. NUNCA sem ícone tonal.

### 4.7 Loading states

- Tela inteira: skeleton com shimmer (não spinner centralizado)
- Em card: shimmer no campo
- Em botão: `loading: true` (spinner inline)
- Em pull-to-refresh: `RefreshIndicator` com `color: RTColors.primary`

### 4.8 Pins no mapa

| Tipo | Cor | Forma | Tamanho |
|---|---|---|---|
| Coleira online | `primary` (verde) | Círculo c/ borda branca 2.5px + sombra | 30×30 + label mono abaixo |
| Coleira offline | `inkMute` | Círculo c/ borda branca | 30×30 |
| Coleira selecionada | `primary` + halo pulsante 60×60 | Mesma + halo | 1.4× scale |
| Gateway | `accent` (terra) | Quadrado arredondado r2 | 32×32 |
| Alerta | `danger` | Círculo + ícone ⚠ branco | 28×28 |
| Origem (herding) | `primary` outline | Círculo vazado tracejado | 36×36 |
| Alvo (herding) | `accent` 18% fill | Polígono | variável |

Label do pin (quando zoom > 14):
```dart
Container(
  margin: EdgeInsets.only(top: 4),
  padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(r1),
    boxShadow: [BoxShadow(blurRadius: 2, color: Colors.black12)],
  ),
  child: Text('C-042', style: RTTypography.monoSmall.copyWith(fontSize: 9)),
)
```

### 4.9 Polígonos editáveis

- Preenchimento: cor relevante a 18% opacidade (`accent` para alvo herding, `primary` para área de propriedade, `danger` para zona de exclusão)
- Borda: tracejada 2px branca/cor com gap 4
- Vértices: círculo branco 14×14, borda cor 2px, número mono interno 9px
- Long-press vértice → confirma remoção
- Drag vértice → reposiciona com snap a 10m de outros vértices
- Mínimo 3 vértices para fechar (CTA disabled abaixo disso)

### 4.10 Bottom Sheets

```dart
DraggableScrollableSheet(
  initialChildSize: 0.28,
  minChildSize: 0.10,
  maxChildSize: 0.72,
  snap: true,
  snapSizes: [0.10, 0.28, 0.72],
  builder: (ctx, scrollCtrl) => Container(
    decoration: BoxDecoration(
      color: RTColors.bg,
      borderRadius: BorderRadius.vertical(top: Radius.circular(r5)),
      boxShadow: [BoxShadow(blurRadius: 24, color: Colors.black.withOpacity(0.12))],
    ),
    child: Column([
      // Drag handle
      Center(child: Container(
        width: 40, height: 4,
        margin: EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: RTColors.inkMute.withOpacity(0.4),
          borderRadius: BorderRadius.circular(rFull),
        ),
      )),
      Expanded(child: SingleChildScrollView(controller: scrollCtrl, child: ...)),
    ]),
  ),
)
```

### 4.11 Dialogs

**Sempre AlertDialog Material 3 com:**
- title em h3
- content em body
- actions: ghost cancel à esquerda + primary/danger confirm à direita
- Para confirmação destrutiva: confirm em `danger` variant
- Para LoRa: usar `RTConfirmLora` dentro do content

---

## 5. Glossário visual (anti-AI-slop)

### NUNCA fazer:
- ❌ Gradient de marca em fundo de card (manchas verde-laranja-roxo)
- ❌ Border-left de 4px colorida em "alert cards" (web design 2018)
- ❌ Emojis dentro de UI (🟢🔴⚠️) — use Icons.* + cor de token
- ❌ `BoxShadow` colorida (`color: primary.withOpacity(0.3)`)
- ❌ Ícones desenhados em SVG inline criativo — use Material Icons ou placeholders
- ❌ Glassmorphism em superfícies sólidas (só sobre mapa)
- ❌ Botões com gradient
- ❌ Backgrounds geométricos atrás de cards normais
- ❌ Roxos, azuis-vibrantes, magenta — não estão na paleta
- ❌ Inter como display font — display é SEMPRE Inter Tight

### SEMPRE fazer:
- ✅ Bordas finas `hairSoft` em cards
- ✅ Mono em todo dado técnico
- ✅ AppBar elevation 0
- ✅ Touch targets ≥ 44px (com luva, em campo)
- ✅ Pelo menos 1 confirmação para LoRa
- ✅ `bgAlt` ou `bgSubtle` em scaffold de listas (cria contraste com cards)
- ✅ Eyebrow uppercase para abrir seção
- ✅ Padding lateral 16 padrão de tela

---

## 6. Workflow para qualquer alteração

### Antes de mexer

1. **Ler a spec correspondente** em `brain/tarefas/design_handoff_ruraltech_v2.1/specs/NN_*.md` se existir
2. **Abrir mockup interativo** `RuralTech Redesign.html` no browser para a seção da tela
3. **Listar componentes RT\*** já disponíveis para essa tela
4. **Identificar tokens faltantes** — se necessário adicionar, fazê-lo em `design/colors.dart` ou `design/tokens.dart` ANTES de usar
5. **Confirmar que mudança é só visual** — se exigir nova service/model, parar e perguntar

### Durante

- Cada widget complexo da tela vira `class _FooSection extends StatelessWidget` privada no mesmo arquivo (`_LoginHero`, `_DashboardChips`, etc.)
- Painters customizados viram `class _FooPainter extends CustomPainter` privados no mesmo arquivo
- Sem hex hardcoded; sem TextStyle inline; sem espaçamento hardcoded fora da escala 4-base
- Comentários em pt-BR curtos explicando seções, não cada linha

### Depois

- `flutter analyze` sem novos warnings
- Compare visualmente com mockup (screenshot do emulador vs PNG da spec)
- Verificar checklist de cada spec
- Verificar `BUTTON_WIRING_PLAN.md` se mexeu em interatividade — todos os botões ligados a callbacks reais ou stubs marcados explicitamente
- Commit message: `refactor(ui-<screen>): <que mudou> [v2 design]`

---

## 7. Exceções e edge cases

### 7.1 Estado offline / sem gateway

- Banner persistente abaixo da AppBar: `Container(color: warnSoft, padding: 12, child: Row([Icons.wifi_off, "Operando offline. Sincroniza ao voltar online."]))`
- Botões de operação LoRa ficam disabled com tooltip "Sem gateway disponível"
- Pull-to-refresh tenta reconexão

### 7.2 Modo escuro

Não implementado em v2. Se solicitado, NÃO usar `Brightness.dark` direto — definir tokens dark explícitos primeiro em `colors.dart` (`bgDark`, `inkDark`, etc.).

### 7.3 Acessibilidade

- Toda imagem decorativa com `Semantics(label: '')` ou `excludeSemantics`
- Todo IconButton com `tooltip:` em pt-BR
- Contraste mínimo AA — se token `inkSoft` em fundo `bg` falha em algum caso, usar `ink`
- TextScale: layouts devem aguentar `MediaQuery.textScaleFactor: 1.3` sem quebrar (use `Flexible`/`Expanded`, evite Heights fixos em texto)

### 7.4 Teclado (formulários)

- `Scaffold(resizeToAvoidBottomInset: true)` (default)
- `SingleChildScrollView` em vez de `Column` quando há mais de 2 fields
- `TextInputAction.next` em todos exceto último (que recebe `done`)
- Autofill hints em campos comuns (`AutofillHints.email`, `password`)

### 7.5 Português

- Todo texto da UI em pt-BR
- Datas em formato `dd/MM/yyyy HH:mm:ss`
- Números com vírgula decimal e ponto de milhar (`24,5°C`, `1.234 m`)
- Coordenadas: 6 casas decimais com sinal (`−23.284731, −46.592088`)
- Termos técnicos (LoRa, RSSI, HDOP, GPS, NMEA, UART, I2C) em uppercase

---

## 8. Checklist obrigatório antes de marcar tarefa como pronta

```
[ ] Tokens RTColors usados — zero hex hardcoded fora de design/colors.dart
[ ] Tipografia RTTypography usada — zero TextStyle(fontSize:) inline
[ ] Spacing RTSpacing usado — zero números arbitrários fora da escala 4-base
[ ] Raios RTRadius usados — zero BorderRadius.circular(N) com N inventado
[ ] Componentes RT* reutilizados — sem duplicação
[ ] Touch targets ≥ 44px verificados
[ ] Operações LoRa têm RTConfirmLora + CTA accent
[ ] Empty state desenhado (não 1 linha cinza)
[ ] Loading state desenhado (skeleton/spinner inline)
[ ] Português em toda UI
[ ] flutter analyze sem novos warnings
[ ] Visual comparado lado-a-lado com mockup ou spec
```

---

## 9. Quando a skill não cobre

Se algo não está coberto aqui:
1. Olhe se existe componente RT\* parecido — extraia o padrão dele
2. Olhe a spec da tela em `specs/NN_*.md`
3. Olhe o mockup HTML
4. Se ainda em dúvida, **pare e pergunte** com proposta concreta — `"Para X não há padrão definido. Proponho Y porque Z. OK?"` é melhor que inventar.

Inventar layout/cor/espaçamento sem base é proibido.

---

## 10. Resumo em 10 linhas (cole na memória)

1. **Tokens primeiro** — RTColors, RTTypography, RTSpacing, RTRadius. Zero hex/inline.
2. **Componentes RT\*** — reutilize ou estenda; nunca duplique.
3. **Verde = navegação. Terra = LoRa irreversível.** Nunca troque.
4. **Mono = dados técnicos.** IDs, coords, timestamps, RSSI, HDOP.
5. **Mapa = full-bleed. UI = orbital.** Nunca mapa em card.
6. **LoRa SEMPRE com `RTConfirmLora` + CTA accent.**
7. **Eyebrow uppercase abre seção. Cards têm borda hair, sem sombra.**
8. **Touch ≥ 44. Português. flutter analyze limpo.**
9. **Não toque em services/models para tarefa de UI.**
10. **Em dúvida → spec → mockup → pergunte. Não invente.**
