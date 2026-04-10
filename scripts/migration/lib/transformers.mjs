/**
 * Transformation logic: Firebase data formats → Supabase schema rows.
 *
 * Firebase → Supabase field mapping conventions:
 * - Firebase Timestamp → epoch ms (bigint) for *_received_at_ms fields
 * - Firebase Timestamp → ISO string for timestamptz fields
 * - GeoPoint { latitude, longitude } → { lat, lon }
 * - DocumentReference → extract last segment (the doc ID)
 * - Arrays of DocumentReference → array of ID strings
 */
import { createHash } from 'crypto';

// ─── ID helpers ──────────────────────────────────────────────────────────────

export function normalizeId(value) {
  if (!value) return '';
  if (typeof value === 'string') return value.trim();
  // Firebase DocumentReference has .id or .path
  if (typeof value === 'object') {
    if (value.id) return String(value.id).trim();
    if (value._path?.segments) {
      const segs = value._path.segments;
      return String(segs[segs.length - 1]).trim();
    }
    if (value.path) {
      const parts = String(value.path).split('/');
      return parts[parts.length - 1].trim();
    }
  }
  return String(value).trim();
}

export function normalizeIdList(value) {
  if (!value) return [];
  if (Array.isArray(value)) return value.map(normalizeId).filter(Boolean);
  if (typeof value === 'object') return Object.keys(value).filter(Boolean);
  return [];
}

export function normalizeText(value) {
  if (!value) return '';
  return String(value).trim();
}

/**
 * Compute property_scope_id: SHA-256 of lowercase trimmed ID, first 16 hex chars uppercase.
 * Must match public.compute_property_scope_id() SQL function.
 */
export function computePropertyScopeId(propertyId) {
  const normalized = normalizeId(propertyId).toLowerCase();
  if (!normalized) return '';
  const hash = createHash('sha256').update(normalized).digest('hex');
  return hash.slice(0, 16).toUpperCase();
}

// ─── Timestamp helpers ───────────────────────────────────────────────────────

/**
 * Convert a Firebase Timestamp (has .toDate()) or Date or number to ISO string.
 * Returns null if invalid.
 */
export function fbTimestampToIso(value) {
  if (!value) return null;
  if (typeof value === 'number') return new Date(value).toISOString();
  if (value instanceof Date) return value.toISOString();
  if (typeof value.toDate === 'function') return value.toDate().toISOString();
  if (typeof value._seconds === 'number') {
    return new Date(value._seconds * 1000 + Math.floor((value._nanoseconds || 0) / 1e6)).toISOString();
  }
  if (typeof value === 'string') return new Date(value).toISOString();
  return null;
}

/**
 * Convert a Firebase Timestamp to milliseconds epoch.
 * Returns null if invalid.
 */
export function fbTimestampToMs(value) {
  if (!value) return null;
  if (typeof value === 'number') return value;
  if (value instanceof Date) return value.getTime();
  if (typeof value.toDate === 'function') return value.toDate().getTime();
  if (typeof value._seconds === 'number') {
    return value._seconds * 1000 + Math.floor((value._nanoseconds || 0) / 1e6);
  }
  if (typeof value === 'string') return new Date(value).getTime();
  return null;
}

// ─── GeoPoint helper ─────────────────────────────────────────────────────────

/**
 * Convert Firebase GeoPoint { latitude, longitude } → { lat, lon }.
 */
export function fbGeoPoint(value) {
  if (!value) return null;
  const lat = typeof value.latitude === 'number' ? value.latitude : (value.lat ?? null);
  const lon = typeof value.longitude === 'number' ? value.longitude : (value.lon ?? value.lng ?? null);
  if (lat === null || lon === null) return null;
  return { lat, lon };
}

/**
 * Convert array of GeoPoints to [ { lat, lon }, ... ]
 */
export function fbGeoPointArray(value) {
  if (!Array.isArray(value)) return [];
  return value.map(fbGeoPoint).filter(Boolean);
}

