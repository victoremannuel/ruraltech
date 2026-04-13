import {
  ALLOWED_COMMANDS,
  commandExpiryMs,
  computePropertyScopeId,
  corsHeaders,
  createAdminClient,
  entityMatchesProperty,
  extractQueueKey,
  getAuthContext,
  getCollarById,
  getGatewayById,
  getPropertyById,
  isTargetReady,
  jsonResponse,
  listGateways,
  matrixRuntimeIdFromGatewayData,
  normalizeBusinessRef,
  normalizeDeviceIdList,
  normalizeId,
  normalizeIdList,
  normalizeRole,
  normalizeScopeId,
  normalizeText,
  type JsonMap,
  userHasPropertyAccess,
} from "../_shared/supabase.ts";

function eventIdFor(commandId: string, status: string): string {
  return `${Date.now()}_${status}_${crypto.randomUUID().slice(0, 8)}_${commandId}`;
}

function derivePolygonKind(
  command: string,
  originDocType: string,
  businessRef: { type: string; id: string } | null,
): string {
  if (command === "SET_HERDING_PLAN") return "herding";
  if (command !== "SET_FENCE") return "";
  if (originDocType === "area" || businessRef?.type === "area") return "area";
  if (
    originDocType === "ruralProperty" || originDocType === "rural_property" ||
    businessRef?.type === "ruralProperty" || businessRef?.type === "rural_property"
  ) {
    return "property";
  }
  return "";
}

function buildDispatchPayload(
  commandId: string,
  command: string,
  sourcePayload: JsonMap,
  businessRef: { type: string; id: string } | null,
): {
  payload: JsonMap;
  polygonKind: string;
  originDocType: string;
  originDocId: string;
} {
  const originDocType = normalizeText(
    sourcePayload.origin_doc_type ??
      sourcePayload.originDocType ??
      businessRef?.type,
  );
  const originDocId = normalizeId(
    sourcePayload.origin_doc_id ??
      sourcePayload.originDocId ??
      businessRef?.id ??
      sourcePayload.operation_id,
  );
  const polygonKind = normalizeText(
    sourcePayload.polygon_kind ??
      sourcePayload.polygonKind ??
      derivePolygonKind(command, originDocType, businessRef),
  );

  const payload: JsonMap = {
    ...sourcePayload,
    cmd_id: normalizeText(sourcePayload.cmd_id ?? sourcePayload.command_id) || commandId,
    command_id:
      normalizeText(sourcePayload.command_id ?? sourcePayload.cmd_id) || commandId,
  };
  if (polygonKind) payload.polygon_kind = polygonKind;
  if (originDocType) payload.origin_doc_type = originDocType;
  if (originDocId) payload.origin_doc_id = originDocId;

  return {
    payload,
    polygonKind,
    originDocType,
    originDocId,
  };
}

async function resolveMatrixGateway(
  explicitMatrixGatewayId: string,
  propertyId: string,
  propertyScopeId: string,
) {
  const admin = createAdminClient();
  if (explicitMatrixGatewayId) {
    const matrixData = await getGatewayById(admin, explicitMatrixGatewayId);
    if (!matrixData) return null;
    return { gatewayId: explicitMatrixGatewayId, gatewayData: matrixData };
  }

  const gateways = await listGateways(admin);
  for (const gateway of gateways) {
    if (gateway.is_matrix !== true && gateway.isMatrix !== true) continue;
    if (!entityMatchesProperty(gateway, propertyId, propertyScopeId)) continue;
    const gatewayId = normalizeId(gateway.id);
    if (!gatewayId) continue;
    return { gatewayId, gatewayData: gateway };
  }
  return null;
}

