# Handoff: RuralTech v2 · Redesign Frontend

## Visão geral

Redesign completo do frontend do RuralTech, um app Flutter de operação rural em campo. O produto trabalha com coleiras LoRa, gateways, geofence, telemetria e arrebanhamento em tempo real.

**O que este handoff contém:**
- Análise de problemas na versão atual
- Nova direção visual (design system)
- 7 telas hi-fi redesenhadas com mockups interativos
- Wireframes textuais das 3 telas críticas
- Backlog priorizado em 15 iniciativas (quick wins + estruturais)
- Componentes Flutter reutilizáveis propostos
- Tokens de design (cores, tipografia, spacing, raios, elevação)

---

## Sobre os arquivos de design

Os arquivos neste pacote são **protótipos HTML/React mostrando o produto final desejado** — não são código para copiar. A tarefa é **recriar esses designs em Flutter** usando Material 3 e os padrões já estabelecidos no repositório (`victoremannuel/ruraltech`), elevando UX e UI sem quebrar a lógica operacional existente.

---

## Fidelidade

**High-fidelity (hi-fi).** Os mockups mostram:
- ✅ Layout pixel-perfeito
- ✅ Cores exatas em OKLCH (com conversão para Flutter Color)
- ✅ Tipografia definida (Inter Tight + Inter + JetBrains Mono, tamanhos e pesos)
- ✅ Spacing, raios e elevações precisos
- ✅ Interações (bottom sheets, tap, filtros, fluxos multi-etapa)
- ✅ Estados (loading, erro, vazio, offline, LoRa crítico)

O desenvolvedor deve implementar **pixel-perfeito** usando a paleta, tipografia e componentes propostos.

---

## Contexto de negócio

**Problema atual:**
- `dashboard_screen.dart` tem 3.632 linhas — monolítico, difícil evoluir
- Navegação via `Navigator.push` — sem bottom nav persistente
- ListTiles genéricos em todos os lugares — zero hierarquia
- Mapa não é herói — compete com UI pesada
- Ausência de padrão para operações críticas via LoRa

**Oportunidade:**
- Mapa em tela cheia, UI flutua
- Bottom nav persistente (Mapa / Eventos / Operações / Perfil)
- Componentes modelos reutilizáveis
- Tipografia técnica (mono) para dados
- Confirmação clara antes de comandos irreversíveis

---

## Telas redesenhadas

### 01 · Login
**Arquivo:** `01_login_screen.html` (protótipo interativo)

**Propósito:** Autenticação + primeira impressão do produto

**Layout:**
- Hero topográfico no topo (padrão SVG verde/terra)
- Bottom sheet branco curvo com campos
- Campo email + senha com ícones
- Botões "Entrar" + "Criar conta"
- Hint de modo offline (crucial em campo)

**Componentes:**
- `RTAuthScaffold` — wrapper com hero + sheet
- `RTField` — input com ícone, toggle visibilidade, validação
- `RTButton` — primário (accent), secundário (ghost)

**Cores:**
- Hero: gradiente `oklch(.62 .14 55)` → `oklch(.42 .11 150)`
- Fundo: `oklch(.985 .004 95)` (branco quente)
- Texto: `oklch(.18 .015 150)` (preto esverdeado)

**Tipografia:**
- Display: Inter Tight 700, 28px
- Corpo: Inter 400, 15px

**Interações:**
- Toggle de visibilidade de senha
- Validação inline (email format, senha mín 8 chars)
- Estado loading no botão de entrar
- Link "Criar conta" → tela de signup (não mockada aqui, mas fluxo claro)

---

### 02 · Home / Dashboard com mapa
**Arquivo:** `02_dashboard_screen.html`

**Propósito:** Operação viva — monitorar propriedade, coleiras, gateways

**Layout:**
- Mapa full-bleed (90% da tela)
- AppBar translúcida no topo (search + notificações)
- Chips de filtro rolagem horizontal
- Controles do mapa em coluna vertical à direita (camadas, GPS, bússola)
- Bottom sheet dinâmico com coleira selecionada (peek → full height)
- Bottom nav persistente (4 abas)
- FAB extendido com speed-dial

**Componentes:**
- `RTMapScaffold` — mapa full-bleed + UI orbital
- `RTSearchBar` — busca por propriedade/coleira com autocomplete
- `RTFilterChips` — chips roláveis (Todos, Coleiras, Alertas, Gateways)
- `RTMapControls` — stack vertical (camadas dia/noite, GPS, bússola, legendas)
- `RTCollarSheet` — bottom sheet expansível com telemetria
- `RTMarker` — pin customizável (coleira, gateway, alerta)
- `RTFAB` — FAB extendido com speed-dial (+ Coleira, + Gateway, + Área)
- `TabBar` — 4 abas (Mapa, Eventos, Operações, Perfil)