// ─── Entity transformers ──────────────────────────────────────────────────────

/**
 * Transform a Firestore ruralProperty document → rural_properties row.
 */
export function transformRuralProperty({ id, data }) {
  const points = Array.isArray(data.points) ? fbGeoPointArray(data.points) : [];
  const ownerUid = normalizeId(data.ownerUid ?? data.owner_uid ?? data.ownerId);
  const createdByUid = normalizeId(data.createdByUid ?? data.created_by_uid ?? ownerUid);
  const updatedByUid = normalizeId(data.updatedByUid ?? data.updated_by_uid) || null;
  const userUids = normalizeIdList(data.userUids ?? data.user_uids ?? data.members ?? []);
  const name = normalizeText(data.name ?? data.farmName ?? '');
  return {
    id,
    name,
    points: JSON.stringify(points),
    owner_uid: ownerUid,
    created_by_uid: createdByUid,
    updated_by_uid: updatedByUid,
    user_uids: userUids,
    property_scope_id: computePropertyScopeId(id),
    created_at: fbTimestampToIso(data.createdAt ?? data.created_at) ?? new Date().toISOString(),
    updated_at: fbTimestampToIso(data.updatedAt ?? data.updated_at) ?? new Date().toISOString(),
  };
}

/**
 * Transform a Firestore area document → areas row.
 */
export function transformArea({ id, data }) {
  const propertyId = normalizeId(data.propertyId ?? data.property_id);
  const ownerUid = normalizeId(data.ownerUid ?? data.owner_uid ?? data.ownerId);
  const perimeter = Array.isArray(data.perimeter ?? data.points) ? fbGeoPointArray(data.perimeter ?? data.points) : [];
  const linkedDeviceIds = normalizeIdList(data.linkedDeviceIds ?? data.linked_device_ids ?? data.deviceIds ?? []);
  const userUids = normalizeIdList(data.userUids ?? data.user_uids ?? []);
  const updatedByUid = normalizeId(data.updatedByUid ?? data.updated_by_uid) || null;
  return {
    id,
    owner_uid: ownerUid,
    property_id: propertyId || null,
    user_uids: userUids,
    perimeter: JSON.stringify(perimeter),
    linked_device_ids: linkedDeviceIds,
    updated_by_uid: updatedByUid,
    created_at: fbTimestampToIso(data.createdAt ?? data.created_at) ?? new Date().toISOString(),
    updated_at: fbTimestampToIso(data.updatedAt ?? data.updated_at) ?? new Date().toISOString(),
  };
}

/**
 * Transform a Firestore gateway document → gateways row.
 */
export function transformGateway({ id, data }) {
  const propertyId = normalizeId(data.propertyId ?? data.property_id) || null;
  const position = fbGeoPoint(data.position ?? data.location);
  const runtimeStatus = data.runtimeStatus ?? data.runtime_status ?? {};
  return {
    id,
    gateway_id: normalizeText(data.gatewayId ?? data.gateway_id ?? data.deviceId ?? id),
    owner_uid: normalizeId(data.ownerUid ?? data.owner_uid) || null,
    name: normalizeText(data.name ?? id),
    status: normalizeText(data.status ?? 'offline'),
    host: normalizeText(data.host ?? data.ip) || null,
    property_id: propertyId,
    user_uids: normalizeIdList(data.userUids ?? data.user_uids ?? []),
    wifi_ota_enabled: data.wifiOtaEnabled ?? data.wifi_ota_enabled ?? true,
    position: position ? JSON.stringify(position) : null,
    is_matrix: data.isMatrix ?? data.is_matrix ?? false,
    property_scope_id: propertyId ? computePropertyScopeId(propertyId) : null,
    binding_ready: data.bindingReady ?? data.binding_ready ?? false,
    supports_scoped_lora: data.supportsScopedLora ?? data.supports_scoped_lora ?? false,
    runtime_status: JSON.stringify(runtimeStatus),
    created_at: fbTimestampToIso(data.createdAt ?? data.created_at) ?? new Date().toISOString(),
    updated_at: fbTimestampToIso(data.updatedAt ?? data.updated_at) ?? new Date().toISOString(),
  };
}