async function validateTargets(
  propertyId: string,
  propertyScopeId: string,
  targetDeviceIds: string[],
  targetGatewayIds: string[],
): Promise<{ ok: boolean; resultReason: string | null; deviceResults: JsonMap }> {
  const admin = createAdminClient();
  const deviceResults: JsonMap = {};

  for (const deviceId of targetDeviceIds) {
    const collar = await getCollarById(admin, deviceId);
    if (!collar) {
      return { ok: false, resultReason: `unknown_target_device:${deviceId}`, deviceResults };
    }
    if (!entityMatchesProperty(collar, propertyId, propertyScopeId)) {
      return {
        ok: false,
        resultReason: `target_device_property_mismatch:${deviceId}`,
        deviceResults,
      };
    }
    if (!isTargetReady(collar, propertyScopeId)) {
      return {
        ok: false,
        resultReason: `target_device_not_ready:${deviceId}`,
        deviceResults,
      };
    }
    deviceResults[deviceId] = {
      status: "validated",
      updatedAtMs: Date.now(),
    };
  }

  for (const gatewayId of targetGatewayIds) {
    const gateway = await getGatewayById(admin, gatewayId);
    if (!gateway) {
      return { ok: false, resultReason: `unknown_target_gateway:${gatewayId}`, deviceResults };
    }
    if (!entityMatchesProperty(gateway, propertyId, propertyScopeId)) {
      return {
        ok: false,
        resultReason: `target_gateway_property_mismatch:${gatewayId}`,
        deviceResults,
      };
    }
    if (!isTargetReady(gateway, propertyScopeId)) {
      return {
        ok: false,
        resultReason: `target_gateway_not_ready:${gatewayId}`,
        deviceResults,
      };
    }
  }

  return { ok: true, resultReason: null, deviceResults };
}

