const crypto = require("node:crypto");
const autoFenceSync = require("./auto_fence_sync");

const admin = require("firebase-admin");
const {
  onDocumentCreated,
  onDocumentWritten,
} = require("firebase-functions/v2/firestore");
const { onValueWritten } = require("firebase-functions/v2/database");
const { logger } = require("firebase-functions");

admin.initializeApp();

const firestore = admin.firestore();
const rtdb = admin.database();
const messaging = admin.messaging();

const ALLOWED_COMMANDS = new Set([
  "SET_FENCE",
  "SET_HERDING_PLAN",
  "SET_PARAMS",
  "PING",
]);

const COMMAND_TTL_MS = {
  SET_FENCE: 15 * 60 * 1000,
  SET_HERDING_PLAN: 20 * 60 * 1000,
  SET_PARAMS: 10 * 60 * 1000,
  PING: 6 * 60 * 1000,
};

const TERMINAL_COMMAND_STATUSES = new Set([
  "completed",
  "failed",
  "expired",
  "rejected",
  "nacked",
]);

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

function normalizeStringList(raw) {
  if (!Array.isArray(raw)) return [];
  return [...new Set(raw.map((entry) => normalizeText(entry)).filter(Boolean))].sort();
}

function sanitizeRtdbKey(value) {
  return normalizeText(value).replace(/[.#$\[\]/]/g, "_");
}

function normalizeScopeId(value) {
  return normalizeText(value).replace(/[^0-9a-fA-F]/g, "").toUpperCase();
}

function computePropertyScopeId(propertyId) {
  const normalized = normalizeId(propertyId).trim().toLowerCase();
  if (!normalized) return "";
  return crypto.createHash("sha256").update(normalized).digest("hex").slice(0, 16).toUpperCase();
}

function timestampFromMs(value) {
  const ms = Number(value);
  if (!Number.isFinite(ms) || ms <= 0) return null;
  return admin.firestore.Timestamp.fromMillis(ms);
}

function millisFromTimestamp(value) {
  if (value == null) return 0;
  if (value instanceof admin.firestore.Timestamp) {
    return value.toMillis();
  }
  if (value && typeof value.toMillis === "function") {
    return value.toMillis();
  }
  const raw = Number(value);
  if (!Number.isFinite(raw) || raw <= 0) return 0;
  return raw > 1000000000000 ? Math.trunc(raw) : Math.trunc(raw * 1000);
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

function collectUserIdsFromProperty(data) {
  const userIds = new Set();
  const createdByUid = normalizeId(data?.createdByUid);
  if (createdByUid) userIds.add(createdByUid);
  const ownerUid = normalizeId(data?.ownerUid);
  if (ownerUid) userIds.add(ownerUid);
  for (const uid of normalizeIdList(data?.userUids)) {
    userIds.add(uid);
  }
  return [...userIds].sort();
}

function normalizeBusinessRef(raw) {
  if (!raw || typeof raw !== "object") return null;
  const type = normalizeText(raw.type);
  const id = normalizeId(raw.id ?? raw.refId ?? raw.operationId);
  if (!type || !id) return null;
  return { type, id };
}

function extractQueueKey(raw) {
  if (typeof raw === "string") return sanitizeRtdbKey(raw);
  if (raw && typeof raw === "object") {
    return sanitizeRtdbKey(raw.queueKey);
  }
  return "";
}

function derivePolygonKind(command, originDocType, businessRef) {
  if (command === "SET_HERDING_PLAN") return "herding";
  if (command !== "SET_FENCE") return "";

  const normalizedOriginDocType = normalizeText(originDocType);
  const normalizedBusinessType = normalizeText(businessRef?.type);
  if (normalizedOriginDocType === "area" || normalizedBusinessType === "area") {
    return "area";
  }
  if (
    normalizedOriginDocType === "ruralProperty" ||
    normalizedBusinessType === "ruralProperty"
  ) {
    return "property";
  }
  return "";
}

function buildDispatchPayload(commandId, command, commandData) {
  const sourcePayload =
    commandData?.payload && typeof commandData.payload === "object"
      ? commandData.payload
      : {};
  const payload = {
    ...sourcePayload,
    cmd_id: normalizeText(sourcePayload.cmd_id || sourcePayload.command_id) || commandId,
    command_id:
      normalizeText(sourcePayload.command_id || sourcePayload.cmd_id) || commandId,
  };
  const businessRef = normalizeBusinessRef(commandData?.businessRef);
  const originDocType =
    normalizeText(
      commandData?.originDocType ||
        sourcePayload.origin_doc_type ||
        sourcePayload.originDocType ||
        businessRef?.type,
    ) || "";
  const originDocId =
    normalizeId(
      commandData?.originDocId ||
        sourcePayload.origin_doc_id ||
        sourcePayload.originDocId ||
        businessRef?.id ||
        sourcePayload.operation_id,
    ) || "";
  const polygonKind =
    normalizeText(
      sourcePayload.polygon_kind ||
        sourcePayload.polygonKind ||
        derivePolygonKind(command, originDocType, businessRef),
    ) || "";

  if (polygonKind) payload.polygon_kind = polygonKind;
  if (originDocType) payload.origin_doc_type = originDocType;
  if (originDocId) payload.origin_doc_id = originDocId;

  return {
    payload,
    polygonKind,
    originDocType,
    originDocId,
    businessRef,
  };
}

function commandExpiryMs(command, createdAtMs) {
  const ttl = COMMAND_TTL_MS[command] || 10 * 60 * 1000;
  return createdAtMs + ttl;
}

async function collectPushTokens(userIds) {
  const normalized = [...new Set((userIds || []).map(normalizeId).filter(Boolean))];
  if (!normalized.length) return [];
  const snapshots = await Promise.all(
    normalized.map((uid) => firestore.collection("users").doc(uid).get()),
  );
  const tokens = new Set();
  for (const snap of snapshots) {
    if (!snap.exists) continue;
    const rawTokens = snap.get("fcmTokens");
    if (!Array.isArray(rawTokens)) continue;
    for (const token of rawTokens) {
      const normalizedToken = typeof token === "string" ? token.trim() : "";
      if (normalizedToken) tokens.add(normalizedToken);
    }
  }
  return [...tokens];
}

async function sendPush({ userIds, title, body, data = {} }) {
  const tokens = await collectPushTokens(userIds);
  if (!tokens.length) return;

  await messaging.sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: Object.fromEntries(
      Object.entries(data).map(([key, value]) => [key, String(value ?? "")]),
    ),
  });
}

async function appendCommandEvent(commandId, type, extra = {}) {
  const payload = {
    type,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    ...extra,
  };
  await firestore.collection("loraCommands").doc(commandId).collection("events").add(payload);
}

async function syncPropertyAccessMirror(propertyId, propertyData) {
  const path = `propertyAccess/${sanitizeRtdbKey(propertyId)}`;
  if (!propertyData) {
    await rtdb.ref(path).remove();
    return;
  }

  const access = {};
  for (const uid of collectUserIdsFromProperty(propertyData)) {
    access[sanitizeRtdbKey(uid)] = true;
  }
  await rtdb.ref(path).set(access);
}

function matrixRuntimeIdFromGatewayData(gatewayId, data) {
  const runtimeStatus = data?.runtimeStatus && typeof data.runtimeStatus === "object"
    ? data.runtimeStatus
    : {};
  const runtimeId = normalizeId(
    data?.rtdbMatrixId ||
      data?.matrixId ||
      runtimeStatus.matrixId ||
      runtimeStatus.rtdbMatrixId ||
      gatewayId,
  );
  return sanitizeRtdbKey(runtimeId);
}

async function resolvePropertyScopeMeta(propertyId) {
  const normalizedPropertyId = normalizeId(propertyId);
  if (!normalizedPropertyId) {
    return {
      propertyId: "",
      propertyScopeId: "",
      propertySnap: null,
      propertyData: null,
    };
  }

  const propertySnap = await firestore.collection("ruralProperties").doc(normalizedPropertyId).get();
  if (!propertySnap.exists) {
    return {
      propertyId: normalizedPropertyId,
      propertyScopeId: "",
      propertySnap,
      propertyData: null,
    };
  }

  const propertyData = propertySnap.data() || {};
  const propertyScopeId =
    normalizeScopeId(propertyData.propertyScopeId) || computePropertyScopeId(normalizedPropertyId);
  return {
    propertyId: normalizedPropertyId,
    propertyScopeId,
    propertySnap,
    propertyData,
  };
}

function propertyRefCandidates(propertyId) {
  const normalizedPropertyId = normalizeId(propertyId);
  if (!normalizedPropertyId) return [];
  return [
    firestore.collection("ruralProperties").doc(normalizedPropertyId),
    normalizedPropertyId,
    `/ruralProperties/${normalizedPropertyId}`,
  ];
}

function entityMatchesProperty(data, expectedPropertyId, expectedScopeId) {
  if (!data || typeof data !== "object") return false;
  if (normalizeId(data.propertyId) === expectedPropertyId) return true;
  const runtimeStatus = data.runtimeStatus && typeof data.runtimeStatus === "object"
    ? data.runtimeStatus
    : {};
  if (normalizeId(runtimeStatus.propertyId) === expectedPropertyId) return true;
  const directScopeId = normalizeScopeId(
    data.propertyScopeId || runtimeStatus.propertyScopeId,
  );
  return Boolean(expectedScopeId && directScopeId === expectedScopeId);
}

async function findMatrixGatewayDocForProperty(propertyId, expectedScopeId = "") {
  const normalizedPropertyId = normalizeId(propertyId);
  if (!normalizedPropertyId) return null;

  const byId = new Map();
  for (const candidate of propertyRefCandidates(normalizedPropertyId)) {
    const snap = await firestore
      .collection("gateways")
      .where("propertyId", "==", candidate)
      .where("is_matrix", "==", true)
      .limit(5)
      .get();
    for (const doc of snap.docs) {
      byId.set(doc.id, doc);
    }
  }

  if (byId.size === 0 && expectedScopeId) {
    const snap = await firestore
      .collection("gateways")
      .where("is_matrix", "==", true)
      .limit(50)
      .get();
    for (const doc of snap.docs) {
      if (entityMatchesProperty(doc.data() || {}, normalizedPropertyId, expectedScopeId)) {
        byId.set(doc.id, doc);
      }
    }
  }

  if (!byId.size) return null;
  return [...byId.values()].sort((a, b) => a.id.localeCompare(b.id))[0];
}

async function listPropertyTargetDeviceIds(propertyId, propertyScopeId) {
  const normalizedPropertyId = normalizeId(propertyId);
  if (!normalizedPropertyId) return [];

  const byId = new Map();
  for (const candidate of propertyRefCandidates(normalizedPropertyId)) {
    const snap = await firestore
      .collection("collars")
      .where("propertyId", "==", candidate)
      .limit(250)
      .get();
    for (const doc of snap.docs) {
      byId.set(doc.id, doc);
    }
  }

  if (byId.size === 0 && propertyScopeId) {
    const snap = await firestore.collection("collars").limit(250).get();
    for (const doc of snap.docs) {
      if (entityMatchesProperty(doc.data() || {}, normalizedPropertyId, propertyScopeId)) {
        byId.set(doc.id, doc);
      }
    }
  }

  return [...byId.values()]
    .map((doc) => normalizeId(doc.get("deviceId")) || normalizeId(doc.id))
    .filter((deviceId) => /^[1-9][0-9]*$/.test(deviceId))
    .sort();
}

async function resolveRequesterInfo(uid) {
  const normalizedUid = normalizeId(uid);
  if (!normalizedUid) {
    return { uid: "", role: "user" };
  }
  const snap = await firestore.collection("users").doc(normalizedUid).get();
  return {
    uid: normalizedUid,
    role: normalizeRole(snap.get("role")),
  };
}

async function enqueueAutoCommand(commandId, commandDoc) {
  const normalizedCommandId = normalizeId(commandId);
  if (!normalizedCommandId) return false;
  const docRef = firestore.collection("loraCommands").doc(normalizedCommandId);
  const now = admin.firestore.FieldValue.serverTimestamp();
  try {
    await docRef.create({
      ...commandDoc,
      commandId: normalizedCommandId,
      createdAt: now,
      updatedAt: now,
      expiresAt: admin.firestore.Timestamp.fromMillis(commandDoc.expiresAtMs),
    });
    return true;
  } catch (error) {
    const code = normalizeText(error?.code || error?.details);
    if (code === "6" || code === "already-exists" || code === "ALREADY_EXISTS") {
      return false;
    }
    throw error;
  }
}

async function syncAreaLinks(linkPlan) {
  const areaId = normalizeId(linkPlan?.areaId);
  if (!areaId) return;

  const assignIds = autoFenceSync.normalizeDeviceIdList(linkPlan?.assignIds);
  const clearIds = autoFenceSync.normalizeDeviceIdList(linkPlan?.clearIds);
  const clearAreaByDeviceId = {};
  if (clearIds.length) {
    const clearSnaps = await Promise.all(
      clearIds.map((deviceId) => firestore.collection("collars").doc(deviceId).get()),
    );
    for (const snap of clearSnaps) {
      if (!snap.exists) continue;
      clearAreaByDeviceId[snap.id] = normalizeId(snap.get("activeAreaId"));
    }
  }
  const mutations = autoFenceSync.buildAreaLinkMutations({
    areaId,
    beforeLinkedDeviceIds: clearIds,
    afterLinkedDeviceIds: assignIds,
    activeAreaByDeviceId: clearAreaByDeviceId,
  });
  const batch = firestore.batch();
  let opCount = 0;

  for (const mutation of mutations.upserts) {
    const deviceId = mutation.deviceId;
    const collarRef = firestore.collection("collars").doc(deviceId);
    batch.set(
      collarRef,
      {
        ...mutation.patch,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    opCount++;
  }

  for (const mutation of mutations.clears) {
    batch.set(
      firestore.collection("collars").doc(mutation.deviceId),
      {
        activeAreaId: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    opCount++;
  }

  if (opCount > 0) {
    await batch.commit();
  }
}

async function resolveAutoFencePropertyMeta(propertyId) {
  const propertyMeta = await resolvePropertyScopeMeta(propertyId);
  if (!propertyMeta.propertyData || !propertyMeta.propertyScopeId) {
    return {
      propertyId: normalizeId(propertyId),
      propertyScopeId: "",
      matrixGatewayId: "",
      propertyData: propertyMeta.propertyData,
    };
  }
  const matrixDoc = await findMatrixGatewayDocForProperty(
    propertyMeta.propertyId,
    propertyMeta.propertyScopeId,
  );
  return {
    propertyId: propertyMeta.propertyId,
    propertyScopeId: propertyMeta.propertyScopeId,
    matrixGatewayId: matrixDoc ? matrixDoc.id : "",
    propertyData: propertyMeta.propertyData,
  };
}

async function syncMatrixBindingMirror(gatewayId, gatewayData) {
  const beforePathCandidates = [sanitizeRtdbKey(gatewayId)];
  const runtimeId = matrixRuntimeIdFromGatewayData(gatewayId, gatewayData);
  if (runtimeId && !beforePathCandidates.includes(runtimeId)) {
    beforePathCandidates.push(runtimeId);
  }

  if (!gatewayData || gatewayData.is_matrix !== true) {
    await Promise.all(beforePathCandidates.map((key) => rtdb.ref(`matrixBindings/${key}`).remove()));
    return;
  }

  const propertyId = normalizeId(gatewayData.propertyId);
  const propertyMeta = await resolvePropertyScopeMeta(propertyId);
  const propertyScopeId = propertyMeta.propertyScopeId;
  const runtimeStatus = gatewayData.runtimeStatus && typeof gatewayData.runtimeStatus === "object"
    ? gatewayData.runtimeStatus
    : {};
  const supportsScopedLora =
    gatewayData.supportsScopedLora === true ||
    runtimeStatus.supportsScopedLora === true;
  const bindingReady =
    gatewayData.bindingReady === true || runtimeStatus.bindingReady === true;
  const enabled =
    Boolean(propertyId) &&
    Boolean(propertyScopeId) &&
    supportsScopedLora &&
    bindingReady;

  const bindingPayload = {
    propertyId,
    propertyScopeId,
    matrixGatewayId: normalizeId(gatewayId),
    matrixRuntimeId: runtimeId,
    enabled,
    updatedAtMs: Date.now(),
  };

  await rtdb.ref(`matrixBindings/${runtimeId}`).set(bindingPayload);
  if (runtimeId !== sanitizeRtdbKey(gatewayId)) {
    await rtdb.ref(`matrixBindings/${sanitizeRtdbKey(gatewayId)}`).set(bindingPayload);
  }

  const patch = {};
  if (propertyScopeId && normalizeScopeId(gatewayData.propertyScopeId) !== propertyScopeId) {
    patch.propertyScopeId = propertyScopeId;
  }
  if (gatewayData.supportsScopedLora !== true) {
    patch.supportsScopedLora = true;
  }
  const desiredBindingReady = Boolean(propertyId && propertyScopeId);
  if (gatewayData.bindingReady !== desiredBindingReady) {
    patch.bindingReady = desiredBindingReady;
  }
  const desiredRuntimeStatus = {
    ...(runtimeStatus && typeof runtimeStatus === "object" ? runtimeStatus : {}),
    supportsScopedLora: true,
    bindingReady: desiredBindingReady,
    propertyScopeId,
    matrixGatewayId: normalizeId(gatewayId),
  };
  const runtimeStatusChanged =
    normalizeScopeId(runtimeStatus.propertyScopeId) !== propertyScopeId ||
    Boolean(runtimeStatus.bindingReady) !== desiredBindingReady ||
    runtimeStatus.supportsScopedLora !== true ||
    normalizeId(runtimeStatus.matrixGatewayId) !== normalizeId(gatewayId);
  if (runtimeStatusChanged) {
    patch.runtimeStatus = desiredRuntimeStatus;
  }
  if (!normalizeText(gatewayData.rtdbMatrixId) && runtimeId) {
    patch.rtdbMatrixId = runtimeId;
  }
  if (Object.keys(patch).length) {
    patch.updatedAt = admin.firestore.FieldValue.serverTimestamp();
    await firestore.collection("gateways").doc(gatewayId).set(patch, { merge: true });
  }
}

async function syncCollarBindingMetadata(collarId, collarData) {
  if (!collarData) return;
  const propertyId = normalizeId(collarData.propertyId);
  if (!propertyId) return;

  const propertyMeta = await resolvePropertyScopeMeta(propertyId);
  const propertyScopeId = propertyMeta.propertyScopeId;
  if (!propertyScopeId) return;

  const runtimeStatus = collarData.runtimeStatus && typeof collarData.runtimeStatus === "object"
    ? collarData.runtimeStatus
    : {};
  const desiredBindingReady = true;
  const patch = {};
  if (normalizeScopeId(collarData.propertyScopeId) !== propertyScopeId) {
    patch.propertyScopeId = propertyScopeId;
  }
  if (collarData.supportsScopedLora !== true) {
    patch.supportsScopedLora = true;
  }
  if (collarData.bindingReady !== desiredBindingReady) {
    patch.bindingReady = desiredBindingReady;
  }
  const runtimeStatusChanged =
    normalizeScopeId(runtimeStatus.propertyScopeId) !== propertyScopeId ||
    Boolean(runtimeStatus.bindingReady) !== desiredBindingReady ||
    runtimeStatus.supportsScopedLora !== true;
  if (runtimeStatusChanged) {
    patch.runtimeStatus = {
      ...(runtimeStatus && typeof runtimeStatus === "object" ? runtimeStatus : {}),
      propertyScopeId,
      bindingReady: desiredBindingReady,
      supportsScopedLora: true,
    };
  }
  if (!Object.keys(patch).length) return;
  await firestore.collection("collars").doc(collarId).set(
    {
      ...patch,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

function isTargetReady(targetData, expectedScopeId) {
  if (!targetData || typeof targetData !== "object") return false;
  const runtimeStatus = targetData.runtimeStatus && typeof targetData.runtimeStatus === "object"
    ? targetData.runtimeStatus
    : {};
  const supportsScopedLora =
    targetData.supportsScopedLora === true ||
    runtimeStatus.supportsScopedLora === true;
  const bindingReady =
    targetData.bindingReady === true || runtimeStatus.bindingReady === true;
  const runtimeScopeId = normalizeScopeId(
    runtimeStatus.propertyScopeId || targetData.propertyScopeId,
  );
  return supportsScopedLora && bindingReady && runtimeScopeId === expectedScopeId;
}

async function validateCommandTargets(command, propertyId, propertyScopeId, targetDeviceIds, targetGatewayIds) {
  if (!targetDeviceIds.length && !targetGatewayIds.length) {
    return {
      ok: false,
      resultReason: "no_targets",
      deviceResults: {},
    };
  }

  const deviceResults = {};
  const collarSnaps = await Promise.all(
    targetDeviceIds.map((deviceId) => firestore.collection("collars").doc(deviceId).get()),
  );
  for (const snap of collarSnaps) {
    if (!snap.exists) {
      return {
        ok: false,
        resultReason: `unknown_target_device:${snap.id}`,
        deviceResults,
      };
    }
    const data = snap.data() || {};
    if (normalizeId(data.propertyId) !== propertyId) {
      return {
        ok: false,
        resultReason: `target_device_property_mismatch:${snap.id}`,
        deviceResults,
      };
    }
    if (!isTargetReady(data, propertyScopeId)) {
      return {
        ok: false,
        resultReason: `target_device_not_ready:${snap.id}`,
        deviceResults,
      };
    }
    deviceResults[snap.id] = {
      status: "validated",
      updatedAtMs: Date.now(),
    };
  }

  const gatewaySnaps = await Promise.all(
    targetGatewayIds.map((gatewayId) => firestore.collection("gateways").doc(gatewayId).get()),
  );
  for (const snap of gatewaySnaps) {
    if (!snap.exists) {
      return {
        ok: false,
        resultReason: `unknown_target_gateway:${snap.id}`,
        deviceResults,
      };
    }
    const data = snap.data() || {};
    if (normalizeId(data.propertyId) !== propertyId) {
      return {
        ok: false,
        resultReason: `target_gateway_property_mismatch:${snap.id}`,
        deviceResults,
      };
    }
    if (!isTargetReady(data, propertyScopeId)) {
      return {
        ok: false,
        resultReason: `target_gateway_not_ready:${snap.id}`,
        deviceResults,
      };
    }
  }

  return {
    ok: true,
    resultReason: null,
    deviceResults,
  };
}

async function updateHerdingOperationFromCommand(commandId, commandData, patch = {}) {
  const businessRef = normalizeBusinessRef(commandData.businessRef);
  if (!businessRef || businessRef.type !== "herdingOperation") return;
  await firestore.collection("herdingOperations").doc(businessRef.id).set(
    {
      loraCommandId: commandId,
      ...patch,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

async function rejectCommand(commandId, resultReason, extra = {}) {
  await firestore.collection("loraCommands").doc(commandId).set(
    {
      status: "rejected",
      resultReason,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...extra,
    },
    { merge: true },
  );
  await appendCommandEvent(commandId, "rejected", {
    resultReason,
    ...extra,
  });
}

async function queueValidatedCommand(commandId, commandData) {
  const command = normalizeText(commandData.command).toUpperCase();
  const propertyId = normalizeId(commandData.propertyId);
  const requestedByUid = normalizeId(commandData.requestedByUid);
  const requestedByRole = normalizeRole(commandData.requestedByRole);
  const propertyMeta = await resolvePropertyScopeMeta(propertyId);
  const expectedScopeId = propertyMeta.propertyScopeId;
  if (!propertyMeta.propertyData || !expectedScopeId) {
    await rejectCommand(commandId, "unknown_property");
    return;
  }

  const requestedScopeId = normalizeScopeId(commandData.propertyScopeId);
  if (!requestedScopeId || requestedScopeId !== expectedScopeId) {
    await rejectCommand(commandId, "property_scope_mismatch", {
      propertyId,
      propertyScopeId: expectedScopeId,
    });
    return;
  }

  if (!ALLOWED_COMMANDS.has(command)) {
    await rejectCommand(commandId, "unsupported_command");
    return;
  }

  const matrixGatewayId = normalizeId(commandData.matrixGatewayId);
  if (!matrixGatewayId) {
    await rejectCommand(commandId, "no_matrix_for_property");
    return;
  }

  const matrixSnap = await firestore.collection("gateways").doc(matrixGatewayId).get();
  if (!matrixSnap.exists) {
    await rejectCommand(commandId, "no_matrix_for_property");
    return;
  }
  const matrixData = matrixSnap.data() || {};
  if (matrixData.is_matrix !== true || normalizeId(matrixData.propertyId) !== propertyId) {
    await rejectCommand(commandId, "no_matrix_for_property");
    return;
  }
  if (!isTargetReady(matrixData, expectedScopeId)) {
    await rejectCommand(commandId, "matrix_not_ready");
    return;
  }

  const matrixRuntimeId = matrixRuntimeIdFromGatewayData(matrixGatewayId, matrixData);
  const queueKeySnap = await rtdb.ref(`matrixQueueKeys/${matrixRuntimeId}`).get();
  const queueKey = extractQueueKey(queueKeySnap.val());
  if (!queueKey) {
    await rejectCommand(commandId, "missing_matrix_queue_key");
    return;
  }

  const targetDeviceIds = normalizeDeviceIdList(commandData.targetDeviceIds);
  const targetGatewayIds = normalizeIdList(commandData.targetGatewayIds);
  const targetValidation = await validateCommandTargets(
    command,
    propertyId,
    expectedScopeId,
    targetDeviceIds,
    targetGatewayIds,
  );
  if (!targetValidation.ok) {
    await rejectCommand(commandId, targetValidation.resultReason, {
      deviceResults: targetValidation.deviceResults,
    });
    return;
  }

  const createdAtMs =
    millisFromTimestamp(commandData.createdAt) ||
    millisFromTimestamp(commandData.updatedAt) ||
    Date.now();
  const requestedExpiresAtMs = millisFromTimestamp(commandData.expiresAt);
  const expiresAtMs =
    requestedExpiresAtMs > createdAtMs
      ? requestedExpiresAtMs
      : commandExpiryMs(command, createdAtMs);
  if (expiresAtMs <= Date.now()) {
    await rejectCommand(commandId, "command_expired");
    return;
  }

  const dispatchData = buildDispatchPayload(commandId, command, commandData);

  const queuePayload = {
    commandId,
    command,
    propertyId,
    propertyScopeId: expectedScopeId,
    matrixGatewayId,
    matrixRuntimeId,
    targetDeviceIds,
    targetGatewayIds,
    payload: dispatchData.payload,
    requestedByUid,
    requestedByRole,
    createdAtMs,
    expiresAtMs,
    businessRef: dispatchData.businessRef,
  };

  await appendCommandEvent(commandId, "validated", {
    propertyId,
    propertyScopeId: expectedScopeId,
    matrixGatewayId,
    matrixRuntimeId,
  });

  await rtdb.ref(`matrixCommandQueues/${matrixRuntimeId}/${queueKey}/${commandId}`).set(queuePayload);

  await firestore.collection("loraCommands").doc(commandId).set(
    {
      commandId,
      command,
      propertyId,
      propertyScopeId: expectedScopeId,
      matrixGatewayId,
      matrixRuntimeId,
      targetDeviceIds,
      targetGatewayIds,
      requestedByUid,
      requestedByRole,
      polygonKind: dispatchData.polygonKind || null,
      originDocType: dispatchData.originDocType || null,
      originDocId: dispatchData.originDocId || null,
      status: "matrix_queued",
      resultReason: null,
      deviceResults: targetValidation.deviceResults,
      expiresAt: admin.firestore.Timestamp.fromMillis(expiresAtMs),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  await appendCommandEvent(commandId, "matrix_queued", {
    matrixRuntimeId,
    queueKeyPresent: true,
  });
  await updateHerdingOperationFromCommand(commandId, commandData, {
    status: "submitted",
  });
}

function mapCommandStatusToHerdingStatus(status) {
  switch (normalizeText(status)) {
    case "dispatching":
    case "validated":
    case "matrix_queued":
      return "dispatching";
    case "acknowledged":
    case "applied":
      return "requested";
    case "completed":
      return "completed";
    case "failed":
    case "expired":
    case "rejected":
    case "nacked":
      return "failed";
    default:
      return "submitted";
  }
}

async function createAreaFromOperation(operationId, payload, currentDocData) {
  const propertyId =
    normalizeId(payload.propertyId) || normalizeId(currentDocData.propertyId);
  const ownerUid =
    normalizeId(payload.ownerUid) ||
    normalizeId(currentDocData.ownerUid) ||
    normalizeId(currentDocData.requestedByUid);
  const polygon = pointList(payload.targetPolygon || currentDocData.targetPolygon);
  if (!propertyId || !ownerUid || polygon.length < 3) {
    return null;
  }

  const propertyRef = firestore.collection("ruralProperties").doc(propertyId);
  const propertySnap = await propertyRef.get();
  const propertyUsers = Array.isArray(propertySnap.get("userUids"))
    ? propertySnap.get("userUids")
    : [];

  const areaRef = await firestore.collection("areas").add({
    ownerUid: firestore.collection("users").doc(ownerUid),
    ruralPropertiesID: propertyRef,
    userUids: propertyUsers,
    perimeter: polygon,
    source: "herding_operation",
    sourceOperationId: operationId,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return areaRef.id;
}

async function updateCollarsWithArea(operationId, areaId, selectedDeviceIds) {
  const batch = firestore.batch();
  const normalized = [...new Set((selectedDeviceIds || []).map(normalizeId).filter(Boolean))];
  for (const deviceId of normalized) {
    const collarRef = firestore.collection("collars").doc(deviceId);
    batch.set(
      collarRef,
      {
        activeAreaId: areaId,
        lastHerdingOperationId: operationId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
  if (normalized.length) {
    await batch.commit();
  }
}

exports.syncPropertyScopeAndAccess = onDocumentWritten(
  "ruralProperties/{propertyId}",
  async (event) => {
    const propertyId = normalizeId(event.params.propertyId);
    const after = event.data.after.exists ? event.data.after.data() || {} : null;

    if (!propertyId) return;
    await syncPropertyAccessMirror(propertyId, after);
    if (!after) return;

    const expectedScopeId = computePropertyScopeId(propertyId);
    if (normalizeScopeId(after.propertyScopeId) !== expectedScopeId) {
      await firestore.collection("ruralProperties").doc(propertyId).set(
        {
          propertyScopeId: expectedScopeId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
  },
);

exports.syncMatrixBindings = onDocumentWritten(
  "gateways/{gatewayId}",
  async (event) => {
    const gatewayId = normalizeId(event.params.gatewayId);
    const after = event.data.after.exists ? event.data.after.data() || {} : null;
    await syncMatrixBindingMirror(gatewayId, after);
  },
);

exports.syncCollarPropertyScope = onDocumentWritten(
  "collars/{collarId}",
  async (event) => {
    const collarId = normalizeId(event.params.collarId);
    const after = event.data.after.exists ? event.data.after.data() || {} : null;
    await syncCollarBindingMetadata(collarId, after);
  },
);

exports.autoSyncPropertyFence = onDocumentWritten(
  "ruralProperties/{propertyId}",
  async (event) => {
    const propertyId = normalizeId(event.params.propertyId);
    const before = event.data.before.exists ? event.data.before.data() || {} : null;
    const after = event.data.after.exists ? event.data.after.data() || {} : null;
    if (!propertyId || !after) return;

    const result = await autoFenceSync.runPropertyPolygonAutoSync({
      propertyId,
      beforeData: before,
      afterData: after,
      deps: {
        resolvePropertyMeta: resolveAutoFencePropertyMeta,
        listPropertyTargetDeviceIds,
        resolveRequester: resolveRequesterInfo,
        enqueueAutoCommand,
      },
    });
    logger.info("autoSyncPropertyFence", {
      propertyId,
      ...result,
    });
  },
);

exports.autoSyncAreaFence = onDocumentWritten(
  "areas/{areaId}",
  async (event) => {
    const areaId = normalizeId(event.params.areaId);
    const before = event.data.before.exists ? event.data.before.data() || {} : null;
    const after = event.data.after.exists ? event.data.after.data() || {} : null;
    if (!areaId || !after) return;

    const result = await autoFenceSync.runAreaPolygonAutoSync({
      areaId,
      beforeData: before,
      afterData: after,
      deps: {
        resolvePropertyMeta: resolveAutoFencePropertyMeta,
        resolveRequester: resolveRequesterInfo,
        enqueueAutoCommand,
        syncAreaLinks,
      },
    });
    logger.info("autoSyncAreaFence", {
      areaId,
      ...result,
    });
  },
);

exports.queueLoraCommand = onDocumentCreated(
  "loraCommands/{commandId}",
  async (event) => {
    const commandId = normalizeId(event.params.commandId);
    const data = event.data.data() || {};
    if (!commandId) return;

    await appendCommandEvent(commandId, "queued");
    await queueValidatedCommand(commandId, data);
  },
);

exports.syncMatrixCommandResult = onValueWritten(
  "/matrixCommandResults/{matrixId}/{commandId}",
  async (event) => {
    const matrixId = sanitizeRtdbKey(event.params.matrixId);
    const commandId = normalizeId(event.params.commandId);
    const after = event.data.after.val();
    if (!matrixId || !commandId || !after || typeof after !== "object") {
      return;
    }

    const docRef = firestore.collection("loraCommands").doc(commandId);
    const commandSnap = await docRef.get();
    if (!commandSnap.exists) {
      logger.warn("matrixCommandResults without matching loraCommand", {
        matrixId,
        commandId,
      });
      return;
    }

    const commandData = commandSnap.data() || {};
    const status = normalizeText(after.status || "dispatching") || "dispatching";
    const resultReason = normalizeText(after.reason || after.resultReason) || null;
    const deviceResults =
      after.deviceResults && typeof after.deviceResults === "object"
        ? after.deviceResults
        : {};
    const patch = {
      status,
      resultReason,
      matrixRuntimeId: matrixId,
      deviceResults,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastMatrixResult: after,
    };
    if (TERMINAL_COMMAND_STATUSES.has(status)) {
      patch.completedAt = admin.firestore.FieldValue.serverTimestamp();
    }
    await docRef.set(patch, { merge: true });
    await appendCommandEvent(commandId, status, {
      matrixRuntimeId: matrixId,
      resultReason,
      deviceResults,
    });

    const businessRef = normalizeBusinessRef(commandData.businessRef);
    if (businessRef && businessRef.type === "herdingOperation") {
      const opPatch = {
        status: mapCommandStatusToHerdingStatus(status),
        failureReason: resultReason,
      };
      if (status === "completed" && normalizeId(after.createdAreaId)) {
        opPatch.createdAreaId = normalizeId(after.createdAreaId);
      }
      await firestore.collection("herdingOperations").doc(businessRef.id).set(
        {
          ...opPatch,
          deviceStatuses: deviceResults,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
  },
);

exports.mirrorPropertyEvent = onValueWritten(
  "/propertyEvents/{propertyId}/{dayKey}/{eventId}",
  async (event) => {
    const propertyId = normalizeId(event.params.propertyId);
    const dayKey = normalizeText(event.params.dayKey);
    const eventId = normalizeText(event.params.eventId);
    const after = event.data.after.val();
    if (!propertyId || !dayKey || !eventId || !after || typeof after !== "object") {
      return;
    }

    const propertyMeta = await resolvePropertyScopeMeta(propertyId);
    if (!propertyMeta.propertyData) return;

    const deviceId = normalizeId(after.deviceId);
    let ownerUid = normalizeId(after.ownerUid);
    if (!ownerUid && deviceId) {
      const collarSnap = await firestore.collection("collars").doc(deviceId).get();
      ownerUid = normalizeId(collarSnap.get("ownerUid"));
    }

    const fireEventId = `${sanitizeRtdbKey(propertyId)}_${sanitizeRtdbKey(dayKey)}_${sanitizeRtdbKey(eventId)}`;
    await firestore.collection("events").doc(fireEventId).set(
      {
        ...after,
        propertyId,
        propertyScopeId: propertyMeta.propertyScopeId,
        ownerUid: ownerUid ? firestore.collection("users").doc(ownerUid) : null,
        createdAt:
          timestampFromMs(after.receivedAtMs || after.createdAtMs || Date.now()) ||
          admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    const severity = normalizeText(after.severity).toLowerCase();
    const critical =
      after.critical === true || severity === "high" || severity === "critical";
    if (critical) {
      await sendPush({
        userIds: collectUserIdsFromProperty(propertyMeta.propertyData),
        title: "Evento critico da propriedade",
        body: normalizeText(after.eventType || after.type || "Novo evento critico"),
        data: {
          type: "property_event",
          propertyId,
          eventId: fireEventId,
          deviceId,
        },
      });
    }
  },
);

exports.syncHerdingOperation = onValueWritten(
  "/herdingOperations/{operationId}",
  async (event) => {
    const operationId = normalizeId(event.params.operationId);
    const after = event.data.after.val();
    if (!operationId || !after || typeof after !== "object") {
      return;
    }

    const before = event.data.before.val() || {};
    const docRef = firestore.collection("herdingOperations").doc(operationId);
    const currentDoc = await docRef.get();
    const currentData = currentDoc.data() || {};

    const update = {
      operationId,
      status: String(after.status || currentData.status || "submitted"),
      matrixGatewayId:
        normalizeId(after.matrixGatewayId) || currentData.matrixGatewayId || null,
      selectedDeviceIds: Array.isArray(after.selectedDeviceIds)
        ? after.selectedDeviceIds.map(normalizeId).filter(Boolean)
        : currentData.selectedDeviceIds || [],
      notifyUserIds: Array.isArray(after.notifyUserIds)
        ? after.notifyUserIds.map(normalizeId).filter(Boolean)
        : currentData.notifyUserIds || [],
      targetPolygon: pointList(after.targetPolygon || currentData.targetPolygon),
      deviceStatuses:
        after.deviceStatuses && typeof after.deviceStatuses === "object"
          ? after.deviceStatuses
          : currentData.deviceStatuses || {},
      updatedAt:
        timestampFromMs(after.updatedAt) ||
        admin.firestore.FieldValue.serverTimestamp(),
      failureReason: after.failureReason || null,
      clientFailureReason: after.clientFailureReason || null,
    };

    if (normalizeId(after.propertyId)) {
      update.propertyId = normalizeId(after.propertyId);
    }
    if (normalizeId(after.ownerUid)) {
      update.ownerUid = firestore.collection("users").doc(normalizeId(after.ownerUid));
    }
    if (normalizeId(after.requestedByUid)) {
      update.requestedByUid = firestore
        .collection("users")
        .doc(normalizeId(after.requestedByUid));
    }
    if (after.createdAreaId) {
      update.createdAreaId = normalizeId(after.createdAreaId);
    }
    if (after.requestedAt) {
      update.requestedAt = timestampFromMs(after.requestedAt);
    }
    if (after.completedAt) {
      update.completedAt = timestampFromMs(after.completedAt);
    }

    await docRef.set(update, { merge: true });

    const notifyUserIds = update.notifyUserIds || [];
    const nextStatus = String(update.status);
    const previousStatus = String(before.status || "");

    if (nextStatus === "requested" && previousStatus !== "requested") {
      await sendPush({
        userIds: notifyUserIds,
        title: "Arrebanhamento solicitado",
        body: "Todas as coleiras selecionadas receberam e montaram o comando.",
        data: {
          type: "herding_requested",
          operationId,
          status: nextStatus,
        },
      });
    }

    if (nextStatus === "completed" && previousStatus !== "completed") {
      let areaId = normalizeId(after.createdAreaId) || normalizeId(currentData.createdAreaId);
      if (!areaId) {
        areaId = await createAreaFromOperation(operationId, after, currentData);
      }

      if (areaId) {
        await updateCollarsWithArea(
          operationId,
          areaId,
          update.selectedDeviceIds || [],
        );
        await docRef.set(
          {
            createdAreaId: areaId,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }

      await sendPush({
        userIds: notifyUserIds,
        title: "Arrebanhamento finalizado",
        body: areaId
          ? "Os animais chegaram ao poligono final e a area foi cadastrada."
          : "Os animais chegaram ao poligono final.",
        data: {
          type: "herding_completed",
          operationId,
          status: nextStatus,
          createdAreaId: areaId || "",
        },
      });
    }

    logger.info("Herding operation synced", {
      operationId,
      status: nextStatus,
    });
  },
);
