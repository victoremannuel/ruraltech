import 'package:flutter/foundation.dart';

class MapFilterService extends ChangeNotifier {
  final Set<String> _propertyIds = {};
  final Set<String> _areaIds = {};
  final Set<String> _collarIds = {};
  final Set<String> _gatewayIds = {};
  int _revision = 0;

  Set<String> get propertyIds => _propertyIds;
  Set<String> get areaIds => _areaIds;
  Set<String> get collarIds => _collarIds;
  Set<String> get gatewayIds => _gatewayIds;
  int get revision => _revision;

  bool get hasAnyFilter =>
      _propertyIds.isNotEmpty ||
      _areaIds.isNotEmpty ||
      _collarIds.isNotEmpty ||
      _gatewayIds.isNotEmpty;

  bool isPropertySelected(String id) => _propertyIds.contains(id);
  bool isAreaSelected(String id) => _areaIds.contains(id);
  bool isCollarSelected(String id) => _collarIds.contains(id);
  bool isGatewaySelected(String id) => _gatewayIds.contains(id);

  void toggleProperty(String id, bool selected) {
    if (selected) {
      _propertyIds.add(id);
    } else {
      _propertyIds.remove(id);
    }
    notifyListeners();
  }

  void toggleCollar(String id, bool selected) {
    if (selected) {
      _collarIds.add(id);
    } else {
      _collarIds.remove(id);
    }
    notifyListeners();
  }

  void toggleArea(String id, bool selected) {
    if (selected) {
      _areaIds.add(id);
    } else {
      _areaIds.remove(id);
    }
    notifyListeners();
  }

  void toggleGateway(String id, bool selected) {
    if (selected) {
      _gatewayIds.add(id);
    } else {
      _gatewayIds.remove(id);
    }
    notifyListeners();
  }

  void clearAll() {
    _propertyIds.clear();
    _areaIds.clear();
    _collarIds.clear();
    _gatewayIds.clear();
    _revision++;
    notifyListeners();
  }

  void applySelections({
    required Set<String> propertyIds,
    required Set<String> areaIds,
    required Set<String> collarIds,
    required Set<String> gatewayIds,
  }) {
    _propertyIds
      ..clear()
      ..addAll(propertyIds);
    _areaIds
      ..clear()
      ..addAll(areaIds);
    _collarIds
      ..clear()
      ..addAll(collarIds);
    _gatewayIds
      ..clear()
      ..addAll(gatewayIds);
    _revision++;
    notifyListeners();
  }
}
