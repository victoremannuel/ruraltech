import {
  computePropertyScopeId,
  corsHeaders,
  createAdminClient,
  getAuthContext,
  jsonResponse,
  matrixRuntimeIdFromGatewayData,
  normalizeId,
  normalizeIdList,
  normalizeRole,
  normalizeScopeId,
  type JsonMap,
} from "../_shared/supabase.ts";

function collectPropertyUserIds(propertyData: JsonMap): string[] {
  const userIds = new Set<string>();
  const createdByUid = normalizeId(
    propertyData.created_by_uid ?? propertyData.createdByUid,
  );
  const ownerUid = normalizeId(propertyData.owner_uid ?? propertyData.ownerUid);
  if (createdByUid) userIds.add(createdByUid);
  if (ownerUid) userIds.add(ownerUid);
  for (const uid of normalizeIdList(propertyData.user_uids ?? propertyData.userUids)) {
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
    const admin = createAdminClient();
    const auth = await getAuthContext(request, admin);
    if (!["adm", "admin"].includes(normalizeRole(auth.role))) {
      return jsonResponse(403, { ok: false, reason: "admin_required" });
    }

    const body = await request.json().catch(() => ({})) as JsonMap;
    const apply = body.apply === true;
    const propertyFilter = normalizeId(body.propertyId);
    const gatewayFilter = normalizeId(body.gatewayId);

    const propertiesQuery = admin.from("rural_properties").select("*");
    const gatewaysQuery = admin.from("gateways").select("*");
    const collarsQuery = admin.from("collars").select("*");

    const propertyResult = propertyFilter
      ? await propertiesQuery.eq("id", propertyFilter)
      : await propertiesQuery;
    const gatewayResult = gatewayFilter
      ? await gatewaysQuery.eq("id", gatewayFilter)
      : await gatewaysQuery;
    const collarResult = await collarsQuery;
    if (propertyResult.error) throw new Error(propertyResult.error.message);
    if (gatewayResult.error) throw new Error(gatewayResult.error.message);
    if (collarResult.error) throw new Error(collarResult.error.message);

    const propertyDocs = (propertyResult.data ?? []) as JsonMap[];
    const gatewayDocs = (gatewayResult.data ?? []) as JsonMap[];
    const collarDocs = (collarResult.data ?? []) as JsonMap[];

    const propertyResults: JsonMap[] = [];
    const gatewayResults: JsonMap[] = [];
    const collarResults: JsonMap[] = [];
    const scopeToPropertyId = new Map<string, string>();

    for (const property of propertyDocs) {
      const propertyId = normalizeId(property.id);
      if (!propertyId) continue;
      const expectedScopeId = await computePropertyScopeId(propertyId);
      const currentScopeId = normalizeScopeId(
        property.property_scope_id ?? property.propertyScopeId,
      );
      const userIds = collectPropertyUserIds(property);
      if (apply) {
        const update = await admin.from("rural_properties").update({
          property_scope_id: expectedScopeId,
          user_uids: userIds,
        }).eq("id", propertyId);
        if (update.error) throw new Error(update.error.message);
      }
      if (expectedScopeId) scopeToPropertyId.set(expectedScopeId, propertyId);
      propertyResults.push({
        propertyId,
        expectedScopeId,
        currentScopeId,
        mirroredUsers: userIds,
      });
    }

    for (const gateway of gatewayDocs) {
      const gatewayId = normalizeId(gateway.id);
      if (!gatewayId) continue;
      if (gateway.is_matrix !== true && gateway.isMatrix !== true) continue;
      const propertyId = normalizeId(gateway.property_id ?? gateway.propertyId);
      if (!propertyId) continue;
      const expectedScopeId = await computePropertyScopeId(propertyId);
      const runtimeId = matrixRuntimeIdFromGatewayData(gatewayId, gateway);
      const runtimeStatus = gateway.runtime_status && typeof gateway.runtime_status === "object"
        ? gateway.runtime_status as JsonMap
        : gateway.runtimeStatus && typeof gateway.runtimeStatus === "object"
        ? gateway.runtimeStatus as JsonMap
        : {};
      const supportsScopedLora = gateway.supports_scoped_lora === true ||
        gateway.supportsScopedLora === true ||
        runtimeStatus.supports_scoped_lora === true ||
        runtimeStatus.supportsScopedLora === true;
      const bindingReady = gateway.binding_ready === true ||
        gateway.bindingReady === true ||
        runtimeStatus.binding_ready === true ||
        runtimeStatus.bindingReady === true ||
        (supportsScopedLora &&
          normalizeScopeId(
            gateway.property_scope_id ?? gateway.propertyScopeId ??
              runtimeStatus.property_scope_id ?? runtimeStatus.propertyScopeId,
          ) === expectedScopeId);
      if (apply) {
        const gatewayUpdate = await admin.from("gateways").update({
          property_scope_id: expectedScopeId,
          binding_ready: bindingReady,
          supports_scoped_lora: supportsScopedLora,
        }).eq("id", gatewayId);
        if (gatewayUpdate.error) throw new Error(gatewayUpdate.error.message);
        const bindingUpsert = await admin.from("matrix_bindings").upsert({
          runtime_id: runtimeId,
          property_id: propertyId,
          property_scope_id: expectedScopeId,
          matrix_gateway_id: gatewayId,
          enabled: Boolean(propertyId && expectedScopeId && bindingReady && supportsScopedLora),
          updated_at_ms: Date.now(),
          raw: {
            propertyId,
            propertyScopeId: expectedScopeId,
            matrixGatewayId: gatewayId,
            matrixRuntimeId: runtimeId,
            enabled: Boolean(propertyId && expectedScopeId && bindingReady && supportsScopedLora),
            updatedAtMs: Date.now(),
          },
        });
        if (bindingUpsert.error) throw new Error(bindingUpsert.error.message);
      }
      gatewayResults.push({
        gatewayId,
        matrixRuntimeId: runtimeId,
        propertyId,
        propertyScopeId: expectedScopeId,
        enabled: Boolean(propertyId && expectedScopeId && bindingReady && supportsScopedLora),
      });
    }

    for (const collar of collarDocs) {
      const collarId = normalizeId(collar.id);
      if (!collarId) continue;
      const propertyId = normalizeId(collar.property_id ?? collar.propertyId);
      if (!propertyId) continue;
      const expectedScopeId = await computePropertyScopeId(propertyId);
      const runtimeStatus = collar.runtime_status && typeof collar.runtime_status === "object"
        ? collar.runtime_status as JsonMap
        : collar.runtimeStatus && typeof collar.runtimeStatus === "object"
        ? collar.runtimeStatus as JsonMap
        : {};
      const supportsScopedLora = collar.supports_scoped_lora === true ||
        collar.supportsScopedLora === true ||
        runtimeStatus.supports_scoped_lora === true ||
        runtimeStatus.supportsScopedLora === true;
      const bindingReady = collar.binding_ready === true ||
        collar.bindingReady === true ||
        runtimeStatus.binding_ready === true ||
        runtimeStatus.bindingReady === true ||
        (supportsScopedLora &&
          normalizeScopeId(
            collar.property_scope_id ?? collar.propertyScopeId ??
              runtimeStatus.property_scope_id ?? runtimeStatus.propertyScopeId,
          ) === expectedScopeId);
      if (apply) {
        const collarUpdate = await admin.from("collars").update({
          property_scope_id: expectedScopeId,
          binding_ready: bindingReady,
          supports_scoped_lora: supportsScopedLora,
        }).eq("id", collarId);
        if (collarUpdate.error) throw new Error(collarUpdate.error.message);
      }
      collarResults.push({
        collarId,
        propertyId,
        propertyScopeId: expectedScopeId,
        bindingReady,
        supportsScopedLora,
      });
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
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown_error";
    return jsonResponse(message === "admin_required" ? 403 : 500, {
      ok: false,
      reason: message,
    });
  }
});