/**
 * Transform a Firestore collar document → collars row.
 */
export function transformCollar({ id, data }) {
  const propertyId = normalizeId(data.propertyId ?? data.property_id) || null;
  const gatewayId = normalizeId(data.gatewayId ?? data.gateway_id) || null;
  const position = fbGeoPoint(data.position ?? data.location);
  const runtimeStatus = data.runtimeStatus ?? data.runtime_status ?? {};
  return {
    id,
    device_id: normalizeText(data.deviceId ?? data.device_id ?? data.loraDeviceId ?? data.lora_device_id ?? id),
    owner_uid: normalizeId(data.ownerUid ?? data.owner_uid) || null,
    name: normalizeText(data.name ?? id),
    status: normalizeText(data.status ?? 'unknown'),
    property_id: propertyId,
    gateway_id: gatewayId,
    position: position ? JSON.stringify(position) : null,
    wifi_ota_enabled: data.wifiOtaEnabled ?? data.wifi_ota_enabled ?? true,
    property_scope_id: propertyId ? computePropertyScopeId(propertyId) : null,
    binding_ready: data.bindingReady ?? data.binding_ready ?? false,
    supports_scoped_lora: data.supportsScopedLora ?? data.supports_scoped_lora ?? false,
    runtime_status: JSON.stringify(runtimeStatus),
    telemetry_received_at_ms: fbTimestampToMs(data.telemetryReceivedAt ?? data.telemetry_received_at) ?? data.telemetryReceivedAtMs ?? data.telemetry_received_at_ms ?? null,
    position_received_at_ms: fbTimestampToMs(data.positionReceivedAt ?? data.position_received_at) ?? data.positionReceivedAtMs ?? null,
    health_received_at_ms: fbTimestampToMs(data.healthReceivedAt ?? data.health_received_at) ?? data.healthReceivedAtMs ?? null,
    health_gps_day_key: data.healthGpsDayKey ?? data.health_gps_day_key ?? null,
    health_flags: data.healthFlags ?? data.health_flags ?? null,
    health_uptime_sec: data.healthUptimeSec ?? data.health_uptime_sec ?? null,
    health_temperature_deci_c: data.healthTemperatureDeciC ?? data.health_temperature_deci_c ?? null,
    health_satellites: data.healthSatellites ?? data.health_satellites ?? null,
    health_hdop_centi: data.healthHdopCenti ?? data.health_hdop_centi ?? null,
    health_i2c_devices: data.healthI2cDevices ?? data.health_i2c_devices ?? null,
    created_at: fbTimestampToIso(data.createdAt ?? data.created_at) ?? new Date().toISOString(),
    updated_at: fbTimestampToIso(data.updatedAt ?? data.updated_at) ?? new Date().toISOString(),
  };
}

/**
 * Transform a Firestore fence document → fences row.
 * Note: fences.device_id references collars.id (UUID primary key).
 */
export function transformFence({ id, data }) {
  const points = Array.isArray(data.points) ? fbGeoPointArray(data.points) : [];
  return {
    device_id: id, // fences PK references collars.id
    owner_uid: normalizeId(data.ownerUid ?? data.owner_uid),
    points: JSON.stringify(points),
    updated_at: fbTimestampToIso(data.updatedAt ?? data.updated_at) ?? new Date().toISOString(),
  };
}

/**
 * Transform a Firestore herdingPlan document → herding_plans row.
 */
export function transformHerdingPlan({ id, data }) {
  const phases = Array.isArray(data.phases) ? data.phases.map(phase => {
    const pts = Array.isArray(phase.points) ? fbGeoPointArray(phase.points) : [];
    return { ...phase, points: pts };
  }) : [];
  return {
    device_id: id,
    owner_uid: normalizeId(data.ownerUid ?? data.owner_uid),
    phases: JSON.stringify(phases),
    updated_at: fbTimestampToIso(data.updatedAt ?? data.updated_at) ?? new Date().toISOString(),
  };
}

