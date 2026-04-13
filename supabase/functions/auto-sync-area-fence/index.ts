/**
 * auto-sync-area-fence
 *
 * Disparado por webhook de banco quando `areas.perimeter` ou
 * `areas.linked_device_ids` muda.
 *
 * Gera automaticamente um SET_FENCE seletivo para as coleiras vinculadas
 * à área e atualiza o espelho operacional `active_area_id` em cada coleira.
 *
 * Contrato de entrada (POST body):
 *   type: "UPDATE" | "INSERT"
 *   table: "areas"
 *   record: { id, property_id, perimeter, linked_device_ids, source, ... }
 *   old_record: { ... }
 *
 * Idempotência: commandId = AUTO_AREA_FENCE:{areaId}:{perimeterHash}:{targetSetHash}
 *
 * Bypass: se `record.source === "herding_operation"`, a propagaçao é ignorada
 * para evitar conflito semântico com condução ativa.
 */

import {
  computePropertyScopeId,
  corsHeaders,
  createAdminClient,
  entityMatchesProperty,
  extractQueueKey,
  isTargetReady,
  jsonResponse,
  matrixRuntimeIdFromGatewayData,
  normalizeDeviceIdList,
  normalizeId,
  normalizeScopeId,
  normalizeText,
  type JsonMap,
} from "../_shared/supabase.ts";

// ---------------------------------------------------------------------------
// Helpers de canonicalização e hash (idênticos ao auto-sync-property-fence)
// ---------------------------------------------------------------------------

type LatLon = { lat: number; lon: number };

function canonicalizePoints(raw: unknown): LatLon[] {
  if (!Array.isArray(raw)) return [];
  const out: LatLon[] = [];
  for (const p of raw) {
    if (Array.isArray(p) && p.length >= 2) {
      const lat = Number(p[0]);
      const lon = Number(p[1]);
      if (!isFinite(lat) || !isFinite(lon)) continue;
      out.push({ lat, lon });
      continue;
    }
    if (p && typeof p === "object") {
      const lat = Number((p as JsonMap).lat ?? (p as JsonMap).latitude);
      const lon = Number(
        (p as JsonMap).lon ?? (p as JsonMap).lng ?? (p as JsonMap).longitude,
      );
      if (!isFinite(lat) || !isFinite(lon)) continue;
      out.push({ lat, lon });
    }
  }
  return out;
}

async function hashString(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 16)
    .toUpperCase();
}

async function perimeterHash(points: LatLon[]): Promise<string> {
  const canonical = points
    .map((p) => `${p.lat.toFixed(7)},${p.lon.toFixed(7)}`)
    .join("|");
  return hashString(canonical);
}

async function targetSetHash(ids: string[]): Promise<string> {
  return hashString([...ids].sort().join(","));
}

function deterministicCommandId(
  areaId: string,
  pHash: string,
  tHash: string,
): string {
  return `AUTO_AREA_FENCE:${areaId}:${pHash}:${tHash}`;
}

// ---------------------------------------------------------------------------
// Resolução de matriz
// ---------------------------------------------------------------------------

async function resolveMatrix(
  admin: ReturnType<typeof createAdminClient>,
  propertyId: string,
  propertyScopeId: string,
): Promise<{ gatewayId: string; gatewayData: JsonMap; runtimeId: string } | null> {
  const { data: gateways, error } = await admin.from("gateways").select("*");
  if (error) throw new Error(error.message);
  for (const gw of (gateways ?? []) as JsonMap[]) {
    if (gw.is_matrix !== true && gw.isMatrix !== true) continue;
    if (!entityMatchesProperty(gw, propertyId, propertyScopeId)) continue;
    const gatewayId = normalizeId(gw.id);
    if (!gatewayId) continue;
    const runtimeId = matrixRuntimeIdFromGatewayData(gatewayId, gw);
    return { gatewayId, gatewayData: gw, runtimeId };
  }
  return null;
}

// ---------------------------------------------------------------------------
// Validação dos linked_device_ids contra a propriedade
// ---------------------------------------------------------------------------

