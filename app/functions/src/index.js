const admin = require("firebase-admin");
const { onValueWritten } = require("firebase-functions/v2/database");
const { logger } = require("firebase-functions");

admin.initializeApp();

const firestore = admin.firestore();
const messaging = admin.messaging();

function normalizeId(value) {
  if (value == null) return "";
  const raw = String(value).trim();
  if (!raw) return "";
  if (!raw.includes("/")) return raw;
  const parts = raw.split("/").filter(Boolean);
  return parts.length ? parts[parts.length - 1] : raw;
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

function timestampFromMs(value) {
  const ms = Number(value);
  if (!Number.isFinite(ms) || ms <= 0) return null;
  return admin.firestore.Timestamp.fromMillis(ms);
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
