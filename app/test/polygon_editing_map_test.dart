import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:ruraltech_app/models/polygon_map_context.dart';
import 'package:ruraltech_app/utils/polygon_edit_session.dart';
import 'package:ruraltech_app/widgets/polygon_editing_map.dart';

void main() {
  Widget buildTestApp(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 600,
            height: 420,
            child: child,
          ),
        ),
      ),
    );
  }

  testWidgets('undo button follows session history availability',
      (tester) async {
    final controller = PolygonEditSessionController();

    await tester.pumpWidget(
      buildTestApp(
        _UndoHarness(controller: controller),
      ),
    );

    OutlinedButton undoButton() =>
        tester.widget<OutlinedButton>(find.byKey(const Key('undo_button')));

    expect(undoButton().onPressed, isNull);

    await tester.tap(find.byKey(const Key('add_point_button')));
    await tester.pump();

    expect(undoButton().onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('undo_button')));
    await tester.pump();

    expect(undoButton().onPressed, isNull);
  });

  testWidgets('tapping a vertex highlights it as selected', (tester) async {
    final controller = PolygonEditSessionController(
      initialPoints: const <LatLng>[
        LatLng(-16.10, -49.10),
        LatLng(-16.20, -49.20),
        LatLng(-16.30, -49.30),
      ],
    );

    await tester.pumpWidget(
      buildTestApp(
        PolygonEditingMap(
          controller: controller,
          showBaseTiles: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('polygon_vertex_1_idle')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('polygon_vertex_gesture_1')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('polygon_vertex_1_selected')),
      findsOneWidget,
    );
  });

  testWidgets('changing context swaps the property overlays on the map',
      (tester) async {
    await tester.pumpWidget(
      buildTestApp(const _ContextSwitchHarness()),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('polygon_device_marker_device-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('polygon_gateway_marker_gateway-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('polygon_device_marker_device-b')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('switch_context_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('polygon_device_marker_device-a')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('polygon_gateway_marker_gateway-a')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('polygon_device_marker_device-b')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('polygon_gateway_marker_gateway-b')),
      findsOneWidget,
    );
  });

  testWidgets('device selection coexists with polygon vertex selection',
      (tester) async {
    await tester.pumpWidget(
      buildTestApp(const _DeviceSelectionHarness()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Selecionados: 0'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('polygon_device_marker_device-herding')),
    );
    await tester.pump();

    expect(find.text('Selecionados: 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('polygon_vertex_gesture_0')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('polygon_vertex_0_selected')),
      findsOneWidget,
    );
  });
}

class _UndoHarness extends StatelessWidget {
  const _UndoHarness({required this.controller});

  final PolygonEditSessionController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: PolygonEditingMap(
            controller: controller,
            showBaseTiles: false,
          ),
        ),
        AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return Row(
              children: [
                OutlinedButton(
                  key: const Key('undo_button'),
                  onPressed: controller.canUndo ? controller.undo : null,
                  child: const Text('Desfazer'),
                ),
                TextButton(
                  key: const Key('add_point_button'),
                  onPressed: () =>
                      controller.addPoint(const LatLng(-16.10, -49.10)),
                  child: const Text('Adicionar'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ContextSwitchHarness extends StatefulWidget {
  const _ContextSwitchHarness();

  @override
  State<_ContextSwitchHarness> createState() => _ContextSwitchHarnessState();
}

class _ContextSwitchHarnessState extends State<_ContextSwitchHarness> {
  final controller = PolygonEditSessionController(
    initialPoints: const <LatLng>[
      LatLng(-16.10, -49.10),
      LatLng(-16.20, -49.20),
      LatLng(-16.30, -49.30),
    ],
  );
  var _useSecondContext = false;

  PolygonMapContext get _contextA => const PolygonMapContext(
        boundaryPolygon: <LatLng>[
          LatLng(-16.11, -49.11),
          LatLng(-16.21, -49.11),
          LatLng(-16.21, -49.21),
        ],
        devices: <PolygonMapDeviceOverlay>[
          PolygonMapDeviceOverlay(
            id: 'device-a',
            label: 'Coleira A',
            point: LatLng(-16.15, -49.15),
          ),
        ],
        gateways: <PolygonMapGatewayOverlay>[
          PolygonMapGatewayOverlay(
            id: 'gateway-a',
            label: 'Gateway A',
            point: LatLng(-16.18, -49.18),
          ),
        ],
      );

  PolygonMapContext get _contextB => const PolygonMapContext(
        boundaryPolygon: <LatLng>[
          LatLng(-15.11, -48.11),
          LatLng(-15.21, -48.11),
          LatLng(-15.21, -48.21),
        ],
        devices: <PolygonMapDeviceOverlay>[
          PolygonMapDeviceOverlay(
            id: 'device-b',
            label: 'Coleira B',
            point: LatLng(-15.15, -48.15),
          ),
        ],
        gateways: <PolygonMapGatewayOverlay>[
          PolygonMapGatewayOverlay(
            id: 'gateway-b',
            label: 'Gateway B',
            point: LatLng(-15.18, -48.18),
          ),
        ],
      );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(
          key: const Key('switch_context_button'),
          onPressed: () {
            setState(() => _useSecondContext = !_useSecondContext);
          },
          child: const Text('Trocar contexto'),
        ),
        Expanded(
          child: PolygonEditingMap(
            controller: controller,
            contextData: _useSecondContext ? _contextB : _contextA,
            viewportSignature: _useSecondContext ? 'context-b' : 'context-a',
            showBaseTiles: false,
          ),
        ),
      ],
    );
  }
}

class _DeviceSelectionHarness extends StatefulWidget {
  const _DeviceSelectionHarness();

  @override
  State<_DeviceSelectionHarness> createState() =>
      _DeviceSelectionHarnessState();
}

class _DeviceSelectionHarnessState extends State<_DeviceSelectionHarness> {
  final controller = PolygonEditSessionController(
    initialPoints: const <LatLng>[
      LatLng(-16.10, -49.10),
      LatLng(-16.20, -49.20),
      LatLng(-16.30, -49.30),
    ],
  );
  var _selected = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('Selecionados: ${_selected ? 1 : 0}'),
        Expanded(
          child: PolygonEditingMap(
            controller: controller,
            contextData: PolygonMapContext(
              devices: [
                PolygonMapDeviceOverlay(
                  id: 'device-herding',
                  label: 'Coleira Herding',
                  point: const LatLng(-16.18, -49.18),
                  selected: _selected,
                  onTap: () => setState(() => _selected = !_selected),
                ),
              ],
            ),
            viewportSignature: 'device-selection',
            showBaseTiles: false,
          ),
        ),
      ],
    );
  }
}