**Dados no bottom sheet (coleira selecionada):**
```
[●] Coleira 042                [Online] · há 2 min
    Fazenda Doce Vale · A2

[Saúde]  87% bateria    [Telemetria]  RSSI −92 dBm, GPS 8 sat HDOP 1.2, Temp 24°C

[Ações]  [Geofence] [Conduzir] [Log] [⋯]
```

**Cores:**
- Mapa: tile padrão (OSM style)
- Pin coleira: `oklch(.42 .11 150)` (verde floresta)
- Pin gateway: `oklch(.62 .14 55)` (terra accent)
- Pin alerta: `oklch(.72 .15 75)` (amarelo)
- AppBar: `rgba(20,30,25,.7)` translúcido com backdrop blur

**Interações:**
- Busca filtra por ID coleira, propriedade, área
- Chips ativar/desativar — filtra mapa em tempo real
- Tap coleira → abre bottom sheet (peek 180px, swipe up → full)
- Drag handle no sheet permite fechar
- FAB expandido abre speed-dial com 4 opções
- Notificação (sino) abre lista de eventos críticos

---

### 03 · Detalhes da coleira
**Arquivo:** `03_device_details_screen.html`

**Propósito:** Diagnóstico técnico de uma coleira específica

**Layout:**
- AppBar com title + voltar + ações
- Hero card de saúde (verde + breakdown de componentes)
- Card de última posição (grid de coordenadas + satélites + HDOP + RSSI)
- Lista de ações operacionais (geofence, plano de condução, log)

**Componentes:**
- `RTStatusHero` — card verde com status global + grid de subsistemas
- `RTDataGrid` — grid 2-col com valores mono (coordenadas, HDOP, RSSI, etc.)
- `RTActionRow` — linha com ícone + título + descrição + valor + chevron
- `RTBadge` — online status com timestamp relativo

**Hero card (breakdown de saúde):**
```
┌─────────────────────────────────────────┐
│ 🟢 Saúde da coleira                     │
│ Todos sistemas operacionais             │
│                                         │
│ ┌──────┬──────┬──────┬──────┐          │
│ │LoRa  │MPU   │MLX   │Fila  │          │
│ │ OK   │ OK   │ OK   │ OK   │          │
│ └──────┴──────┴──────┴──────┘          │
│ [●] Online · há 2 min                  │
└─────────────────────────────────────────┘
```

**Grid de telemetria:**
```
Latitude          −23.2847°
Longitude         −46.5920°
GPS fix           8 sat · HDOP 1.2
RSSI LoRa         −92 dBm
```

**Ações operacionais:**
```
[🔷] Configurar Geofence
     Desenhar perímetro no mapa
     1.6 km²

[🔷] Plano de Condução
     Arrebanhar para área-alvo
     
[🔷] Log da coleira
     Mensagens recebidas pela matriz
     324
```

**Tipografia:**
- Titles: Inter Tight 600, 15px, uppercase
- Valores técnicos: JetBrains Mono 600, 14px
- Descrições: Inter 400, 12px
- Badges: JetBrains Mono 600, 10px

---

### 04 · Geofence
**Arquivo:** `04_geofence_screen.html`

**Propósito:** Desenhar perímetro virtual para coleira

**Layout:**
- Mapa em tile escuro (melhor em sol)
- AppBar translúcida escura no topo
- HUD flutuante com contador de vértices e km²
- Barra de controles translúcida no fundo (undo, clear)
- CTA accent destacado ("Publicar cerca via LoRa")
- Aviso em amarelo reforçando irreversibilidade

**Componentes:**
- `RTMapNightTile` — tile escuro (OSM variant)
- `RTMapHUD` — badge flutuante com métricas
- `RTPolyEditor` — gestor de vértices (toque + drag)
- `RTConfirmBanner` — aviso de operação LoRa irreversível
- `RTButton` — CTA accent (primário)

**HUD:**
```
┌────────────────────────────────┐
│ ● 6 / 32 vértices · 1.6 km²   │
└────────────────────────────────┘
```

**Controles:**
```
┌────────────────────────────────┐
│ [↶ Desfazer]    [⌫ Limpar]    │
├────────────────────────────────┤
│ [▶ Publicar cerca via LoRa →] │
└────────────────────────────────┘
```

