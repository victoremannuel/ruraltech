import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/domain/rt_action_row.dart';
import '../components/primitives/rt_card.dart';
import '../design/colors.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../services/auth_service.dart';
import 'area_editor_screen.dart';
import 'herding_screen.dart';
import 'rural_property_editor_screen.dart';

/// Hub de operações: geofence/arrebanhamento + cadastros (admin).
///
/// Substitui o modal "+ Acoes" da bottom bar antiga. Itens cadastrais seguem
/// visíveis apenas para administradores — o restante (arrebanhamento, área)
/// é disponível a qualquer operador autenticado.
class OperationsScreen extends StatelessWidget {
  const OperationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return Scaffold(
      backgroundColor: RTColors.bgAlt,
      appBar: AppBar(title: const Text('Operações')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          RTSpacing.x4,
          RTSpacing.x3,
          RTSpacing.x4,
          RTSpacing.x8,
        ),
        children: [
          _sectionLabel('Campo'),
          const SizedBox(height: RTSpacing.x2),
          _group(context, [
            _RowConfig(
              icon: Icons.crop_free,
              title: 'Novo polígono / área',
              description: 'Desenhar perímetro de piquete ou retiro',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AreaEditorScreen()),
              ),
              actionKey: const Key('operations_action_new_area'),
            ),
            _RowConfig(
              icon: Icons.route_outlined,
              title: 'Solicitar arrebanhamento',
              description: 'Conduzir rebanho para área-alvo',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HerdingScreen()),
              ),
              actionKey: const Key('operations_action_start_herding'),
            ),
          ]),
          if (auth.isAdmin) ...[
            const SizedBox(height: RTSpacing.x5),
            _sectionLabel('Cadastros'),
            const SizedBox(height: RTSpacing.x2),
            _group(context, [
              _RowConfig(
                icon: Icons.landscape_outlined,
                title: 'Nova propriedade rural',
                description: 'Registrar fazenda / retiro',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RuralPropertyEditorScreen(),
                  ),
                ),
                actionKey: const Key('operations_action_add_property'),
              ),
            ]),
            const SizedBox(height: RTSpacing.x5),
            _hintBanner(
              'Cadastros de coleira / gateway / repair continuam no FAB do mapa. Em breve migram para este hub.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: RTSpacing.x1),
      child: Text(label.toUpperCase(), style: RTTypography.eyebrow),
    );
  }

  Widget _group(BuildContext context, List<_RowConfig> rows) {
    return RTCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: RTColors.hairSoft),
            RTActionRow(
              key: rows[i].actionKey,
              icon: rows[i].icon,
              title: rows[i].title,
              description: rows[i].description,
              onTap: rows[i].onTap,
            ),
          ],
        ],
      ),
    );
  }

  Widget _hintBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(RTSpacing.x3),
      decoration: BoxDecoration(
        color: RTColors.infoSoft,
        borderRadius: BorderRadius.circular(RTRadius.r3),
        border: Border.all(color: RTColors.info.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: RTColors.info, size: 20),
          const SizedBox(width: RTSpacing.x2),
          Expanded(
            child: Text(
              message,
              style: RTTypography.bodySmall.copyWith(color: RTColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _RowConfig {
  const _RowConfig({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.actionKey,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final Key? actionKey;
}
