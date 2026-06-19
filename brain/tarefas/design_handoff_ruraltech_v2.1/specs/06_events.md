# 06 · Events — Spec

**Arquivo Flutter:** `app/lib/screens/events_screen.dart`  
**Status:** Próximo, ajustes finos.

---

## Layout

```
┌─────────────────────────────────────┐
│ [status]                            │
│  Eventos                            │ ← title H2 24px InterTight 700
│  Últimas 24 horas                   │ ← subtitle inkSoft
├─────────────────────────────────────┤
│                                     │
│ ┌──────┐  ┌──────┐                  │ ← 2 contadores grandes
│ │  2   │  │  4   │                  │
│ │CRÍTI-│  │ INFO │                  │
│ │ COS  │  │      │                  │
│ └──────┘  └──────┘                  │
│                                     │
│ [Tudo] [Crítico] [Atenção] [OK]    │ ← chips de filtro
│                                     │
│ ┌─────────────────────────────────┐ │
│ │🔴 Coleira fora da geofence     │ │ ← danger card
│ │   C-042 · Quadrante Norte       │ │
│ │   agora            [● AO VIVO]  │ │
│ └─────────────────────────────────┘ │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │🟡 Bateria baixa                │ │ ← warn card
│ │   C-017 · 18%                   │ │
│ │   há 12 min                     │ │
│ └─────────────────────────────────┘ │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │🟢 Gateway online               │ │ ← ok card
│ │   GW-01 · sincronizado          │ │
│ │   há 1 h                        │ │
│ └─────────────────────────────────┘ │
│                                     │
│ ...                                 │
└─────────────────────────────────────┘
```

---

## Estrutura

```dart
Scaffold(
  backgroundColor: RTColors.bgAlt,
  body: CustomScrollView(slivers: [
    SliverAppBar(
      pinned: true,
      backgroundColor: RTColors.bg,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Eventos', style: RTTypography.h2.copyWith(fontSize: 24)),
          Text('Últimas 24 horas', 
            style: RTTypography.bodySmall.copyWith(color: RTColors.inkSoft)),
        ],
      ),
    ),
    
    SliverPadding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
      sliver: SliverToBoxAdapter(
        child: Row(children: [
          Expanded(child: _CounterCard(value: 2, label: 'Críticos', tone: RTColors.danger)),
          SizedBox(width: 12),
          Expanded(child: _CounterCard(value: 4, label: 'Informativos', tone: RTColors.info)),
        ]),
      ),
    ),
    
    SliverToBoxAdapter(child: SizedBox(height: 12)),
    
    SliverToBoxAdapter(
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: 16),
          children: [
            RTFilterChip(label: 'Tudo · 6', active: true),
            SizedBox(width: 8),
            RTFilterChip(label: 'Crítico · 2', dot: RTColors.danger),
            SizedBox(width: 8),
            RTFilterChip(label: 'Atenção · 1', dot: RTColors.warn),
            SizedBox(width: 8),
            RTFilterChip(label: 'OK · 3', dot: RTColors.ok),
          ],
        ),
      ),
    ),
    
    SliverPadding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16),
      sliver: SliverList.separated(
        itemCount: events.length,
        itemBuilder: (_, i) => RTEventCard(event: events[i]),
        separatorBuilder: (_, __) => SizedBox(height: 10),
      ),
    ),
  ]),
)
```

### `_CounterCard`
```dart
Container(
  padding: EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: RTColors.bg,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: RTColors.hairSoft),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$value', 
        style: RTTypography.h1.copyWith(fontSize: 36, color: tone)),
      SizedBox(height: 4),
      Text(label.toUpperCase(),
        style: RTTypography.eyebrow),
    ],
  ),
)
```

---

## RTEventCard (já existe — confirmar):
- Ícone tonal (círculo 36px com bg `dangerSoft`/`warnSoft`/`okSoft` + ícone `danger`/`warn`/`ok`)
- Title 14px medium
- Subtitle 12px inkSoft
- Timestamp 11px mono na direita
- Badge "● AO VIVO" em `danger` com pulse animation se evento < 60s

---

## Critério

- [ ] Header com 2 contadores grandes (números 36px InterTight 700)
- [ ] Chips de filtro por severidade com count
- [ ] Cards de evento com ícone tonal + cor por severidade
- [ ] Timestamp mono na direita
- [ ] Badge "AO VIVO" pulsante para eventos recentes
- [ ] Empty state desenhado se nenhum evento
