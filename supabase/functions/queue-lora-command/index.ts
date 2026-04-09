import {
  ALLOWED_COMMANDS,
  commandExpiryMs,
  computePropertyScopeId,
  corsHeaders,
  entityMatchesProperty,
  extractQueueKey,
  getFirestoreDocument,
  getRtdbValue,
  isTargetReady,
  jsonResponse,
  listFirestoreCollectionDocuments,
  matrixRuntimeIdFromGatewayData,
  normalizeBusinessRef,
  normalizeDeviceIdList,
  normalizeId,
  normalizeIdList,
  normalizeRole,
  normalizeScopeId,
  normalizeText,
  patchRtdbRoot,
  userHasPropertyAccess,
  verifyFirebaseBearerToken,
} from "../_shared/firebase.ts";

type JsonMap = Record<string, unknown>;

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
    originDocType === "ruralProperty" || businessRef?.type === "ruralProperty"
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
): { payload: JsonMap; polygonKind: string; originDocType: string; originDocId: string } {
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
): Promise<{ gatewayId: string; gatewayData: JsonMap } | null> {
  if (explicitMatrixGatewayId) {
    const matrixData = await getFirestoreDocument(`gateways/${explicitMatrixGatewayId}`);
    if (!matrixData) return null;
    return { gatewayId: explicitMatrixGatewayId, gatewayData: matrixData };
  }

  const gateways = await listFirestoreCollectionDocuments("gateways");
  for (const gateway of gateways) {
    if (gateway.is_matrix !== true) continue;
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
  const deviceResults: JsonMap = {};

  for (const deviceId of targetDeviceIds) {
    const collar = await getFirestoreDocument(`collars/${deviceId}`);
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
    const gateway = await getFirestoreDocument(`gateways/${gatewayId}`);
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

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders() });
  }
  if (request.method !== "POST") {
    return jsonResponse(405, { ok: false, reason: "method_not_allowed" });
  }

  try {
    const { uid } = await verifyFirebaseBearerToken(
      request.headers.get("authorization"),
    );
    const body = await request.json() as JsonMap;
    const normalizedCommand = normalizeText(body.command).toUpperCase();
    if (!ALLOWED_COMMANDS.has(normalizedCommand)) {
      return jsonResponse(400, { ok: false, reason: "unsupported_command" });
    }

    const propertyId = normalizeId(body.propertyId);
    if (!propertyId) {
      return jsonResponse(400, { ok: false, reason: "invalid_property_id" });
    }

    const propertyData = await getFirestoreDocument(`ruralProperties/${propertyId}`);
    if (!propertyData) {
      return jsonResponse(404, { ok: false, reason: "property_not_found" });
    }
    const expectedScopeId = normalizeScopeId(propertyData.propertyScopeId) ||
      await computePropertyScopeId(propertyId);
    const requestedScopeId = normalizeScopeId(body.propertyScopeId);
    if (requestedScopeId && requestedScopeId !== expectedScopeId) {
      return jsonResponse(400, {
        ok: false,
        reason: "property_scope_mismatch",
        propertyScopeId: expectedScopeId,
      });
    }

    const userData = await getFirestoreDocument(`users/${uid}`);
    const requestedByRole = normalizeRole(
      userData?.role ?? body.requestedByRole ?? "user",
    );
    if (!userHasPropertyAccess(uid, requestedByRole, propertyData)) {
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
      matrixData.is_matrix !== true ||
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
          propertyId: normalizeId(matrixData.propertyId),
          propertyScopeId: normalizeScopeId(
            matrixData.propertyScopeId ??
              (matrixData.runtimeStatus as JsonMap | undefined)?.propertyScopeId,
          ),
          bindingReady: matrixData.bindingReady === true ||
            ((matrixData.runtimeStatus as JsonMap | undefined)?.bindingReady === true),
          supportsScopedLora: matrixData.supportsScopedLora === true ||
            ((matrixData.runtimeStatus as JsonMap | undefined)?.supportsScopedLora === true),
        },
      });
    }

    const matrixRuntimeId = matrixRuntimeIdFromGatewayData(matrixGatewayId, matrixData);
    const queueKey = extractQueueKey(await getRtdbValue(`matrixQueueKeys/${matrixRuntimeId}`));
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

    const propertyKey = normalizeText(propertyId).replace(/[.#$\[\]/]/g, "_");
    const queuedEventId = eventIdFor(commandId, "queued");
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

    const commandSummary = {
      commandId,
      command: normalizedCommand,
      propertyId,
      propertyScopeId: expectedScopeId,
      matrixGatewayId,
      matrixRuntimeId,
      targetDeviceIds,
      targetGatewayIds,
      requestedByUid: uid,
      requestedByRole,
      status: "queued",
      resultReason: null,
      deviceResults: targetValidation.deviceResults,
      createdAtMs: nowMs,
      updatedAtMs: nowMs,
      expiresAtMs,
      completedAtMs: null,
      polygonKind: dispatchPayload.polygonKind || null,
      originDocType: dispatchPayload.originDocType || null,
      originDocId: dispatchPayload.originDocId || null,
      ...(businessRef ? { businessRef } : {}),
    };

    const queuedEvent = {
      type: "queued",
      status: "queued",
      reason: null,
      matrixId: matrixRuntimeId,
      createdAtMs: nowMs,
    };

    const queuePayload = {
      commandId,
      command: normalizedCommand,
      propertyId,
      propertyScopeId: expectedScopeId,
      matrixGatewayId,
      matrixRuntimeId,
      targetDeviceIds,
      targetGatewayIds,
      payload: dispatchPayload.payload,
      requestedByUid: uid,
      requestedByRole,
      createdAtMs: nowMs,
      expiresAtMs,
      ...(businessRef ? { businessRef } : {}),
    };

    await patchRtdbRoot({
      [`propertyCommands/${propertyKey}/${commandId}`]: commandSummary,
      [`propertyCommandEvents/${propertyKey}/${commandId}/${queuedEventId}`]: queuedEvent,
      [`matrixCommandQueues/${matrixRuntimeId}/${queueKey}/${commandId}`]: queuePayload,
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
    const status = message.startsWith("missing_bearer_token") ||
        message.startsWith("invalid_firebase_token")
      ? 401
      : 500;
    return jsonResponse(status, { ok: false, reason: message });
  }
});