**Aviso:**
```
⚠ Comandos LoRa são irreversíveis. 
  Confirme antes de publicar.
```

**Interações:**
- Toque no mapa = adiciona vértice (numerado)
- Long-press vértice = remove
- Drag vértice = reposiciona
- Snap automático em vértices próximos (threshold 10m)
- Botão "Desfazer" reverte último vértice
- "Limpar" zera tudo com confirmação
- "Publicar" desabilitado até ≥3 vértices

---

### 05 · Arrebanhamento (Herding)
**Arquivo:** `05_herding_screen.html`

**Propósito:** Conduzir rebanho para área-alvo em 3 etapas

**Layout:**
- AppBar com título + voltar
- Stepper visual (3 etapas: Coleiras → Área-alvo → Revisar)
- Mapa com origem (coleiras) + alvo + seta animada
- Bottom sheet com contexto (coleiras selecionadas, aviso, botões)

**Componentes:**
- `RTStepper` — progress visual (3 barras)
- `RTHerdingMap` — mapa com origem/alvo/seta
- `RTChip` — coleiras selecionadas
- `RTConfirmBanner` — aviso em amarelo
- `RTButton` — CTA primário ("Revisar e publicar")

**Stepper (etapa 2/3):**
```
━━━━━━━━━━━━ Coleiras
━━━━━━━━━━━━ Área-alvo      (ativo)
━━━━━━━━━━━━ Revisar
```

**Bottom sheet:**
```
3 coleiras selecionadas · Lote Norte
[🟢C-017] [🟢C-042] [🟢C-088]

⚠ Comandos LoRa são irreversíveis

[Voltar]         [Revisar e publicar →]
```

**Fluxo:**
- **Etapa 1:** Lista de coleiras por lote, checkboxes, com count
- **Etapa 2:** Mapa, desenhar polígono-alvo (reusa `RTPolyEditor`)
- **Etapa 3:** Revisão com coleiras + polígono + estimativa de tempo

---

### 06 · Eventos e Telemetria
**Arquivo:** `06_events_screen.html`

**Propósito:** Feed de eventos críticos e telemetria do sistema

**Layout:**
- AppBar com título
- Header com contadores (2 críticos, 4 informativos)
- Chips de filtro por severidade
- Lista de eventos com scroll
- Cada evento: ícone tonal + título + descrição + timestamp

**Componentes:**
- `RTEventFeed` — lista scrollável
- `RTEventCard` — card com ícone tonal por severidade
- `RTSeverityBadge` — badge com cor (danger/warn/ok/info)
- `RTChip` — filtros por tipo

**Card de evento:**
```
┌────────────────────────────────────┐
│ 🔴 Coleira fora da geofence        │
│    C-042 · Quadrante Norte         │
│    agora                  [● VIVO] │
└────────────────────────────────────┘
```

**Severidades (cor tonal):**
- **Danger** (vermelho): `oklch(.55 .19 25)`
- **Warn** (amarelo): `oklch(.72 .15 75)`
- **Ok** (verde): `oklch(.55 .14 150)`
- **Info** (azul): `oklch(.55 .12 230)`

**Timestamps:** JetBrains Mono 10px

---

### 07 · Perfil / Filtros
**Arquivo:** `07_profile_screen.html`

**Propósito:** Identidade do usuário + filtros de mapa + conta

**Layout:**
- Header com avatar + nome + email + papel (Admin/User)
- Bloco "Filtros do mapa" colapsável (4 linhas com toggles)
- Bloco "Conta" (dados, notificações, sincronização, sobre)

**Componentes:**
- `RTAvatarHeader` — avatar grande + identidade
- `RTFilterGroup` — toggle + label + count + descrição
- `RTToggleRow` — linha com toggle à direita
- `RTCard` — agrupa linhas de menu

**Header:**
```
┌─────────────────────────────────┐
│ [JR] João Ribeiro        [⚙]   │
│      joao@fazenda...            │
│      [Admin]                    │
└─────────────────────────────────┘
```

**Filtros do mapa:**
```
Propriedades    [●●●●●●●] Fazenda Doce Vale        [▶]
Áreas           [●●●●●●●] A2 · Piquete Norte      [▶]
Coleiras        [●●●●●●●] Todas (9)                [▶]
Gateways        [●●●●●●●] Nenhum (0)               [▶]
```

---

## Fluxos auxiliares (não mockados aqui, mas descritos)

### Cadastro de coleira / gateway
- Wizard 3 etapas (identidade → vinculação → confirmação)
- Campo ID LoRa com validação inline
- Preview final antes de salvar

