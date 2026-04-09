const crypto = require("node:crypto");

function normalizeId(value) {
  if (value == null) return "";
  if (typeof value === "string") {
    const raw = value.trim();
    if (!raw) return "";
    if (!raw.includes("/")) return raw;
    const parts = raw.split("/").filter(Boolean);
    return parts.length ? parts[parts.length - 1] : raw;
  }
  if (typeof value === "object") {
    if (typeof value.id === "string" && value.id.trim()) {
      return value.id.trim();
    }
    if (typeof value.path === "string" && value.path.trim()) {
      return normalizeId(value.path);
    }
  }
  return "";
}

function normalizeText(value) {
  if (value == null) return "";
  return String(value).trim();
}

function normalizeRole(value) {
  const raw = normalizeText(value).toLowerCase();
  return raw || "user";
}

function normalizeIdList(raw) {
  if (!Array.isArray(raw)) return [];
  return [...new Set(raw.map(normalizeId).filter(Boolean))].sort();
}

function normalizeDeviceIdList(raw) {
  return normalizeIdList(raw).filter((deviceId) => /^[1-9][0-9]*$/.test(deviceId));
}

function pointList(raw) {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((entry) => {
      if (Array.isArray(entry) && entry.length >= 2) {
        const lat = Number(entry[0]);
        const lon = Number(entry[1]);
        if (Number.isFinite(lat) && Number.isFinite(lon)) {
          return { lat, lon };
        }
        return null;
      }
      if (entry && typeof entry === "object") {
        const lat = Number(entry.lat);
        const lon = Number(entry.lon ?? entry.lng);
        if (Number.isFinite(lat) && Number.isFinite(lon)) {
          return { lat, lon };
        }
      }
      return null;
    })
    .filter(Boolean);
}

function latLonPairs(raw) {
  return pointList(raw).map(({ lat, lon }) => [lat, lon]);
}

function canonicalizeCoordinate(value) {
  return Number(Number(value).toFixed(7));
}

function polygonSignature(raw) {
  return JSON.stringify(
    pointList(raw).map(({ lat, lon }) => [
      canonicalizeCoordinate(lat),
      canonicalizeCoordinate(lon),
    ]),
  );
}

function linkedDeviceSignature(raw) {
  return JSON.stringify(normalizeDeviceIdList(raw));
}

function propertyPolygonChanged(beforeData, afterData) {
  return polygonSignature(beforeData?.points) !== polygonSignature(afterData?.points);
}

function areaFenceInputsChanged(beforeData, afterData) {
  return (
    polygonSignature(beforeData?.perimeter) !== polygonSignature(afterData?.perimeter) ||
    linkedDeviceSignature(beforeData?.linkedDeviceIds) !==
      linkedDeviceSignature(afterData?.linkedDeviceIds)
  );
}

function sanitizeDocToken(value) {
  return normalizeText(value).replace(/[^A-Za-z0-9_-]/g, "-").replace(/-+/g, "-");
}

function buildDeterministicCommandId({
  origin,
  originDocType,
  originDocId,
  propertyId,
  propertyScopeId,
  targetDeviceIds,
  points,
}) {
  const hash = crypto
    .createHash("sha256")
    .update(
      JSON.stringify({
        origin: normalizeText(origin),
        originDocType: normalizeText(originDocType),
        originDocId: normalizeId(originDocId),
        propertyId: normalizeId(propertyId),
        propertyScopeId: normalizeText(propertyScopeId).toUpperCase(),
        targetDeviceIds: normalizeDeviceIdList(targetDeviceIds),
        points: latLonPairs(points),
      }),
    )
    .digest("hex")
    .slice(0, 24);
  return `auto-${sanitizeDocToken(originDocType)}-${sanitizeDocToken(originDocId)}-${hash}`;
}

function resolveUpdatedByUid(data) {
  return (
    normalizeId(data?.updatedByUid) ||
    normalizeId(data?.requestedByUid) ||
    normalizeId(data?.createdByUid) ||
    normalizeId(data?.ownerUid)
  );
}

