# 07 · Profile — Spec

**Arquivo Flutter:** `app/lib/screens/profile_screen.dart` (481 linhas — reorganizar)  
**Status:** Layout não bate com mockup.

---

## Layout

```
┌─────────────────────────────────────┐
│ Perfil                          ⚙   │
├─────────────────────────────────────┤
│                                     │
│ ┌──────────────────────────────┐    │
│ │ [JR]  João Ribeiro           │    │ ← avatar header
│ │       joao@fazenda…          │    │
│ │       [Admin]                │    │
│ └──────────────────────────────┘    │
│                                     │
│ FILTROS DO MAPA                     │ ← eyebrow
│ ┌──────────────────────────────┐    │
│ │ 🏠 Propriedades              │    │
│ │    1 ativa · Fazenda Doce    │    │
│ │                          [▶] │    │
│ ├──────────────────────────────┤    │
│ │ 🗺  Áreas                    │    │
│ │    3 ativas · A1, A2, B1     │    │
│ │                          [▶] │    │
│ ├──────────────────────────────┤    │
│ │ 🐂 Coleiras                  │    │
│ │    Todas (9)                 │    │
│ │                          [▶] │    │
│ ├──────────────────────────────┤    │
│ │ 📡 Gateways                  │    │
│ │    Nenhum (0)                │    │
│ │                          [▶] │    │
│ └──────────────────────────────┘    │
│                                     │
│ CONTA                               │
│ ┌──────────────────────────────┐    │
│ │ 👤 Dados pessoais        [▶] │    │
│ │ 🔔 Notificações          [▶] │    │
│ │ ↻ Sincronização          [▶] │    │
│ │ ℹ Sobre o app            [▶] │    │
│ │ ⏻ Sair                       │    │
│ └──────────────────────────────┘    │
│                                     │
└─────────────────────────────────────┘
```

---

## Componentes

### Avatar header
```dart
RTCard(
  padding: EdgeInsets.all(16),
  child: Row(children: [
    Container(
      width: 56, height: 56,
      decoration: BoxDecoration(
        color: RTColors.primarySoft,
        shape: BoxShape.circle,
      ),
      child: Center(child: Text('JR',
        style: RTTypography.h3.copyWith(
          color: RTColors.primaryDeep, fontSize: 18,
        ),
      )),
    ),
    SizedBox(width: 14),
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('João Ribeiro', style: RTTypography.h3.copyWith(fontSize: 16)),
          SizedBox(height: 2),
          Text('joao@fazendadoce.com.br',
            style: RTTypography.bodySmall.copyWith(color: RTColors.inkSoft)),
          SizedBox(height: 6),
          RTBadge(label: 'Admin', tone: RTBadgeTone.primary),
        ],
      ),
    ),
  ]),
)
```

### Section header (eyebrow)
```dart
Padding(
  padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
  child: Text('FILTROS DO MAPA', style: RTTypography.eyebrow),
)
```

### Filter row
```dart
class _FilterRow extends StatelessWidget {
  Widget build(...) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: RTColors.bgAlt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: RTColors.inkSoft),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: RTTypography.body.copyWith(fontWeight: FontWeight.w600)),
                SizedBox(height: 2),
                Text(summary, style: RTTypography.bodySmall.copyWith(color: RTColors.inkSoft)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: RTColors.inkMute),
        ]),
      ),
    );
  }
}
```

Cards agrupam linhas com `Divider(color: RTColors.hairSoft, height: 1, indent: 60)`.

---

## Critério

- [ ] Avatar header com iniciais sobre `primarySoft` e badge de papel
- [ ] Seção "Filtros do mapa" com 4 linhas (Propriedades / Áreas / Coleiras / Gateways)
- [ ] Cada linha com ícone + título + summary + chevron
- [ ] Seção "Conta" separada com 5 linhas (Dados / Notificações / Sync / Sobre / Sair)
- [ ] Eyebrow uppercase entre seções
- [ ] Card único agrupa linhas com divisor leve
