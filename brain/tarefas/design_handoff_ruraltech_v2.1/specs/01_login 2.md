# 01 · Login Screen — Spec pixel-a-pixel

**Arquivo Flutter:** `app/lib/screens/login_screen.dart`  
**Componente wrapper:** `RTAuthScaffold` (já existe — precisa ser ESTENDIDO com o hero ilustrativo)  
**Referência visual:** abrir `design_handoff_ruraltech_v2.1/RuralTech Redesign.html` no browser e ir para a seção "05 · Telas → 01 Login"

---

## Layout geral

```
┌─────────────────────────────────────┐
│ [status bar — branco em verde]      │
│                                     │
│   HERO TOPOGRÁFICO (40% altura)    │
│   - Gradient: heroStart → heroEnd  │
│   - Pattern SVG topográfico (linhas curvas)
│   - Logo "RuralTech" + ícone (top-left)
│   - Polígono ilustrativo (centro)  │
│                                     │
├─────────────────────────────────────┤  ← curva top: 24px radius
│                                     │
│   CARD BRANCO (60% altura)         │
│   - Padding: 24px lateral, 28 top  │
│   - Title "Entrar na operação"     │
│   - Subtitle (1 linha)             │
│   - Spacer 24                      │
│   - Field email                    │
│   - Spacer 16                      │
│   - Field senha                    │
│   - Spacer 24                      │
│   - Button primário "Entrar"       │
│   - Spacer 12                      │
│   - Button ghost "Criar conta"     │
│   - Spacer 24                      │
│   - Offline hint (accent soft)     │
│                                     │
└─────────────────────────────────────┘
```

---

## Diff vs implementação atual

A implementação atual tem o `RTAuthScaffold` com title + subtitle + child, mas **falta o hero ilustrativo**. Hoje é um header simples — precisa virar um hero com:

1. **Gradient diagonal** de `RTColors.heroStart` (terra accent) → `RTColors.heroEnd` (verde primary)
2. **Padrão topográfico SVG** sobreposto (linhas onduladas em branco com 8% de opacidade)
3. **Logo RuralTech** no topo-esquerdo (Container 40×40 com primary, ícone branco + texto "RuralTech" em InterTight 700 18px branco)
4. **Polígono ilustrativo** centralizado mostrando uma propriedade rural com 3 pontos (coleiras) — desenho SVG simples

---

## Widget tree alvo (Flutter)

```dart
class LoginScreen extends StatefulWidget {
  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RTColors.bg,
      body: Stack(
        children: [
          // ── HERO TOPOGRÁFICO ──
          Positioned(
            top: 0, left: 0, right: 0,
            height: MediaQuery.of(context).size.height * 0.42,
            child: _Hero(),
          ),
          
          // ── BOTTOM SHEET ESTÁTICA ──
          Positioned(
            bottom: 0, left: 0, right: 0,
            top: MediaQuery.of(context).size.height * 0.36,  // sobrepõe 6% do hero
            child: Container(
              decoration: BoxDecoration(
                color: RTColors.bg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(RTRadius.r5),  // 24
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Entrar na operação', style: RTTypography.h2.copyWith(fontSize: 24)),
                      const SizedBox(height: 6),
                      Text('Monitore propriedades, coleiras e gateways em campo.',
                        style: RTTypography.body.copyWith(color: RTColors.inkSoft)),
                      const SizedBox(height: RTSpacing.x6),  // 24
                      RTField(label: 'E-mail', leadingIcon: Icons.mail_outline, ...),
                      const SizedBox(height: RTSpacing.x4),  // 16
                      RTField(label: 'Senha', leadingIcon: Icons.lock_outline, obscure: true, ...),
                      const SizedBox(height: RTSpacing.x6),  // 24
                      RTButton(label: 'Entrar', size: RTButtonSize.lg, fullWidth: true, ...),
                      const SizedBox(height: RTSpacing.x3),  // 12
                      RTButton(label: 'Criar conta', variant: RTButtonVariant.ghost, fullWidth: true, ...),
                      const SizedBox(height: RTSpacing.x6),
                      _OfflineHint(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  @override Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [RTColors.heroStart, RTColors.heroEnd],
        ),
      ),
      child: Stack(
        children: [
          // Pattern topográfico (SVG inline ou CustomPainter de linhas onduladas)
          Positioned.fill(
            child: Opacity(
              opacity: 0.08,
              child: CustomPaint(painter: _TopographyPainter()),
            ),
          ),
          // Logo top-left
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: const Icon(Icons.terrain_outlined, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Text('RuralTech',
                    style: RTTypography.h3.copyWith(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Polígono ilustrativo central
          Center(
            child: SizedBox(
              width: 220, height: 130,
              child: CustomPaint(painter: _PropertyPolygonPainter()),
            ),
          ),
        ],
      ),
    );
  }
}
```