function buildAutoFenceCommand({
  origin,
  originDocType,
  originDocId,
  propertyId,
  propertyScopeId,
  matrixGatewayId,
  targetDeviceIds,
  requestedByUid,
  requestedByRole,
  points,
  nowMs = Date.now(),
  ttlMs = 15 * 60 * 1000,
}) {
  const normalizedPropertyId = normalizeId(propertyId);
  const normalizedScopeId = normalizeText(propertyScopeId).toUpperCase();
  const normalizedMatrixGatewayId = normalizeId(matrixGatewayId);
  const normalizedTargetDeviceIds = normalizeDeviceIdList(targetDeviceIds);
  const normalizedPoints = latLonPairs(points);
  if (!normalizedPropertyId || !normalizedScopeId || !normalizedMatrixGatewayId) {
    return null;
  }
  if (!normalizedTargetDeviceIds.length || normalizedPoints.length < 3) {
    return null;
  }
  const commandId = buildDeterministicCommandId({
    origin,
    originDocType,
    originDocId,
    propertyId: normalizedPropertyId,
    propertyScopeId: normalizedScopeId,
    targetDeviceIds: normalizedTargetDeviceIds,
    points: normalizedPoints,
  });
  return {
    commandId,
    command: "SET_FENCE",
    propertyId: normalizedPropertyId,
    propertyScopeId: normalizedScopeId,
    matrixGatewayId: normalizedMatrixGatewayId,
    targetDeviceIds: normalizedTargetDeviceIds,
    targetGatewayIds: [],
    payload: {
      cmd_id: commandId,
      command_id: commandId,
      polygon_kind: originDocType === "area" ? "area" : "property",
      origin_doc_type: normalizeText(originDocType),
      origin_doc_id: normalizeId(originDocId),
      points: normalizedPoints,
    },
    requestedByUid: normalizeId(requestedByUid),
    requestedByRole: normalizeRole(requestedByRole),
    origin: normalizeText(origin),
    originDocType: normalizeText(originDocType),
    originDocId: normalizeId(originDocId),
    createdAtMs: nowMs,
    expiresAtMs: nowMs + ttlMs,
  };
}

function buildAreaLinkSyncPlan({
  areaId,
  beforeLinkedDeviceIds,
  afterLinkedDeviceIds,
}) {
  const normalizedAreaId = normalizeId(areaId);
  const before = new Set(normalizeDeviceIdList(beforeLinkedDeviceIds));
  const after = new Set(normalizeDeviceIdList(afterLinkedDeviceIds));
  const assignIds = [...after].sort();
  const clearIds = [...before].filter((deviceId) => !after.has(deviceId)).sort();
  return {
    areaId: normalizedAreaId,
    assignIds,
    clearIds,
  };
}

function buildAreaLinkMutations({
  areaId,
  beforeLinkedDeviceIds,
  afterLinkedDeviceIds,
  activeAreaByDeviceId = {},
}) {
  const linkPlan = buildAreaLinkSyncPlan({
    areaId,
    beforeLinkedDeviceIds,
    afterLinkedDeviceIds,
  });
  const normalizedAreaId = normalizeId(linkPlan.areaId);
  return {
    areaId: normalizedAreaId,
    linkPlan,
    upserts: linkPlan.assignIds.map((deviceId) => ({
      deviceId,
      patch: { activeAreaId: normalizedAreaId },
    })),
    clears: linkPlan.clearIds
      .filter((deviceId) => normalizeId(activeAreaByDeviceId[deviceId]) === normalizedAreaId)
      .map((deviceId) => ({
        deviceId,
        clearActiveAreaId: true,
      })),
  };
}

async function runPropertyPolygonAutoSync({
  propertyId,
  beforeData,
  afterData,
  deps,
}) {
  const normalizedPropertyId = normalizeId(propertyId);
  if (!normalizedPropertyId || !afterData) {
    return { ok: false, reason: "missing_property" };
  }
  if (!propertyPolygonChanged(beforeData, afterData)) {
    return { ok: true, reason: "no_polygon_change", enqueued: false };
  }

  const propertyMeta = await deps.resolvePropertyMeta(normalizedPropertyId, afterData);
  if (!propertyMeta?.propertyScopeId || !propertyMeta?.matrixGatewayId) {
    return { ok: false, reason: "property_not_ready" };
  }

  const targetDeviceIds = normalizeDeviceIdList(
    await deps.listPropertyTargetDeviceIds(
      normalizedPropertyId,
      propertyMeta.propertyScopeId,
    ),
  );
  if (!targetDeviceIds.length) {
    return { ok: true, reason: "no_target_devices", enqueued: false };
  }

  const requestedByUid = resolveUpdatedByUid(afterData);
  const requester = await deps.resolveRequester(requestedByUid);
  const commandDoc = buildAutoFenceCommand({
    origin: "auto_property_polygon_sync",
    originDocType: "ruralProperty",
    originDocId: normalizedPropertyId,
    propertyId: normalizedPropertyId,
    propertyScopeId: propertyMeta.propertyScopeId,
    matrixGatewayId: propertyMeta.matrixGatewayId,
    targetDeviceIds,
    requestedByUid,
    requestedByRole: requester.role,
    points: afterData.points,
    nowMs: deps.nowMs ? deps.nowMs() : Date.now(),
  });
  if (!commandDoc) {
    return { ok: false, reason: "invalid_polygon" };
  }

  const created = await deps.enqueueAutoCommand(commandDoc.commandId, commandDoc);
  return {
    ok: true,
    reason: created ? "queued" : "duplicate",
    enqueued: created,
    commandId: commandDoc.commandId,
    targetDeviceIds,
  };
}