async function upsertCommandRecords(args: {
  propertyId: string;
  propertyScopeId: string;
  matrixGatewayId: string;
  matrixRuntimeId: string;
  queueKey: string;
  commandId: string;
  command: string;
  targetDeviceIds: string[];
  targetGatewayIds: string[];
  requestedByUid: string;
  requestedByRole: string;
  deviceResults: JsonMap;
  payload: JsonMap;
  polygonKind: string;
  originDocType: string;
  originDocId: string;
  businessRef: { type: string; id: string } | null;
  createdAtMs: number;
  expiresAtMs: number;
}) {
  const admin = createAdminClient();
  const commandSummary = {
    property_id: args.propertyId,
    command_id: args.commandId,
    command: args.command,
    status: "queued",
    property_scope_id: args.propertyScopeId,
    matrix_gateway_id: args.matrixGatewayId,
    requested_by_uid: args.requestedByUid,
    requested_by_role: args.requestedByRole,
    created_at_ms: args.createdAtMs,
    updated_at_ms: args.createdAtMs,
    expires_at_ms: args.expiresAtMs,
    polygon_kind: args.polygonKind || null,
    origin_doc_type: args.originDocType || null,
    origin_doc_id: args.originDocId || null,
    target_device_ids: args.targetDeviceIds,
    target_gateway_ids: args.targetGatewayIds,
    device_results: args.deviceResults,
    payload: args.payload,
    raw: {
      commandId: args.commandId,
      command: args.command,
      propertyId: args.propertyId,
      propertyScopeId: args.propertyScopeId,
      matrixGatewayId: args.matrixGatewayId,
      matrixRuntimeId: args.matrixRuntimeId,
      targetDeviceIds: args.targetDeviceIds,
      targetGatewayIds: args.targetGatewayIds,
      requestedByUid: args.requestedByUid,
      requestedByRole: args.requestedByRole,
      status: "queued",
      createdAtMs: args.createdAtMs,
      updatedAtMs: args.createdAtMs,
      expiresAtMs: args.expiresAtMs,
      polygonKind: args.polygonKind || null,
      originDocType: args.originDocType || null,
      originDocId: args.originDocId || null,
      businessRef: args.businessRef,
      deviceResults: args.deviceResults,
      payload: args.payload,
    },
  };
  const queuedEventId = eventIdFor(args.commandId, "queued");
  const queuedEvent = {
    property_id: args.propertyId,
    day_key: new Date(args.createdAtMs).toISOString().slice(0, 10).replaceAll("-", ""),
    event_id: queuedEventId,
    command_id: args.commandId,
    status: "queued",
    received_at_ms: args.createdAtMs,
    payload: {
      type: "queued",
      status: "queued",
      matrixId: args.matrixRuntimeId,
      createdAtMs: args.createdAtMs,
    },
    raw: {
      type: "queued",
      status: "queued",
      matrixId: args.matrixRuntimeId,
      createdAtMs: args.createdAtMs,
    },
  };
  const queuePayload = {
    commandId: args.commandId,
    command: args.command,
    propertyId: args.propertyId,
    propertyScopeId: args.propertyScopeId,
    matrixGatewayId: args.matrixGatewayId,
    matrixRuntimeId: args.matrixRuntimeId,
    targetDeviceIds: args.targetDeviceIds,
    targetGatewayIds: args.targetGatewayIds,
    payload: args.payload,
    requestedByUid: args.requestedByUid,
    requestedByRole: args.requestedByRole,
    createdAtMs: args.createdAtMs,
    expiresAtMs: args.expiresAtMs,
    ...(args.businessRef ? { businessRef: args.businessRef } : {}),
  };

  const commandUpsert = await admin.from("property_commands").upsert(commandSummary);
  if (commandUpsert.error) throw new Error(commandUpsert.error.message);

  const eventInsert = await admin.from("property_command_events").upsert(queuedEvent);
  if (eventInsert.error) throw new Error(eventInsert.error.message);

  const queueInsert = await admin.from("matrix_command_queues").upsert({
    runtime_id: args.matrixRuntimeId,
    queue_key: args.queueKey,
    command_id: args.commandId,
    created_at_ms: args.createdAtMs,
    expires_at_ms: args.expiresAtMs,
    payload: queuePayload,
  });
  if (queueInsert.error) throw new Error(queueInsert.error.message);
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders() });
  }
  if (request.method !== "POST") {
    return jsonResponse(405, { ok: false, reason: "method_not_allowed" });
  }

  try {
    const admin = createAdminClient();
    const auth = await getAuthContext(request, admin);
    const body = await request.json() as JsonMap;
    const normalizedCommand = normalizeText(body.command).toUpperCase();
    if (!ALLOWED_COMMANDS.has(normalizedCommand)) {
      return jsonResponse(400, { ok: false, reason: "unsupported_command" });
    }

    const propertyId = normalizeId(body.propertyId);
    if (!propertyId) {
      return jsonResponse(400, { ok: false, reason: "invalid_property_id" });
    }

    const propertyData = await getPropertyById(admin, propertyId);
    if (!propertyData) {
      return jsonResponse(404, { ok: false, reason: "property_not_found" });
    }
    const expectedScopeId = normalizeScopeId(propertyData.property_scope_id) ||
      await computePropertyScopeId(propertyId);
    const requestedScopeId = normalizeScopeId(body.propertyScopeId);
    if (requestedScopeId && requestedScopeId !== expectedScopeId) {
      return jsonResponse(400, {
        ok: false,
        reason: "property_scope_mismatch",
        propertyScopeId: expectedScopeId,
      });
    }

    const requestedByRole = normalizeRole(body.requestedByRole ?? auth.role);
    if (!userHasPropertyAccess(auth.legacyUid, requestedByRole, propertyData)) {
      return jsonResponse(403, { ok: false, reason: "forbidden_property_access" });
    }

    const matrixGateway = await resolveMatrixGateway(
      normalizeId(body.matrixGatewayId),
      propertyId,
      expectedScopeId,
    );
    if (!matrixGateway) {
      return jsonResponse(400, { ok: false, reason: "no_matrix_for_property" });
    }
    const { gatewayId: matrixGatewayId, gatewayData: matrixData } = matrixGateway;
    if (
      matrixData.is_matrix !== true && matrixData.isMatrix !== true ||
      !entityMatchesProperty(matrixData, propertyId, expectedScopeId)
    ) {
      return jsonResponse(400, { ok: false, reason: "no_matrix_for_property" });
    }
    if (!isTargetReady(matrixData, expectedScopeId)) {
      return jsonResponse(409, {
        ok: false,
        reason: "matrix_not_ready",
        matrixGatewayId,
        expectedScopeId,
        matrixState: {
          propertyId: normalizeId(matrixData.property_id ?? matrixData.propertyId),
          propertyScopeId: normalizeScopeId(
            matrixData.property_scope_id ??
              matrixData.propertyScopeId ??
              (matrixData.runtime_status as JsonMap | undefined)?.property_scope_id ??
              (matrixData.runtime_status as JsonMap | undefined)?.propertyScopeId,
          ),
          bindingReady: matrixData.binding_ready === true ||
            matrixData.bindingReady === true ||
            (matrixData.runtime_status as JsonMap | undefined)?.binding_ready === true ||
            (matrixData.runtime_status as JsonMap | undefined)?.bindingReady === true,
          supportsScopedLora: matrixData.supports_scoped_lora === true ||
            matrixData.supportsScopedLora === true ||
            (matrixData.runtime_status as JsonMap | undefined)?.supports_scoped_lora === true ||
            (matrixData.runtime_status as JsonMap | undefined)?.supportsScopedLora === true,
        },
      });
    }

    const matrixRuntimeId = matrixRuntimeIdFromGatewayData(matrixGatewayId, matrixData);
    const { data: queueKeyRow, error: queueKeyError } = await admin
      .from("matrix_queue_keys")
      .select("queue_key")
      .eq("runtime_id", matrixRuntimeId)
      .maybeSingle();
    if (queueKeyError) throw new Error(queueKeyError.message);
    const queueKey = extractQueueKey(queueKeyRow?.queue_key);
    if (!queueKey) {
      return jsonResponse(409, { ok: false, reason: "missing_matrix_queue_key" });
    }

    const targetDeviceIds = normalizeDeviceIdList(body.targetDeviceIds);
    const targetGatewayIds = normalizeIdList(body.targetGatewayIds);
    if (!targetDeviceIds.length && !targetGatewayIds.length) {
      return jsonResponse(400, { ok: false, reason: "no_targets" });
    }

    const targetValidation = await validateTargets(
      propertyId,
      expectedScopeId,
      targetDeviceIds,
      targetGatewayIds,
    );
    if (!targetValidation.ok) {
      return jsonResponse(409, {
        ok: false,
        reason: targetValidation.resultReason,
        deviceResults: targetValidation.deviceResults,
      });
    }

    const nowMs = Date.now();
    const commandId = normalizeText(body.commandId) || crypto.randomUUID();
    const ttlMs = Number(body.ttlMs);
    const expiresAtMs = Number.isFinite(ttlMs) && ttlMs > 0
      ? nowMs + ttlMs
      : commandExpiryMs(normalizedCommand, nowMs);
    if (expiresAtMs <= nowMs) {
      return jsonResponse(400, { ok: false, reason: "command_expired" });
    }

    const businessRef = normalizeBusinessRef(body.businessRef);
    const sourcePayload = body.payload && typeof body.payload === "object"
      ? body.payload as JsonMap
      : {};
    const dispatchPayload = buildDispatchPayload(
      commandId,
      normalizedCommand,
      sourcePayload,
      businessRef,
    );

    await upsertCommandRecords({
      propertyId,
      propertyScopeId: expectedScopeId,
      matrixGatewayId,
      matrixRuntimeId,
      queueKey,
      commandId,
      command: normalizedCommand,
      targetDeviceIds,
      targetGatewayIds,
      requestedByUid: auth.legacyUid,
      requestedByRole,
      deviceResults: targetValidation.deviceResults,
      payload: dispatchPayload.payload,
      polygonKind: dispatchPayload.polygonKind,
      originDocType: dispatchPayload.originDocType,
      originDocId: dispatchPayload.originDocId,
      businessRef,
      createdAtMs: nowMs,
      expiresAtMs,
    });

    return jsonResponse(200, {
      ok: true,
      commandId,
      propertyId,
      propertyScopeId: expectedScopeId,
      matrixGatewayId,
      matrixRuntimeId,
      expiresAtMs,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown_error";
    const status = message === "missing_auth_token" || message === "invalid_auth_token"
      ? 401
      : 500;
    return jsonResponse(status, { ok: false, reason: message });
  }
});