async function resolveValidLinkedCollars(
  admin: ReturnType<typeof createAdminClient>,
  propertyId: string,
  propertyScopeId: string,
  linkedDeviceIds: string[],
): Promise<{ validIds: string[]; invalidIds: string[] }> {
  const validIds: string[] = [];
  const invalidIds: string[] = [];

  for (const deviceId of linkedDeviceIds) {
    const { data: collar, error } = await admin
      .from("collars")
      .select("id, property_id, property_scope_id, binding_ready, supports_scoped_lora, runtime_status")
      .eq("id", deviceId)
      .maybeSingle();

    if (error || !collar) {
      invalidIds.push(deviceId);
      continue;
    }

    const c = collar as JsonMap;
    if (!entityMatchesProperty(c, propertyId, propertyScopeId)) {
      invalidIds.push(deviceId);
      continue;
    }
    if (!isTargetReady(c, propertyScopeId)) {
      invalidIds.push(deviceId);
      continue;
    }
    validIds.push(deviceId);
  }

  return { validIds: validIds.sort(), invalidIds };
}

// ---------------------------------------------------------------------------
// Atualizar espelho operacional active_area_id nas coleiras vinculadas
// ---------------------------------------------------------------------------

async function updateActiveAreaMirror(
  admin: ReturnType<typeof createAdminClient>,
  areaId: string,
  validCollarIds: string[],
  removedCollarIds: string[],
): Promise<void> {
  const tasks: Promise<unknown>[] = [];

  if (validCollarIds.length > 0) {
    tasks.push(
      admin
        .from("collars")
        .update({ active_area_id: areaId })
        .in("id", validCollarIds),
    );
  }

  // Coleiras que foram removidas do vínculo: limpar active_area_id se for desta área
  if (removedCollarIds.length > 0) {
    tasks.push(
      admin
        .from("collars")
        .update({ active_area_id: null })
        .in("id", removedCollarIds)
        .eq("active_area_id", areaId),
    );
  }

  await Promise.all(tasks);
}

// ---------------------------------------------------------------------------
// Registro de auditoria de falha
// ---------------------------------------------------------------------------

async function recordAutoSyncFailure(
  admin: ReturnType<typeof createAdminClient>,
  propertyId: string,
  areaId: string,
  reason: string,
  details: JsonMap,
): Promise<void> {
  try {
    await admin.from("property_command_events").insert({
      property_id: propertyId,
      day_key: new Date().toISOString().slice(0, 10).replaceAll("-", ""),
      event_id: `AUTO_AREA_FAIL_${Date.now()}_${crypto.randomUUID().slice(0, 8)}`,
      command_id: `auto_area_fence_${areaId}`,
      status: "auto_sync_failed",
      received_at_ms: Date.now(),
      payload: { type: "auto_sync_failed", reason, areaId, ...details },
      raw: { type: "auto_sync_failed", reason, areaId, ...details },
    });
  } catch (_) {
    // não deixar falha de auditoria derrubar o handler
  }
}

