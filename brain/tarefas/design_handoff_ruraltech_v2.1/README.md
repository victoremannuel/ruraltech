# RuralTech v2.1 — Handoff Visual

**Branch base:** `claude/implement-design-sprint-1-pMOiT`  
**Caminho no repo:** `brain/tarefas/design_handoff_ruraltech_v2.1/`  
**Objetivo:** Refazer as **telas finais** para baterem pixel-a-pixel com os mockups da apresentação. Os componentes RT* já estão corretos — falta a **composição de cada tela**.

---

## Como ler este handoff

Cada tela tem:
1. **Screenshot do mockup** (imagem de referência — `screens/NN_*.png`)
2. **Widget tree Flutter exata** (estrutura que a tela deve ter)
3. **Anotações pixel-a-pixel** (medidas, cores por token, pesos de fonte)
4. **Diff vs implementação atual** (o que está faltando ou errado)

---

## Arquivos

```
design_handoff_ruraltech_v2.1/
├── README.md                    ← este arquivo
├── PROMPT_FOR_CLAUDE_CODE.md    ← prompt pronto para usar
├── TOKENS.json                  ← tokens de design (cópia da v2)
├── screens/
│   ├── 01_login.png
│   ├── 02_dashboard.png
│   ├── 03_device_details.png
│   ├── 04_geofence.png
│   ├── 05_herding.png
│   ├── 06_events.png
│   ├── 07_profile.png
│   └── all_screens_overview.png
└── specs/
    ├── 01_login.md
    ├── 02_dashboard.md
    ├── 03_device_details.md
    ├── 04_geofence.md
    ├── 05_herding.md
    ├── 06_events.md
    └── 07_profile.md
```

---

## Princípio operacional

**O objetivo não é refazer os componentes RT\*** — eles estão corretos.  
**O objetivo é refazer a composição de cada tela** para usar esses componentes na ordem, hierarquia e proporção exatas dos mockups.

Para cada tela:
1. Abra `screens/NN_*.png` lado a lado com a tela atual
2. Compare elemento por elemento
3. Refatore o `build()` para bater com o widget tree em `specs/NN_*.md`
4. Não invente — siga a spec

---

## Resumo das 7 telas

| # | Tela | Arquivo Flutter | Status atual | Ação |
|---|------|-----------------|--------------|------|
| 01 | Login | `login_screen.dart` | Estrutura existe, falta hero topográfico SVG no fundo | Adicionar SVG pattern + polígono ilustrativo no `RTAuthScaffold` |
| 02 | Dashboard | `dashboard_screen.dart` | Refatoração estrutural não feita | Mapa full-bleed + UI orbital + bottom sheet dinâmica |
| 03 | Device Details | `device_details_screen.dart` | Próximo do mockup | Ajustar spacing, hero card precisa do gradient verde-floresta |
| 04 | Geofence | `geofence_screen.dart` | Falta tile escuro + HUD translúcido | Tile dark + HUD pill + CTA accent destacado |
| 05 | Herding | `herding_screen.dart` | Falta wizard 3 etapas | PageView + RTStepper visual + sheet de revisão |
| 06 | Events | `events_screen.dart` | Quase certo | Header com contadores grandes + chips de severidade |
| 07 | Profile | `profile_screen.dart` | Layout não bate | Avatar header + bloco filtros + bloco conta |

---

## Critério de aceitação

- [ ] Cada tela bate visualmente com seu mockup PNG (≥90% similaridade)
- [ ] Spacing usa `RTSpacing` (4-based scale)
- [ ] Cores usam tokens de `RTColors` (zero hex hardcoded)
- [ ] Tipografia usa `RTTypography` (Inter Tight / Inter / JetBrains Mono)
- [ ] Touch targets ≥ 44px
- [ ] Componentes RT* são reutilizados — não duplique lógica