/**
 * Transform a Firestore herdingOperation document → herding_operations row.
 */
export function transformHerdingOperation({ id, data }) {
  const propertyId = normalizeId(data.propertyId ?? data.property_id);
  const targetPolygon = Array.isArray(data.targetPolygon ?? data.target_polygon) ? fbGeoPointArray(data.targetPolygon ?? data.target_polygon) : [];
  return {
    id,
    property_id: propertyId,
    owner_uid: normalizeId(data.ownerUid ?? data.owner_uid),
    requested_by_uid: normalizeId(data.requestedByUid ?? data.requested_by_uid ?? data.ownerUid ?? data.owner_uid),
    requested_by_role: normalizeText(data.requestedByRole ?? data.requested_by_role ?? 'user'),
    status: normalizeText(data.status ?? 'unknown'),
    target_polygon: JSON.stringify(targetPolygon),
    selected_device_ids: normalizeIdList(data.selectedDeviceIds ?? data.selected_device_ids ?? []),
    notify_user_ids: normalizeIdList(data.notifyUserIds ?? data.notify_user_ids ?? []),
    device_statuses: JSON.stringify(data.deviceStatuses ?? data.device_statuses ?? {}),
    matrix_gateway_id: normalizeId(data.matrixGatewayId ?? data.matrix_gateway_id) || null,
    created_area_id: normalizeId(data.createdAreaId ?? data.created_area_id) || null,
    lora_command_id: normalizeId(data.loraCommandId ?? data.lora_command_id) || null,
    area_promotion_requested: data.areaPromotionRequested ?? data.area_promotion_requested ?? true,
    client_failure_reason: normalizeText(data.clientFailureReason ?? data.client_failure_reason) || null,
    property_scope_id: propertyId ? computePropertyScopeId(propertyId) : null,
    created_at: fbTimestampToIso(data.createdAt ?? data.created_at) ?? new Date().toISOString(),
    updated_at: fbTimestampToIso(data.updatedAt ?? data.updated_at) ?? new Date().toISOString(),
  };
}

/**
 * Transform a Firestore event document → events row.
 */
export function transformEvent({ id, data }) {
  const propertyId = normalizeId(data.propertyId ?? data.property_id) || null;
  return {
    id,
    owner_uid: normalizeId(data.ownerUid ?? data.owner_uid) || null,
    property_id: propertyId,
    device_id: normalizeId(data.deviceId ?? data.device_id) || null,
    gateway_id: normalizeId(data.gatewayId ?? data.gateway_id) || null,
    type: normalizeText(data.type) || null,
    event_type: normalizeText(data.eventType ?? data.event_type ?? data.type) || null,
    polygon_kind: normalizeText(data.polygonKind ?? data.polygon_kind) || null,
    origin_doc_type: normalizeText(data.originDocType ?? data.origin_doc_type) || null,
    origin_doc_id: normalizeId(data.originDocId ?? data.origin_doc_id) || null,
    received_at_ms: fbTimestampToMs(data.receivedAt ?? data.received_at) ?? data.receivedAtMs ?? null,
    payload: JSON.stringify(data.payload ?? {}),
    created_at: fbTimestampToIso(data.createdAt ?? data.created_at) ?? new Date().toISOString(),
    updated_at: fbTimestampToIso(data.updatedAt ?? data.updated_at) ?? new Date().toISOString(),
  };
}

/**
 * Transform a Firestore loraCommand document → property_commands row.
 */