async function runAreaPolygonAutoSync({
  areaId,
  beforeData,
  afterData,
  deps,
}) {
  const normalizedAreaId = normalizeId(areaId);
  if (!normalizedAreaId || !afterData) {
    return { ok: false, reason: "missing_area" };
  }
  if (normalizeText(afterData.source).toLowerCase() === "herding_operation") {
    return { ok: true, reason: "ignored_herding_area", enqueued: false };
  }

  const linkPlan = buildAreaLinkSyncPlan({
    areaId: normalizedAreaId,
    beforeLinkedDeviceIds: beforeData?.linkedDeviceIds,
    afterLinkedDeviceIds: afterData?.linkedDeviceIds,
  });
  const linksChanged =
    linkedDeviceSignature(beforeData?.linkedDeviceIds) !==
    linkedDeviceSignature(afterData?.linkedDeviceIds);
  if (linksChanged || !beforeData) {
    await deps.syncAreaLinks(linkPlan);
  }

  if (!areaFenceInputsChanged(beforeData, afterData)) {
    return { ok: true, reason: "no_fence_change", enqueued: false, linkPlan };
  }

  if (!linkPlan.assignIds.length) {
    return { ok: true, reason: "no_linked_devices", enqueued: false, linkPlan };
  }

  const propertyId = normalizeId(afterData.ruralPropertiesID ?? afterData.propertyId);
  if (!propertyId) {
    return { ok: false, reason: "missing_property_id", linkPlan };
  }

  const propertyMeta = await deps.resolvePropertyMeta(propertyId, afterData);
  if (!propertyMeta?.propertyScopeId || !propertyMeta?.matrixGatewayId) {
    return { ok: false, reason: "property_not_ready", linkPlan };
  }

  const requestedByUid = resolveUpdatedByUid(afterData);
  const requester = await deps.resolveRequester(requestedByUid);
  const commandDoc = buildAutoFenceCommand({
    origin: "auto_area_polygon_sync",
    originDocType: "area",
    originDocId: normalizedAreaId,
    propertyId,
    propertyScopeId: propertyMeta.propertyScopeId,
    matrixGatewayId: propertyMeta.matrixGatewayId,
    targetDeviceIds: linkPlan.assignIds,
    requestedByUid,
    requestedByRole: requester.role,
    points: afterData.perimeter,
    nowMs: deps.nowMs ? deps.nowMs() : Date.now(),
  });
  if (!commandDoc) {
    return { ok: false, reason: "invalid_polygon", linkPlan };
  }

  const created = await deps.enqueueAutoCommand(commandDoc.commandId, commandDoc);
  return {
    ok: true,
    reason: created ? "queued" : "duplicate",
    enqueued: created,
    commandId: commandDoc.commandId,
    targetDeviceIds: linkPlan.assignIds,
    linkPlan,
  };
}

module.exports = {
  areaFenceInputsChanged,
  buildAreaLinkMutations,
  buildAreaLinkSyncPlan,
  buildAutoFenceCommand,
  buildDeterministicCommandId,
  latLonPairs,
  linkedDeviceSignature,
  normalizeDeviceIdList,
  normalizeId,
  normalizeRole,
  normalizeText,
  pointList,
  polygonSignature,
  propertyPolygonChanged,
  resolveUpdatedByUid,
  runAreaPolygonAutoSync,
  runPropertyPolygonAutoSync,
};