---

## Pintor topográfico (linhas onduladas)

```dart
class _TopographyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    
    for (double y = 20; y < size.height; y += 30) {
      final path = Path()..moveTo(0, y);
      for (double x = 0; x < size.width; x += 60) {
        path.quadraticBezierTo(x + 15, y - 15, x + 30, y);
        path.quadraticBezierTo(x + 45, y + 15, x + 60, y);
      }
      canvas.drawPath(path, paint);
    }
  }
  @override bool shouldRepaint(_) => false;
}
```

---

## Pintor do polígono ilustrativo

```dart
class _PropertyPolygonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // polígono irregular preenchido translúcido
    final fillPaint = Paint()
      ..color = Colors.black.withOpacity(0.15)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = const Color(0xFFE7A300).withOpacity(0.7)  // accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    
    final dashPath = Path()
      ..moveTo(size.width * 0.15, size.height * 0.45)
      ..lineTo(size.width * 0.45, size.height * 0.10)
      ..lineTo(size.width * 0.85, size.height * 0.30)
      ..lineTo(size.width * 0.90, size.height * 0.70)
      ..lineTo(size.width * 0.55, size.height * 0.95)
      ..lineTo(size.width * 0.20, size.height * 0.85)
      ..close();
    
    canvas.drawPath(dashPath, fillPaint);
    // desenhar tracejado manualmente (PathMetric com dashes)
    _drawDashedPath(canvas, dashPath, strokePaint, dashWidth: 5, gap: 4);
    
    // 3 pontos (coleiras): círculos brancos pequenos
    final dotPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(size.width * 0.35, size.height * 0.35), 4, dotPaint);
    canvas.drawCircle(Offset(size.width * 0.55, size.height * 0.55), 4, dotPaint);
    // 1 ponto laranja (selecionado)
    canvas.drawCircle(
      Offset(size.width * 0.50, size.height * 0.30), 5,
      Paint()..color = const Color(0xFFE7A300),
    );
  }
  @override bool shouldRepaint(_) => false;
}
```

---

## Tokens usados

- `RTColors.heroStart`, `RTColors.heroEnd` (já existem)
- `RTColors.bg`, `RTColors.ink`, `RTColors.inkSoft`
- `RTColors.accentSoft`, `RTColors.accent` (offline hint)
- `RTRadius.r5` (24) — curva do bottom sheet estático
- `RTSpacing.x3` (12), `x4` (16), `x6` (24)

---

## Critério de aceitação

- [ ] Hero ocupa ~42% da altura da tela
- [ ] Gradient diagonal terra→verde visível
- [ ] Pattern topográfico sutil (8% opacidade) sobreposto
- [ ] Logo "RuralTech" branco no topo-esquerdo
- [ ] Polígono ilustrativo no centro do hero
- [ ] Card branco com radius 24 no topo, sobrepondo o hero
- [ ] Form com email + senha + 2 botões + offline hint
- [ ] Offline hint em `accentSoft` com texto explicativo