// ---------------------------------------------------------------------------
// Handler principal
// ---------------------------------------------------------------------------

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders() });
  }
  if (request.method !== "POST") {
    return jsonResponse(405, { ok: false, reason: "method_not_allowed" });
  }

  let body: JsonMap;
  try {
    body = await request.json() as JsonMap;
  } catch (_) {
    return jsonResponse(400, { ok: false, reason: "invalid_json" });
  }

  const eventType = normalizeText(body.type).toUpperCase();
  if (eventType !== "UPDATE" && eventType !== "INSERT") {
    return jsonResponse(200, { ok: true, skipped: true, reason: "not_an_update" });
  }

  const record = (body.record ?? {}) as JsonMap;
  const oldRecord = (body.old_record ?? {}) as JsonMap;

  // Bypass para atualizações originadas por herding_operation
  const source = normalizeText(record.source);
  if (source === "herding_operation") {
    return jsonResponse(200, {
      ok: true,
      skipped: true,
      reason: "bypass_herding_source",
    });
  }

  const areaId = normalizeId(record.id);
  if (!areaId) {
    return jsonResponse(400, { ok: false, reason: "missing_area_id" });
  }

  const propertyId = normalizeId(record.property_id ?? record.propertyId);
  if (!propertyId) {
    return jsonResponse(400, { ok: false, reason: "missing_property_id" });
  }

  // Canonicalizar perímetros e linked_device_ids
  const newPerimeter = canonicalizePoints(record.perimeter);
  const oldPerimeter = canonicalizePoints(oldRecord.perimeter);

  const newLinkedRaw = normalizeDeviceIdList(record.linked_device_ids ?? record.linkedDeviceIds);
  const oldLinkedRaw = normalizeDeviceIdList(oldRecord.linked_device_ids ?? oldRecord.linkedDeviceIds);

  if (newPerimeter.length < 3) {
    return jsonResponse(200, { ok: true, skipped: true, reason: "insufficient_perimeter_points" });
  }

  const [newPHash, oldPHash] = await Promise.all([
    perimeterHash(newPerimeter),
    perimeterHash(oldPerimeter),
  ]);

  const newLinkedSorted = [...newLinkedRaw].sort().join(",");
  const oldLinkedSorted = [...oldLinkedRaw].sort().join(",");

  const perimeterChanged = newPHash !== oldPHash;
  const devicesChanged = newLinkedSorted !== oldLinkedSorted;

  if (eventType === "UPDATE" && !perimeterChanged && !devicesChanged) {
    return jsonResponse(200, { ok: true, skipped: true, reason: "no_relevant_change" });
  }

  const admin = createAdminClient();

  // Resolver scope da propriedade
  const { data: propertyRow } = await admin
    .from("rural_properties")
    .select("property_scope_id")
    .eq("id", propertyId)
    .maybeSingle();

  const propertyScopeId = normalizeScopeId(
    (propertyRow as JsonMap | null)?.property_scope_id,
  ) || await computePropertyScopeId(propertyId);

  // Coleiras removidas do vínculo
  const removedCollarIds = oldLinkedRaw.filter((id) => !newLinkedRaw.includes(id));

  // Atualizar espelho operacional (mesmo que não haja coleiras válidas para enviar)
  if (newLinkedRaw.length === 0 && removedCollarIds.length > 0) {
    await updateActiveAreaMirror(admin, areaId, [], removedCollarIds);
    return jsonResponse(200, {
      ok: true,
      skipped: true,
      reason: "no_linked_devices",
      mirrorCleared: removedCollarIds,
    });
  }

  if (newLinkedRaw.length === 0) {
    return jsonResponse(200, { ok: true, skipped: true, reason: "no_linked_devices" });
  }

  // Validar coleiras contra a propriedade
  const { validIds: targetIds, invalidIds } = await resolveValidLinkedCollars(
    admin,
    propertyId,
    propertyScopeId,
    newLinkedRaw,
  );

  // Atualizar espelho operacional para coleiras válidas e limpar removidas
  await updateActiveAreaMirror(admin, areaId, targetIds, removedCollarIds);

  if (!targetIds.length) {
    return jsonResponse(200, {
      ok: true,
      skipped: true,
      reason: "no_ready_linked_collars",
      invalidIds,
      propertyId,
      areaId,
    });
  }

  const tHash = await targetSetHash(targetIds);
  const commandId = deterministicCommandId(areaId, newPHash, tHash);

  // Verificar idempotência
  const { data: existing } = await admin
    .from("property_commands")
    .select("command_id, status")
    .eq("command_id", commandId)
    .maybeSingle();

  if (existing) {
    return jsonResponse(200, {
      ok: true,
      skipped: true,
      reason: "command_already_exists",
      commandId,
      existingStatus: (existing as JsonMap).status,
    });
  }

  // Resolver matriz
  const matrix = await resolveMatrix(admin, propertyId, propertyScopeId);
  if (!matrix) {
    await recordAutoSyncFailure(admin, propertyId, areaId, "no_matrix_for_property", {
      propertyScopeId,
    });
    return jsonResponse(200, {
      ok: false,
      skipped: true,
      reason: "no_matrix_for_property",
      propertyId,
      areaId,
    });
  }

  if (!isTargetReady(matrix.gatewayData, propertyScopeId)) {
    await recordAutoSyncFailure(admin, propertyId, areaId, "matrix_not_ready", {
      matrixGatewayId: matrix.gatewayId,
    });
    return jsonResponse(200, {
      ok: false,
      skipped: true,
      reason: "matrix_not_ready",
      matrixGatewayId: matrix.gatewayId,
    });
  }

  // Recuperar queue_key
  const { data: queueKeyRow, error: qKeyErr } = await admin
    .from("matrix_queue_keys")
    .select("queue_key")
    .eq("runtime_id", matrix.runtimeId)
    .maybeSingle();
  if (qKeyErr) throw new Error(qKeyErr.message);
  const queueKey = extractQueueKey(queueKeyRow?.queue_key);
  if (!queueKey) {
    await recordAutoSyncFailure(admin, propertyId, areaId, "missing_matrix_queue_key", {
      matrixGatewayId: matrix.gatewayId,
    });
    return jsonResponse(200, { ok: false, skipped: true, reason: "missing_matrix_queue_key" });
  }

  const nowMs = Date.now();
  const expiresAtMs = nowMs + 15 * 60 * 1000;
  const updatedByUid = normalizeId(record.updated_by_uid ?? record.updatedByUid) || "system";

  // Serializar points no formato esperado pelo firmware: [[lat, lon], ...]
  // A canonicalização interna {lat, lon} é usada apenas para hash/idempotência.
  const pointsForFirmware = newPerimeter.map((p) => [p.lat, p.lon]);

  const commandPayload: JsonMap = {
    cmd_id: commandId,
    command_id: commandId,
    polygon_kind: "area",
    origin_doc_type: "area",
    origin_doc_id: areaId,
    property_id: propertyId,
    property_scope_id: propertyScopeId,
    matrix_gateway_id: matrix.gatewayId,
    target_device_ids: targetIds,
    requested_by_uid: updatedByUid,
    requested_by_role: "system",
    requested_at_ms: nowMs,
    points: pointsForFirmware,
  };

  const deviceResults = Object.fromEntries(
    targetIds.map((id) => [id, { status: "queued", updatedAtMs: nowMs }]),
  );

  const commandSummary: JsonMap = {
    property_id: propertyId,
    command_id: commandId,
    command: "SET_FENCE",
    status: "queued",
    property_scope_id: propertyScopeId,
    matrix_gateway_id: matrix.gatewayId,
    requested_by_uid: updatedByUid,
    requested_by_role: "system",
    created_at_ms: nowMs,
    updated_at_ms: nowMs,
    expires_at_ms: expiresAtMs,
    polygon_kind: "area",
    origin_doc_type: "area",
    origin_doc_id: areaId,
    target_device_ids: targetIds,
    target_gateway_ids: [],
    device_results: deviceResults,
    payload: commandPayload,
    raw: {
      commandId,
      command: "SET_FENCE",
      propertyId,
      propertyScopeId,
      matrixGatewayId: matrix.gatewayId,
      matrixRuntimeId: matrix.runtimeId,
      targetDeviceIds: targetIds,
      targetGatewayIds: [],
      requestedByUid: updatedByUid,
      requestedByRole: "system",
      status: "queued",
      createdAtMs: nowMs,
      updatedAtMs: nowMs,
      expiresAtMs,
      polygonKind: "area",
      originDocType: "area",
      originDocId: areaId,
      businessRef: { type: "area", id: areaId },
      deviceResults,
      payload: commandPayload,
    },
  };

  const queuePayload: JsonMap = {
    commandId,
    command: "SET_FENCE",
    propertyId,
    propertyScopeId,
    matrixGatewayId: matrix.gatewayId,
    matrixRuntimeId: matrix.runtimeId,
    targetDeviceIds: targetIds,
    targetGatewayIds: [],
    payload: commandPayload,
    requestedByUid: updatedByUid,
    requestedByRole: "system",
    createdAtMs: nowMs,
    expiresAtMs,
    businessRef: { type: "area", id: areaId },
  };

  const dayKey = new Date(nowMs).toISOString().slice(0, 10).replaceAll("-", "");
  const eventId = `auto_area_${Date.now()}_queued_${commandId.slice(-8)}`;

  const [cmdResult, evtResult, queueResult] = await Promise.all([
    admin.from("property_commands").upsert(commandSummary),
    admin.from("property_command_events").upsert({
      property_id: propertyId,
      day_key: dayKey,
      event_id: eventId,
      command_id: commandId,
      status: "queued",
      received_at_ms: nowMs,
      payload: {
        type: "queued",
        status: "queued",
        matrixId: matrix.runtimeId,
        createdAtMs: nowMs,
        origin: "auto_sync_area",
        areaId,
      },
      raw: {
        type: "queued",
        status: "queued",
        matrixId: matrix.runtimeId,
        createdAtMs: nowMs,
        origin: "auto_sync_area",
        areaId,
      },
    }),
    admin.from("matrix_command_queues").upsert({
      runtime_id: matrix.runtimeId,
      queue_key: queueKey,
      command_id: commandId,
      created_at_ms: nowMs,
      expires_at_ms: expiresAtMs,
      payload: queuePayload,
    }),
  ]);

  if (cmdResult.error) throw new Error(cmdResult.error.message);
  if (evtResult.error) throw new Error(evtResult.error.message);
  if (queueResult.error) throw new Error(queueResult.error.message);

  return jsonResponse(200, {
    ok: true,
    commandId,
    areaId,
    propertyId,
    propertyScopeId,
    matrixGatewayId: matrix.gatewayId,
    matrixRuntimeId: matrix.runtimeId,
    targetDeviceIds: targetIds,
    invalidCollarIds: invalidIds,
    mirrorUpdated: targetIds,
    mirrorCleared: removedCollarIds,
    perimeterHash: newPHash,
    targetSetHash: tHash,
    perimeterChanged,
    devicesChanged,
  });
});