### Seleção de ponto no mapa
- Tela cheia com crosshair fixo central
- Endereço geocoded flutuante
- Botão sticky "Confirmar"

### Edição de polígono / área / propriedade
- Reutiliza `RTPolyEditor`
- HUD com km², perímetro, #vértices
- Lock/unlock de vértices

---

## Design System

### Paleta de cores

#### Neutros (quentes, chroma ≤ 0.015)
```
bg             oklch(.985 .004 95)    — fundo primário
bg-alt         oklch(.965 .008 95)    — superfície alternativa
bg-subtle      oklch(.945 .012 95)    — fundo de seções
hair           oklch(.90 .008 150)    — bordas sutis
ink-soft       oklch(.38 .015 150)    — texto secundário
ink            oklch(.18 .015 150)    — texto primário
```

#### Primário (floresta)
```
primary-soft   oklch(.94 .04 150)     — fundo tonal
primary        oklch(.42 .11 150)     — padrão
primary-deep   oklch(.30 .10 150)     — ênfase
```

#### Accent (terra)
```
accent-soft    oklch(.93 .05 70)      — fundo
accent         oklch(.62 .14 55)      — ênfase
```

#### Feedback / Status
```
ok             oklch(.55 .14 150)     — verde (saudável)
warn           oklch(.72 .15 75)      — amarelo (atenção)
danger         oklch(.55 .19 25)      — vermelho (crítico)
info           oklch(.55 .12 230)     — azul (informação)
```

### Tipografia

**Famílias:**
```
Display:   Inter Tight (weights: 600, 700, 800)
Corpo:     Inter (weights: 400, 500, 600, 700)
Mono/Tech: JetBrains Mono (weights: 400, 500, 600, 700)
```

**Escala de tamanhos:**
```
h1 (display)    56px / 700 / −0.04em   — títulos principais
h2              36px / 700 / −0.03em   — seções
h3              22px / 600 / −0.02em   — subseções
h4 (eyebrow)    12px / 600 / uppercase / 0.08em
body            15px / 400 / 1.55 line-height
small           13px / 500 / 1.45
mono            13px / 600 / family: JetBrains Mono

Valores técnicos (IDs, coords, HDOP):
                13–14px / mono / 600 / −0.01em
```

### Spacing

```
4, 8, 12, 16, 20, 24, 32, 48, 64
```

Padrões:
- Padding tela: `16`
- Padding card: `16`
- Gap itens: `8–12`
- Espaço entre seções: `24–32`

### Raios

```
r1  6px        — chips, badges
r2  10px       — buttons small
r3  14px       — cards, buttons padrão
r4  18px       — hero cards
r5  24px       — bottom sheets, modais
rFull           — circles (avatars, FABs)
```

### Elevação (shadows)

```
sh1  0 1px 2px rgba(0,0,0,.04)          — cards em lista
sh2  0 2px 6px rgba(0,0,0,.08)          — floating controls
sh3  0 4px 12px rgba(0,0,0,.12)         — FAB, bottom sheets
sh4  0 8px 24px rgba(0,0,0,.16)         — modais, sheets expandidos
```

---

## Componentes Flutter propostos

### Primitivos
- `RTButton` — primário, accent, tonal, ghost, danger
- `RTChip` — filtro, ação, com ícone, com dot de status
- `RTBadge` — tone (ok/warn/danger/info/primary/accent)
- `RTField` — input com ícone, toggle, validação inline
- `RTCard` — superfície com sombra/borda, padding
- `RTSheet` — bottom sheet com drag handle
- `RTStepper` — progress visual de múltiplas etapas
- `RTEmptyState` — ícone + título + descrição quando lista vazia
- `RTLoadingSkeleton` — shimmer placeholder

### Mapa
- `RTMapScaffold` — container full-bleed com UI orbital
- `RTMarker` — pin customizável (tipo, status, label)
- `RTMapControls` — stack vertical (camadas, GPS, bússola)
- `RTPolyEditor` — gestor de polígonos (toque, drag, snap)
- `RTMapHUD` — badge translúcido com métricas
- `RTFilterChips` — chips de filtro rápido
- `RTMapTileStyle` — day/night variants

### Domínio (RuralTech)
- `RTCollarSheet` — bottom sheet de coleira selecionada
- `RTHealthHero` — card de saúde com breakdown
- `RTTelemetryGrid` — grid 2-col de dados técnicos
- `RTEventCard` — card de evento com severidade
- `RTGatewayCard` — card de gateway com status
- `RTPropertyPicker` — seletor de propriedade
- `RTConfirmLoRa` — banner de confirmação para LoRa
- `RTAuthScaffold` — wrapper para login com hero