export function transformPropertyCommand({ id, data }) {
  const propertyId = normalizeId(data.propertyId ?? data.property_id);
  return {
    property_id: propertyId,
    command_id: normalizeText(data.commandId ?? data.command_id ?? id),
    command: normalizeText(data.command ?? data.type) || null,
    status: normalizeText(data.status) || null,
    property_scope_id: propertyId ? computePropertyScopeId(propertyId) : null,
    matrix_gateway_id: normalizeId(data.matrixGatewayId ?? data.matrix_gateway_id) || null,
    requested_by_uid: normalizeId(data.requestedByUid ?? data.requested_by_uid) || null,
    requested_by_role: normalizeText(data.requestedByRole ?? data.requested_by_role) || null,
    created_at_ms: fbTimestampToMs(data.createdAt ?? data.created_at) ?? data.createdAtMs ?? null,
    updated_at_ms: fbTimestampToMs(data.updatedAt ?? data.updated_at) ?? data.updatedAtMs ?? null,
    expires_at_ms: data.expiresAtMs ?? data.expires_at_ms ?? null,
    polygon_kind: normalizeText(data.polygonKind ?? data.polygon_kind) || null,
    origin_doc_type: normalizeText(data.originDocType ?? data.origin_doc_type) || null,
    origin_doc_id: normalizeId(data.originDocId ?? data.origin_doc_id) || null,
    target_device_ids: normalizeIdList(data.targetDeviceIds ?? data.target_device_ids ?? []),
    target_gateway_ids: normalizeIdList(data.targetGatewayIds ?? data.target_gateway_ids ?? []),
    device_results: JSON.stringify(data.deviceResults ?? data.device_results ?? {}),
    reason: normalizeText(data.reason) || null,
    payload: JSON.stringify(data.payload ?? {}),
    raw: JSON.stringify(data),
    created_at: fbTimestampToIso(data.createdAt ?? data.created_at) ?? new Date().toISOString(),
    updated_at: fbTimestampToIso(data.updatedAt ?? data.updated_at) ?? new Date().toISOString(),
  };
}

/**
 * Transform a Firestore loraCommandEvent document → property_command_events row.
 */
export function transformPropertyCommandEvent({ id, data, propertyId, dayKey }) {
  return {
    property_id: propertyId,
    day_key: dayKey,
    event_id: id,
    command_id: normalizeId(data.commandId ?? data.command_id) || null,
    device_id: normalizeId(data.deviceId ?? data.device_id) || null,
    status: normalizeText(data.status) || null,
    received_at_ms: fbTimestampToMs(data.receivedAt ?? data.received_at) ?? data.receivedAtMs ?? null,
    payload: JSON.stringify(data.payload ?? {}),
    raw: JSON.stringify(data),
    created_at: fbTimestampToIso(data.createdAt ?? data.created_at) ?? new Date().toISOString(),
  };
}

// ─── RTDB transformers ───────────────────────────────────────────────────────

/**
 * Transform RTDB telemetryLatest entry.
 * RTDB path: telemetryLatest/{property}/{device} → value is telemetry object
 */
export function transformTelemetryLatest({ propertyId, deviceId, data }) {
  return {
    property_id: propertyId,
    device_id: deviceId,
    lat: typeof data.lat === 'number' ? data.lat : null,
    lon: typeof data.lon === 'number' ? data.lon : null,
    received_at_ms: data.receivedAtMs ?? data.received_at_ms ?? fbTimestampToMs(data.receivedAt) ?? null,
    payload: JSON.stringify(data),
    updated_at: new Date().toISOString(),
  };
}

/**
 * Transform RTDB telemetryHistory entry.
 */
export function transformTelemetryHistory({ propertyId, deviceId, dayKey, historyId, data }) {
  return {
    property_id: propertyId,
    device_id: deviceId,
    history_id: historyId,
    day_key: dayKey,
    lat: typeof data.lat === 'number' ? data.lat : null,
    lon: typeof data.lon === 'number' ? data.lon : null,
    received_at_ms: data.receivedAtMs ?? data.received_at_ms ?? fbTimestampToMs(data.receivedAt) ?? null,
    payload: JSON.stringify(data),
    created_at: new Date().toISOString(),
  };
}

