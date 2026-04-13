import {
  computePropertyScopeId,
  corsHeaders,
  getFirestoreDocument,
  jsonResponse,
  listFirestoreCollectionDocuments,
  matrixRuntimeIdFromGatewayData,
  normalizeId,
  normalizeIdList,
  normalizeScopeId,
  normalizeText,
  patchFirestoreDocument,
  patchRtdbRoot,
  resolveEntityScopeId,
  sanitizeRtdbKey,
  verifyFirebaseBearerToken,
} from "../_shared/firebase.ts";

type JsonMap = Record<string, unknown>;

function collectPropertyUserIds(propertyData: JsonMap): string[] {
  const userIds = new Set<string>();
  const createdByUid = normalizeId(propertyData.createdByUid);
  const ownerUid = normalizeId(propertyData.ownerUid);
  if (createdByUid) userIds.add(createdByUid);
  if (ownerUid) userIds.add(ownerUid);
  for (const uid of normalizeIdList(propertyData.userUids)) {
    userIds.add(uid);
  }
  return [...userIds].sort();
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
    const user = await getFirestoreDocument(`users/${uid}`);
    const userRole = normalizeText(user?.role).toLowerCase();
    if (userRole != "adm" && userRole != "admin") {
      return jsonResponse(403, { ok: false, reason: "admin_required" });
    }

    const body = await request.json().catch(() => ({})) as JsonMap;
    const apply = body.apply === true;
    const propertyFilter = normalizeId(body.propertyId);
    const gatewayFilter = normalizeId(body.gatewayId);

    const propertyDocs = propertyFilter
      ? [await getFirestoreDocument(`ruralProperties/${propertyFilter}`)].filter(Boolean) as JsonMap[]
      : await listFirestoreCollectionDocuments("ruralProperties");
    const gatewayDocs = gatewayFilter
      ? [await getFirestoreDocument(`gateways/${gatewayFilter}`)].filter(Boolean) as JsonMap[]
      : await listFirestoreCollectionDocuments("gateways");
    const collarDocs = await listFirestoreCollectionDocuments("collars");

    const rtdbPatch: Record<string, boolean | JsonMap> = {};
    const propertyResults: JsonMap[] = [];
    const gatewayResults: JsonMap[] = [];
    const collarResults: JsonMap[] = [];
    const scopeToPropertyId = new Map<string, string>();

    for (const property of propertyDocs) {
      const propertyId = normalizeId(property.id);
      if (!propertyId) continue;
      const expectedScopeId = await computePropertyScopeId(propertyId);
      const currentScopeId = normalizeScopeId(property.propertyScopeId);
      const userIds = collectPropertyUserIds(property);
      const propertyAccess: Record<string, boolean> = {};
      for (const userId of userIds) {
        propertyAccess[sanitizeRtdbKey(userId)] = true;
      }

      if (apply && expectedScopeId && currentScopeId != expectedScopeId) {
        await patchFirestoreDocument(`ruralProperties/${propertyId}`, {
          propertyScopeId: expectedScopeId,
        });
      }

      rtdbPatch[`propertyAccess/${sanitizeRtdbKey(propertyId)}`] = propertyAccess;
      if (expectedScopeId) {
        scopeToPropertyId.set(expectedScopeId, propertyId);
      }
      propertyResults.push({
        propertyId,
        expectedScopeId,
        currentScopeId,
        mirroredUsers: userIds,
      });
    }

    for (const gateway of gatewayDocs) {
      const gatewayId = normalizeId(gateway.id);
      if (!gatewayId || gateway.is_matrix !== true) continue;
      const runtimeScopeId = resolveEntityScopeId(gateway);
      const propertyId = normalizeId(gateway.propertyId) ||
        normalizeId((gateway.runtimeStatus as JsonMap | undefined)?.propertyId) ||
        scopeToPropertyId.get(runtimeScopeId) ||
        "";
      if (!propertyId) continue;
      const expectedScopeId = await computePropertyScopeId(propertyId);
      const runtimeId = matrixRuntimeIdFromGatewayData(gatewayId, gateway);
      const runtimeStatus = gateway.runtimeStatus &&
          typeof gateway.runtimeStatus === "object"
        ? gateway.runtimeStatus as JsonMap
        : {};
      const supportsScopedLora = gateway.supportsScopedLora === true ||
        runtimeStatus.supportsScopedLora === true;
      const bindingReady = gateway.bindingReady === true ||
        runtimeStatus.bindingReady === true ||
        (supportsScopedLora && runtimeScopeId === expectedScopeId);
      if (apply) {
        await patchFirestoreDocument(`gateways/${gatewayId}`, {
          propertyId,
          propertyScopeId: expectedScopeId,
          bindingReady,
          supportsScopedLora,
        });
      }
      const matrixBinding = {
        propertyId,
        propertyScopeId: expectedScopeId,
        matrixGatewayId: gatewayId,
        matrixRuntimeId: runtimeId,
        enabled: Boolean(propertyId && expectedScopeId && bindingReady && supportsScopedLora),
        updatedAtMs: Date.now(),
      };

      rtdbPatch[`matrixBindings/${runtimeId}`] = matrixBinding;
      rtdbPatch[`matrixBindings/${sanitizeRtdbKey(gatewayId)}`] = matrixBinding;
      gatewayResults.push({
        gatewayId,
        matrixRuntimeId: runtimeId,
        propertyId,
        propertyScopeId: expectedScopeId,
        enabled: matrixBinding.enabled,
      });
    }

    for (const collar of collarDocs) {
      const collarId = normalizeId(collar.id);
      if (!collarId) continue;
      const runtimeScopeId = resolveEntityScopeId(collar);
      const propertyId = normalizeId(collar.propertyId) ||
        normalizeId((collar.runtimeStatus as JsonMap | undefined)?.propertyId) ||
        scopeToPropertyId.get(runtimeScopeId) ||
        "";
      if (!propertyId) continue;
      const expectedScopeId = await computePropertyScopeId(propertyId);
      const runtimeStatus = collar.runtimeStatus &&
          typeof collar.runtimeStatus === "object"
        ? collar.runtimeStatus as JsonMap
        : {};
      const supportsScopedLora = collar.supportsScopedLora === true ||
        runtimeStatus.supportsScopedLora === true;
      const bindingReady = collar.bindingReady === true ||
        runtimeStatus.bindingReady === true ||
        (supportsScopedLora && runtimeScopeId === expectedScopeId);
      if (apply) {
        await patchFirestoreDocument(`collars/${collarId}`, {
          propertyId,
          propertyScopeId: expectedScopeId,
          bindingReady,
          supportsScopedLora,
        });
      }
      collarResults.push({
        collarId,
        propertyId,
        propertyScopeId: expectedScopeId,
        bindingReady,
        supportsScopedLora,
      });
    }

    if (apply && Object.keys(rtdbPatch).length) {
      await patchRtdbRoot(rtdbPatch);
    }

    return jsonResponse(200, {
      ok: true,
      apply,
      propertyCount: propertyResults.length,
      gatewayCount: gatewayResults.length,
      collarCount: collarResults.length,
      properties: propertyResults,
      gateways: gatewayResults,
      collars: collarResults,
      rtdbPatchCount: Object.keys(rtdbPatch).length,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown_error";
    const status = message === "admin_required" ? 403 : 500;
    return jsonResponse(status, { ok: false, reason: message });
  }
});