---

## Estado e interações

### Bottom sheet de coleira
- Inicia com peek de 180px
- Drag up / tap → expande para 70% height
- Swipe down / tap fora → fecha
- Contém: identidade → telemetria → ações rápidas

### FAB extendido
- Estado padrão: "🔧 Novo" (label visível)
- Tap → abre speed-dial com 4 opções
- Cada opção navega para fluxo de criação

### Filtros de mapa
- Chips no topo são atalhos (rápido)
- Painel completo em Perfil para granularidade
- Sincronizados em tempo real
- Badge numeric mostra count de filtros ativos

### Operações críticas (LoRa)
- Banner amarelo antes de publicar
- Botão accent destacado, grande
- Após sucesso: toast com opção "Acompanhar"

---

## Padrões de UX específicos RuralTech

### Mapa
- Sempre tela cheia quando em operação
- UI orbital (não compete com canvas)
- Dois tiles: day (padrão) + night (escuro, melhor em sol)

### Marcadores
- Cor por tipo (coleira verde, gateway terra, alerta laranja)
- Forma: pin — exceto alerta que é circular
- Selecionado: halo pulsante + tamanho 1.4×
- Label mono abaixo quando zoom > 15

### Operação LoRa
- Toda operação que vai via LoRa tem confirmação
- Não há "desfazer" — ação é permanente
- Banner amarelo (`warn` tone) no lugar do erro
- Timestamp de publicação em toast

### Telemetria
- Grid 2×2 padrão (bateria, RSSI, GPS, temperatura)
- Valores mono, labels uppercase
- Cor muda só em anormal (bateria < 20%, GPS sem fix)
- Evita ruído quando tudo OK

---

## Backlog priorizado

### Quick wins (Sprints 1–2, 2 semanas)
- **Q1:** Ampliar ColorScheme com tokens OKLCH
- **Q2:** Adicionar fonts (Inter Tight, JetBrains Mono)
- **Q3:** Redesenhar Device Details (cards em vez de ListTiles)
- **Q4:** Eventos com cor por severidade
- **Q5:** Login com hero topográfico

### Estruturais (Sprints 2–4, 3–4 semanas)
- **S1:** Bottom nav persistente (4 abas)
- **S2:** Refatorar dashboard_screen (split em módulos)
- **S3:** Controles de mapa em coluna vertical
- **S4:** Bottom sheet dinâmica para coleira
- **S5:** Arrebanhamento como wizard 3 etapas
- **S6:** Geofence com tile escuro + HUD
- **S7:** FAB extendido com speed-dial

### Longo prazo (Sprint 5+, 2–3 semanas cada)
- **L1:** Offline-first (sincronização visível, retry)
- **L2:** Dark mode completo
- **L3:** Acessibilidade (TalkBack, AAA contrast, text scale)

---

## Regras de implementação

1. **Preserve a lógica operacional** — o que muda é apresentação e navegação, não funcionalidade
2. **Use Material 3** — aproveite Material Design widgets, customize via theme
3. **Reutilize componentes** — não crie um novo widget para cada tela
4. **Tipografia técnica para dados** — IDs LoRa, coordenadas, HDOP sempre em mono
5. **Confirmação para LoRa** — todo comando irreversível passa por aviso + CTA destacado
6. **Mapa é herói** — ele nunca compete com UI, UI orbita ao redor
7. **Touch targets ≥ 44px** — operador em campo pode ter luva
8. **Estados visuais** — desenhada empty state, loading, erro, offline

---

## Próximos passos para o desenvolvedor

1. **Começar por Sprint 1** (tokens + tipografia) — é rápido e unifica o produto
2. **Alinhar com repositório existente** — clone do `victoremannuel/ruraltech`, branch de feature
3. **Implementar em ordem do backlog** — quick wins primeiro (morale) + estruturais depois
4. **Testar em dispositivo real** — sol forte, modo offline, com gestos rápidos
5. **Iterar com product** — a cada 2 semanas, screenshot das telas implementadas

---

## Contato / Dúvidas

Se há ambiguidade em qualquer tela, layout ou comportamento, abra uma issue referenciando esta spec (arquivo `REDESIGN.md` ou `RuralTech Redesign.html`).

Todos os mockups são interativos — abra os arquivos HTML em browser para explorar hover, tap e navegação entre telas.

---

**Versão:** 1.0  
**Data:** abr/2026  
**Baseado em:** `victoremannuel/ruraltech` @ main  
**Contato desenhador:** (referência ao projeto de design original)