/**
 * Transform RTDB healthLatest entry.
 */
export function transformHealthLatest({ propertyId, deviceId, data }) {
  return {
    property_id: propertyId,
    device_id: deviceId,
    health_received_at_ms: data.healthReceivedAtMs ?? data.health_received_at_ms ?? fbTimestampToMs(data.receivedAt) ?? null,
    payload: JSON.stringify(data),
    updated_at: new Date().toISOString(),
  };
}

/**
 * Transform RTDB healthHistory entry.
 */
export function transformHealthHistory({ propertyId, deviceId, dayKey, historyId, data }) {
  return {
    property_id: propertyId,
    device_id: deviceId,
    history_id: historyId,
    day_key: dayKey,
    health_received_at_ms: data.healthReceivedAtMs ?? data.health_received_at_ms ?? fbTimestampToMs(data.receivedAt) ?? null,
    payload: JSON.stringify(data),
    created_at: new Date().toISOString(),
  };
}

/**
 * Transform RTDB propertyEvents entry.
 */
export function transformPropertyEvent({ propertyId, dayKey, eventId, data }) {
  return {
    property_id: propertyId,
    day_key: dayKey,
    event_id: eventId,
    device_id: normalizeText(data.deviceId ?? data.device_id) || null,
    gateway_id: normalizeText(data.gatewayId ?? data.gateway_id) || null,
    event_type: normalizeText(data.eventType ?? data.event_type ?? data.type) || null,
    lat: typeof data.lat === 'number' ? data.lat : null,
    lon: typeof data.lon === 'number' ? data.lon : null,
    position_received_at_ms: data.positionReceivedAtMs ?? data.position_received_at_ms ?? null,
    received_at_ms: data.receivedAtMs ?? data.received_at_ms ?? fbTimestampToMs(data.receivedAt) ?? null,
    payload: JSON.stringify(data),
    created_at: new Date().toISOString(),
  };
}

/**
 * Transform RTDB matrixBindings entry.
 */
export function transformMatrixBinding({ runtimeId, data }) {
  return {
    runtime_id: runtimeId,
    property_id: normalizeId(data.propertyId ?? data.property_id) || null,
    property_scope_id: normalizeText(data.propertyScopeId ?? data.property_scope_id) || null,
    matrix_gateway_id: normalizeText(data.matrixGatewayId ?? data.matrix_gateway_id) || null,
    enabled: data.enabled ?? false,
    updated_at_ms: data.updatedAtMs ?? data.updated_at_ms ?? null,
    raw: JSON.stringify(data),
    updated_at: new Date().toISOString(),
  };
}

/**
 * Transform RTDB matrixQueueKeys entry.
 */
export function transformMatrixQueueKey({ runtimeId, data }) {
  return {
    runtime_id: runtimeId,
    queue_key: normalizeText(data.queueKey ?? data.queue_key) || null,
    writer_key: normalizeText(data.writerKey ?? data.writer_key) || null,
    updated_at_ms: data.updatedAtMs ?? data.updated_at_ms ?? null,
    raw: JSON.stringify(data),
    updated_at: new Date().toISOString(),
  };
}

/**
 * Transform RTDB matrixCommandQueues entry.
 */
export function transformMatrixCommandQueue({ runtimeId, queueKey, commandId, data }) {
  return {
    runtime_id: runtimeId,
    queue_key: queueKey,
    command_id: commandId,
    created_at_ms: data.createdAtMs ?? data.created_at_ms ?? null,
    expires_at_ms: data.expiresAtMs ?? data.expires_at_ms ?? null,
    payload: JSON.stringify(data),
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };
}

/**
 * Transform RTDB matrixCommandResults entry.
 */
export function transformMatrixCommandResult({ runtimeId, commandId, data }) {
  return {
    runtime_id: runtimeId,
    command_id: commandId,
    updated_at_ms: data.updatedAtMs ?? data.updated_at_ms ?? null,
    payload: JSON.stringify(data),
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };
}
