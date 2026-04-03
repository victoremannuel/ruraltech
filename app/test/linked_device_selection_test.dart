import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:ruraltech_app/models/polygon_map_context.dart';
import 'package:ruraltech_app/utils/linked_device_selection.dart';
import 'package:ruraltech_app/utils/polygon_edit_session.dart';
import 'package:ruraltech_app/widgets/polygon_editing_map.dart';

void main() {
  test('normalizeLinkedDeviceIds keeps only valid numeric ids once', () {
    expect(
      normalizeLinkedDeviceIds(['2', '01', '2', 'abc', 3, 0, -4, ' 4 ']),
      ['1', '2', '3', '4'],
    );
  });

  test('LinkedDeviceSelectionController preloads and persists sorted ids', () {
    final controller = LinkedDeviceSelectionController(
      initialDeviceIds: ['3', '2', '2'],
    );

    expect(controller.selectedDeviceIds, ['2', '3']);

    controller.toggle('1');
    controller.toggle('3');

    expect(controller.selectedDeviceIds, ['1', '2']);
    expect(controller.selectedCount, 2);
  });

  testWidgets('map harness preloads selection and toggles linked collars',
      (tester) async {
    await tester.pumpWidget(const _AreaSelectionHarness());
    await tester.pumpAndSettle();

    expect(find.text('linked:2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('polygon_device_marker_1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('polygon_device_marker_2')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('polygon_device_marker_1')));
    await tester.pump();

    expect(find.text('linked:1,2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('polygon_device_marker_2')));
    await tester.pump();

    expect(find.text('linked:1'), findsOneWidget);
  });
}

class _AreaSelectionHarness extends StatefulWidget {
  const _AreaSelectionHarness();

  @override
  State<_AreaSelectionHarness> createState() => _AreaSelectionHarnessState();
}

class _AreaSelectionHarnessState extends State<_AreaSelectionHarness> {
  final PolygonEditSessionController _polygonController =
      PolygonEditSessionController(
    initialPoints: const <LatLng>[
      LatLng(-16.10, -49.10),
      LatLng(-16.20, -49.10),
      LatLng(-16.20, -49.20),
    ],
  );
  final LinkedDeviceSelectionController _linkedDeviceController =
      LinkedDeviceSelectionController(
    initialDeviceIds: const ['2'],
  );

  @override
  void dispose() {
    _polygonController.dispose();
    _linkedDeviceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: AnimatedBuilder(
                animation: _linkedDeviceController,
                builder: (context, _) {
                  return PolygonEditingMap(
                    controller: _polygonController,
                    showBaseTiles: false,
                    contextData: PolygonMapContext(
                      boundaryPolygon: const <LatLng>[
                        LatLng(-16.00, -49.00),
                        LatLng(-16.30, -49.00),
                        LatLng(-16.30, -49.30),
                      ],
                      devices: <PolygonMapDeviceOverlay>[
                        PolygonMapDeviceOverlay(
                          id: '1',
                          label: 'Coleira 1',
                          point: const LatLng(-16.12, -49.12),
                          selected: _linkedDeviceController.isSelected('1'),
                          onTap: () => _linkedDeviceController.toggle('1'),
                        ),
                        PolygonMapDeviceOverlay(
                          id: '2',
                          label: 'Coleira 2',
                          point: const LatLng(-16.18, -49.18),
                          selected: _linkedDeviceController.isSelected('2'),
                          onTap: () => _linkedDeviceController.toggle('2'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            AnimatedBuilder(
              animation: _linkedDeviceController,
              builder: (context, _) {
                return Text(
                  'linked:${_linkedDeviceController.selectedDeviceIds.join(',')}',
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
