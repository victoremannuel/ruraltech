/**
 * auto-sync-property-fence
 *
 * Disparado por webhook de banco quando `rural_properties.points` muda.
 * Gera automaticamente um SET_FENCE para todas as coleiras aptas da propriedade.
 *
 * Contrato de entrada (POST body):
 *   type: "UPDATE"
 *   table: "rural_properties"
 *   record: { id, points, property_scope_id, ... }   // novo estado
 *   old_record: { id, points, ... }                   // estado anterior
 *
 * Idempotência: commandId = AUTO_PROPERTY_FENCE:{propertyId}:{polygonHash}:{targetSetHash}
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
// Helpers de canonicalização e hash
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

async function polygonHash(points: LatLon[]): Promise<string> {
  const canonical = points
    .map((p) => `${p.lat.toFixed(7)},${p.lon.toFixed(7)}`)
    .join("|");
  return hashString(canonical);
}

async function targetSetHash(ids: string[]): Promise<string> {
  return hashString([...ids].sort().join(","));
}

function deterministicCommandId(
  propertyId: string,
  pHash: string,
  tHash: string,
): string {
  return `AUTO_PROPERTY_FENCE:${propertyId}:${pHash}:${tHash}`;
}

// ---------------------------------------------------------------------------
// Resolução de matriz e coleiras
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

async function resolveReadyCollars(
  admin: ReturnType<typeof createAdminClient>,
  propertyId: string,
  propertyScopeId: string,
): Promise<string[]> {
  const { data: collars, error } = await admin
    .from("collars")
    .select("id, property_id, property_scope_id, binding_ready, supports_scoped_lora, runtime_status")
    .eq("property_id", propertyId);
  if (error) throw new Error(error.message);
  const ids: string[] = [];
  for (const c of (collars ?? []) as JsonMap[]) {
    const id = normalizeId(c.id);
    if (!id) continue;
    if (!entityMatchesProperty(c, propertyId, propertyScopeId)) continue;
    if (!isTargetReady(c, propertyScopeId)) continue;
    ids.push(id);
  }
  return ids.sort();
}

// ---------------------------------------------------------------------------
// Registro de auditoria de falha
// ---------------------------------------------------------------------------

async function recordAutoSyncFailure(
  admin: ReturnType<typeof createAdminClient>,
  propertyId: string,
  reason: string,
  details: JsonMap,
): Promise<void> {
  try {
    await admin.from("property_command_events").insert({
      property_id: propertyId,
      day_key: new Date().toISOString().slice(0, 10).replaceAll("-", ""),
      event_id: `AUTO_PROP_FAIL_${Date.now()}_${crypto.randomUUID().slice(0, 8)}`,
      command_id: `auto_property_fence_${propertyId}`,
      status: "auto_sync_failed",
      received_at_ms: Date.now(),
      payload: { type: "auto_sync_failed", reason, ...details },
      raw: { type: "auto_sync_failed", reason, ...details },
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

  const propertyId = normalizeId(record.id);
  if (!propertyId) {
    return jsonResponse(400, { ok: false, reason: "missing_property_id" });
  }

  // Canonicalizar polígonos novo e antigo
  const newPoints = canonicalizePoints(record.points);
  const oldPoints = canonicalizePoints(oldRecord.points);

  if (newPoints.length < 3) {
    return jsonResponse(200, { ok: true, skipped: true, reason: "insufficient_points" });
  }

  const [newPHash, oldPHash] = await Promise.all([
    polygonHash(newPoints),
    polygonHash(oldPoints),
  ]);

  // Sem mudança efetiva no polígono → não gerar comando
  if (eventType === "UPDATE" && newPHash === oldPHash) {
    return jsonResponse(200, { ok: true, skipped: true, reason: "polygon_unchanged" });
  }

  const admin = createAdminClient();

  const propertyScopeId = normalizeScopeId(record.property_scope_id) ||
    await computePropertyScopeId(propertyId);

  // Resolver matriz
  const matrix = await resolveMatrix(admin, propertyId, propertyScopeId);
  if (!matrix) {
    await recordAutoSyncFailure(admin, propertyId, "no_matrix_for_property", {
      propertyId,
      propertyScopeId,
    });
    return jsonResponse(200, {
      ok: false,
      skipped: true,
      reason: "no_matrix_for_property",
      propertyId,
    });
  }

  // Verificar matriz pronta
  if (!isTargetReady(matrix.gatewayData, propertyScopeId)) {
    await recordAutoSyncFailure(admin, propertyId, "matrix_not_ready", {
      propertyId,
      matrixGatewayId: matrix.gatewayId,
    });
    return jsonResponse(200, {
      ok: false,
      skipped: true,
      reason: "matrix_not_ready",
      matrixGatewayId: matrix.gatewayId,
    });
  }

  // Resolver coleiras aptas
  const targetIds = await resolveReadyCollars(admin, propertyId, propertyScopeId);
  if (!targetIds.length) {
    // Auditável, mas não é erro fatal
    return jsonResponse(200, {
      ok: true,
      skipped: true,
      reason: "no_ready_collars",
      propertyId,
    });
  }

  const tHash = await targetSetHash(targetIds);
  const commandId = deterministicCommandId(propertyId, newPHash, tHash);

  // Verificar se já existe este comando (idempotência)
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

  // Recuperar queue_key da matriz
  const { data: queueKeyRow, error: qKeyErr } = await admin
    .from("matrix_queue_keys")
    .select("queue_key")
    .eq("runtime_id", matrix.runtimeId)
    .maybeSingle();
  if (qKeyErr) throw new Error(qKeyErr.message);
  const queueKey = extractQueueKey(queueKeyRow?.queue_key);
  if (!queueKey) {
    await recordAutoSyncFailure(admin, propertyId, "missing_matrix_queue_key", {
      matrixGatewayId: matrix.gatewayId,
      matrixRuntimeId: matrix.runtimeId,
    });
    return jsonResponse(200, {
      ok: false,
      skipped: true,
      reason: "missing_matrix_queue_key",
    });
  }

  // Montar payload do comando
  const nowMs = Date.now();
  const expiresAtMs = nowMs + 15 * 60 * 1000; // 15 min TTL para SET_FENCE
  const updatedByUid = normalizeId(record.updated_by_uid ?? record.updatedByUid) || "system";

  const commandPayload: JsonMap = {
    cmd_id: commandId,
    command_id: commandId,
    polygon_kind: "property",
    origin_doc_type: "ruralProperty",
    origin_doc_id: propertyId,
    property_id: propertyId,
    property_scope_id: propertyScopeId,
    matrix_gateway_id: matrix.gatewayId,
    target_device_ids: targetIds,
    requested_by_uid: updatedByUid,
    requested_by_role: "system",
    requested_at_ms: nowMs,
    points: newPoints,
  };

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
    polygon_kind: "property",
    origin_doc_type: "ruralProperty",
    origin_doc_id: propertyId,
    target_device_ids: targetIds,
    target_gateway_ids: [],
    device_results: Object.fromEntries(
      targetIds.map((id) => [id, { status: "queued", updatedAtMs: nowMs }]),
    ),
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
      polygonKind: "property",
      originDocType: "ruralProperty",
      originDocId: propertyId,
      businessRef: { type: "ruralProperty", id: propertyId },
      deviceResults: Object.fromEntries(
        targetIds.map((id) => [id, { status: "queued", updatedAtMs: nowMs }]),
      ),
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
    businessRef: { type: "ruralProperty", id: propertyId },
  };

  const eventId = `auto_prop_${Date.now()}_queued_${commandId.slice(-8)}`;
  const dayKey = new Date(nowMs).toISOString().slice(0, 10).replaceAll("-", "");

  // Persistir em paralelo
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
        origin: "auto_sync_property",
      },
      raw: {
        type: "queued",
        status: "queued",
        matrixId: matrix.runtimeId,
        createdAtMs: nowMs,
        origin: "auto_sync_property",
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
    propertyId,
    propertyScopeId,
    matrixGatewayId: matrix.gatewayId,
    matrixRuntimeId: matrix.runtimeId,
    targetDeviceIds: targetIds,
    polygonHash: newPHash,
    targetSetHash: tHash,
  });
});
