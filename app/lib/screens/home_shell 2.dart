import 'package:flutter/material.dart';

import '../design/colors.dart';
import 'dashboard_screen.dart';
import 'events_screen.dart';
import 'operations_screen.dart';
import 'profile_screen.dart';

/// Shell raiz com `BottomNavigationBar` persistente + `IndexedStack`.
///
/// Substitui a antiga navegação via `Navigator.push` a partir da BottomAppBar
/// do dashboard. As 4 abas preservam estado ao trocar (IndexedStack mantém os
/// widgets montados; mapa e streams não reiniciam).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs = <_TabConfig>[
    _TabConfig(
      icon: Icons.map_outlined,
      activeIcon: Icons.map,
      label: 'Mapa',
      key: PageStorageKey('shell_tab_map'),
    ),
    _TabConfig(
      icon: Icons.notifications_outlined,
      activeIcon: Icons.notifications,
      label: 'Eventos',
      key: PageStorageKey('shell_tab_events'),
    ),
    _TabConfig(
      icon: Icons.tune_outlined,
      activeIcon: Icons.tune,
      label: 'Operações',
      key: PageStorageKey('shell_tab_ops'),
    ),
    _TabConfig(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Perfil',
      key: PageStorageKey('shell_tab_profile'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          _KeepAliveTab(
            storageKey: PageStorageKey('shell_tab_map'),
            child: HomeScreen(),
          ),
          _KeepAliveTab(
            storageKey: PageStorageKey('shell_tab_events'),
            child: EventsScreen(),
          ),
          _KeepAliveTab(
            storageKey: PageStorageKey('shell_tab_ops'),
            child: OperationsScreen(),
          ),
          _KeepAliveTab(
            storageKey: PageStorageKey('shell_tab_profile'),
            child: ProfileScreen(),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        key: const Key('home_shell_bottom_nav'),
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: RTColors.bg,
        indicatorColor: RTColors.primarySoft,
        surfaceTintColor: Colors.transparent,
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.activeIcon, color: RTColors.primary),
              label: t.label,
            ),
        ],
      ),
    );
  }
}

class _TabConfig {
  const _TabConfig({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.key,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final PageStorageKey<String> key;
}

class _KeepAliveTab extends StatefulWidget {
  const _KeepAliveTab({required this.storageKey, required this.child});

  final PageStorageKey<String> storageKey;
  final Widget child;

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return KeyedSubtree(key: widget.storageKey, child: widget.child);
  }
}
