import '../utils/cloud_compat.dart';

enum HerdingOperationStatus {
  submitted,
  dispatching,
  awaitingAssembly,
  requested,
  completed,
  failed,
  superseded,
}

HerdingOperationStatus herdingOperationStatusFromValue(dynamic value) {
  final raw = (value ?? '').toString().trim().toLowerCase();
  switch (raw) {
    case 'submitted':
      return HerdingOperationStatus.submitted;
    case 'dispatching':
      return HerdingOperationStatus.dispatching;
    case 'awaiting_assembly':
      return HerdingOperationStatus.awaitingAssembly;
    case 'requested':
      return HerdingOperationStatus.requested;
    case 'completed':
      return HerdingOperationStatus.completed;
    case 'failed':
      return HerdingOperationStatus.failed;
    case 'superseded':
      return HerdingOperationStatus.superseded;
    default:
      return HerdingOperationStatus.submitted;
  }
}

String herdingOperationStatusValue(HerdingOperationStatus status) {
  switch (status) {
    case HerdingOperationStatus.submitted:
      return 'submitted';
    case HerdingOperationStatus.dispatching:
      return 'dispatching';
    case HerdingOperationStatus.awaitingAssembly:
      return 'awaiting_assembly';
    case HerdingOperationStatus.requested:
      return 'requested';
    case HerdingOperationStatus.completed:
      return 'completed';
    case HerdingOperationStatus.failed:
      return 'failed';
    case HerdingOperationStatus.superseded:
      return 'superseded';
  }
}

class HerdingOperationDeviceStatus {
  const HerdingOperationDeviceStatus({
    required this.deviceId,
    required this.status,
    this.reason,
    this.phaseIndex,
    this.retryCount,
    this.updatedAtMs,
  });

  final String deviceId;
  final String status;
  final String? reason;
  final int? phaseIndex;
  final int? retryCount;
  final int? updatedAtMs;

  factory HerdingOperationDeviceStatus.fromMap(
    String deviceId,
    Map<String, dynamic> data,
  ) {
    return HerdingOperationDeviceStatus(
      deviceId: deviceId,
      status: (data['status'] ?? 'pending').toString(),
      reason: (data['reason'] ?? '').toString().trim().isEmpty
          ? null
          : data['reason'].toString().trim(),
      phaseIndex: data['phaseIndex'] is num
          ? (data['phaseIndex'] as num).toInt()
          : null,
      retryCount: data['retryCount'] is num
          ? (data['retryCount'] as num).toInt()
          : null,
      updatedAtMs: data['updatedAtMs'] is num
          ? (data['updatedAtMs'] as num).toInt()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'status': status,
      if (reason != null) 'reason': reason,
      if (phaseIndex != null) 'phaseIndex': phaseIndex,
      if (retryCount != null) 'retryCount': retryCount,
      if (updatedAtMs != null) 'updatedAtMs': updatedAtMs,
    };
  }
}

class HerdingOperationModel {
  const HerdingOperationModel({
    required this.id,
    required this.propertyId,
    required this.ownerUid,
    required this.requestedByUid,
    required this.requestedByRole,
    required this.status,
    required this.targetPolygon,
    required this.selectedDeviceIds,
    required this.notifyUserIds,
    required this.deviceStatuses,
    this.matrixGatewayId,
    this.createdAreaId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String propertyId;
  final String ownerUid;
  final String requestedByUid;
  final String requestedByRole;
  final HerdingOperationStatus status;
  final List<List<double>> targetPolygon;
  final List<String> selectedDeviceIds;
  final List<String> notifyUserIds;
  final Map<String, HerdingOperationDeviceStatus> deviceStatuses;
  final String? matrixGatewayId;
  final String? createdAreaId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  int get assembledCount => deviceStatuses.values
      .where((status) =>
          status.status == 'assembled' || status.status == 'completed')
      .length;

  int get completedCount => deviceStatuses.values
      .where((status) => status.status == 'completed')
      .length;

  factory HerdingOperationModel.fromMap(
    String id,
    Map<String, dynamic> data,
  ) {
    final rawTarget = data['targetPolygon'];
    final targetPolygon = <List<double>>[];
    if (rawTarget is List) {
      for (final entry in rawTarget) {
        if (entry is Map) {
          final lat = entry['lat'];
          final lon = entry['lon'];
          if (lat is num && lon is num) {
            targetPolygon.add(<double>[lat.toDouble(), lon.toDouble()]);
          }
        }
      }
    }

    final deviceStatuses = <String, HerdingOperationDeviceStatus>{};
    final rawStatuses = data['deviceStatuses'];
    if (rawStatuses is Map<String, dynamic>) {
      for (final entry in rawStatuses.entries) {
        if (entry.value is Map<String, dynamic>) {
          deviceStatuses[entry.key] = HerdingOperationDeviceStatus.fromMap(
            entry.key,
            entry.value as Map<String, dynamic>,
          );
        }
      }
    }

    DateTime? asDateTime(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String && value.trim().isNotEmpty) {
        return DateTime.tryParse(value.trim())?.toLocal();
      }
      if (value is num) {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      }
      return null;
    }

    String idFrom(dynamic value) {
      if (value is DocumentReference) return value.id;
      if (value is String) {
        final raw = value.trim();
        if (raw.isEmpty) return '';
        if (!raw.contains('/')) return raw;
        final parts =
            raw.split('/').where((entry) => entry.isNotEmpty).toList();
        return parts.isEmpty ? raw : parts.last;
      }
      if (value is Map) {
        if (value['id'] != null) return idFrom(value['id']);
        if (value['path'] != null) return idFrom(value['path']);
      }
      return '';
    }

    return HerdingOperationModel(
      id: id,
      propertyId: idFrom(data['propertyId']),
      ownerUid: idFrom(data['ownerUid']),
      requestedByUid: idFrom(data['requestedByUid']),
      requestedByRole: (data['requestedByRole'] ?? 'user').toString(),
      status: herdingOperationStatusFromValue(data['status']),
      targetPolygon: targetPolygon,
      selectedDeviceIds: ((data['selectedDeviceIds'] as List?) ?? const [])
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .toList(),
      notifyUserIds: ((data['notifyUserIds'] as List?) ?? const [])
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .toList(),
      deviceStatuses: deviceStatuses,
      matrixGatewayId: idFrom(data['matrixGatewayId']).isEmpty
          ? null
          : idFrom(data['matrixGatewayId']),
      createdAreaId: idFrom(data['createdAreaId']).isEmpty
          ? null
          : idFrom(data['createdAreaId']),
      createdAt: asDateTime(data['createdAt']),
      updatedAt: asDateTime(data['updatedAt']),
    );
  }
}
