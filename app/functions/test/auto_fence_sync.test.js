const test = require("node:test");
const assert = require("node:assert/strict");

const autoFenceSync = require("../src/auto_fence_sync");

test("property polygon change creates one deterministic SET_FENCE for all property collars", async () => {
  const createdCommands = [];

  const result = await autoFenceSync.runPropertyPolygonAutoSync({
    propertyId: "property-1",
    beforeData: {
      points: [
        [-16.0, -49.0],
        [-16.1, -49.0],
        [-16.1, -49.1],
      ],
    },
    afterData: {
      points: [
        [-16.0, -49.0],
        [-16.1, -49.0],
        [-16.2, -49.1],
      ],
      updatedByUid: { id: "user-7" },
    },
    deps: {
      resolvePropertyMeta: async () => ({
        propertyScopeId: "DEADBEEF00000001",
        matrixGatewayId: "matrix-1",
      }),
      listPropertyTargetDeviceIds: async () => ["2", "1", "invalid", "1"],
      resolveRequester: async (uid) => ({ uid, role: "adm" }),
      enqueueAutoCommand: async (commandId, commandDoc) => {
        createdCommands.push({ commandId, commandDoc });
        return true;
      },
      nowMs: () => 1234567890,
    },
  });

  assert.equal(result.ok, true);
  assert.equal(result.enqueued, true);
  assert.equal(createdCommands.length, 1);
  assert.deepEqual(createdCommands[0].commandDoc.targetDeviceIds, ["1", "2"]);
  assert.deepEqual(createdCommands[0].commandDoc.payload.points, [
    [-16, -49],
    [-16.1, -49],
    [-16.2, -49.1],
  ]);
  assert.equal(createdCommands[0].commandDoc.payload.cmd_id, createdCommands[0].commandId);
  assert.equal(createdCommands[0].commandDoc.payload.command_id, createdCommands[0].commandId);
  assert.equal(createdCommands[0].commandDoc.payload.polygon_kind, "property");
  assert.equal(createdCommands[0].commandDoc.payload.origin_doc_type, "ruralProperty");
  assert.equal(createdCommands[0].commandDoc.payload.origin_doc_id, "property-1");
  assert.equal(createdCommands[0].commandDoc.requestedByUid, "user-7");
  assert.equal(createdCommands[0].commandDoc.requestedByRole, "adm");
  assert.match(createdCommands[0].commandId, /^auto-ruralProperty-property-1-/);
});

test("area perimeter edit with linked collars syncs active area and enqueues selective SET_FENCE", async () => {
  const createdCommands = [];
  const syncedPlans = [];

  const result = await autoFenceSync.runAreaPolygonAutoSync({
    areaId: "area-9",
    beforeData: {
      perimeter: [
        [-16.0, -49.0],
        [-16.1, -49.0],
        [-16.1, -49.1],
      ],
      linkedDeviceIds: ["1"],
    },
    afterData: {
      ruralPropertiesID: { id: "property-1" },
      perimeter: [
        [-16.0, -49.0],
        [-16.1, -49.0],
        [-16.2, -49.1],
      ],
      linkedDeviceIds: ["2", "3"],
      updatedByUid: "user-3",
    },
    deps: {
      resolvePropertyMeta: async () => ({
        propertyScopeId: "DEADBEEF00000001",
        matrixGatewayId: "matrix-1",
      }),
      resolveRequester: async (uid) => ({ uid, role: "user" }),
      enqueueAutoCommand: async (commandId, commandDoc) => {
        createdCommands.push({ commandId, commandDoc });
        return true;
      },
      syncAreaLinks: async (plan) => {
        syncedPlans.push(plan);
      },
      nowMs: () => 1234567890,
    },
  });

  assert.equal(result.ok, true);
  assert.equal(result.enqueued, true);
  assert.deepEqual(result.linkPlan.assignIds, ["2", "3"]);
  assert.deepEqual(result.linkPlan.clearIds, ["1"]);
  assert.deepEqual(syncedPlans, [result.linkPlan]);
  assert.equal(createdCommands.length, 1);
  assert.deepEqual(createdCommands[0].commandDoc.targetDeviceIds, ["2", "3"]);
  assert.equal(createdCommands[0].commandDoc.origin, "auto_area_polygon_sync");
  assert.equal(createdCommands[0].commandDoc.payload.polygon_kind, "area");
  assert.equal(createdCommands[0].commandDoc.payload.origin_doc_type, "area");
  assert.equal(createdCommands[0].commandDoc.payload.origin_doc_id, "area-9");
});

test("metadata-only area update does not enqueue fence and does not rewrite links", async () => {
  let syncCalls = 0;
  let enqueueCalls = 0;

  const result = await autoFenceSync.runAreaPolygonAutoSync({
    areaId: "area-9",
    beforeData: {
      ruralPropertiesID: { id: "property-1" },
      perimeter: [
        [-16.0, -49.0],
        [-16.1, -49.0],
        [-16.1, -49.1],
      ],
      linkedDeviceIds: ["2", "3"],
      updatedAt: 1,
    },
    afterData: {
      ruralPropertiesID: { id: "property-1" },
      perimeter: [
        [-16.0, -49.0],
        [-16.1, -49.0],
        [-16.1, -49.1],
      ],
      linkedDeviceIds: ["2", "3"],
      updatedAt: 2,
      propertyScopeId: "DEADBEEF00000001",
    },
    deps: {
      resolvePropertyMeta: async () => ({
        propertyScopeId: "DEADBEEF00000001",
        matrixGatewayId: "matrix-1",
      }),
      resolveRequester: async () => ({ uid: "", role: "user" }),
      enqueueAutoCommand: async () => {
        enqueueCalls++;
        return true;
      },
      syncAreaLinks: async () => {
        syncCalls++;
      },
    },
  });

  assert.equal(result.ok, true);
  assert.equal(result.reason, "no_fence_change");
  assert.equal(result.enqueued, false);
  assert.equal(syncCalls, 0);
  assert.equal(enqueueCalls, 0);
});

test("areas created by herding operation do not re-enqueue fence sync", async () => {
  let syncCalls = 0;
  let enqueueCalls = 0;

  const result = await autoFenceSync.runAreaPolygonAutoSync({
    areaId: "area-9",
    beforeData: null,
    afterData: {
      source: "herding_operation",
      linkedDeviceIds: ["2", "3"],
      perimeter: [
        [-16.0, -49.0],
        [-16.1, -49.0],
        [-16.1, -49.1],
      ],
    },
    deps: {
      resolvePropertyMeta: async () => ({
        propertyScopeId: "DEADBEEF00000001",
        matrixGatewayId: "matrix-1",
      }),
      resolveRequester: async () => ({ uid: "", role: "user" }),
      enqueueAutoCommand: async () => {
        enqueueCalls++;
        return true;
      },
      syncAreaLinks: async () => {
        syncCalls++;
      },
    },
  });

  assert.equal(result.ok, true);
  assert.equal(result.reason, "ignored_herding_area");
  assert.equal(syncCalls, 0);
  assert.equal(enqueueCalls, 0);
});

test("deterministic command id avoids duplicate re-enqueue on trigger replay", async () => {
  const commandA = autoFenceSync.buildAutoFenceCommand({
    origin: "auto_property_polygon_sync",
    originDocType: "ruralProperty",
    originDocId: "property-1",
    propertyId: "property-1",
    propertyScopeId: "DEADBEEF00000001",
    matrixGatewayId: "matrix-1",
    targetDeviceIds: ["3", "1"],
    requestedByUid: "user-1",
    requestedByRole: "adm",
    points: [
      [-16.0, -49.0],
      [-16.1, -49.0],
      [-16.2, -49.1],
    ],
    nowMs: 1,
  });
  const commandB = autoFenceSync.buildAutoFenceCommand({
    origin: "auto_property_polygon_sync",
    originDocType: "ruralProperty",
    originDocId: "property-1",
    propertyId: "property-1",
    propertyScopeId: "DEADBEEF00000001",
    matrixGatewayId: "matrix-1",
    targetDeviceIds: ["1", "3"],
    requestedByUid: "user-9",
    requestedByRole: "user",
    points: [
      [-16.0, -49.0],
      [-16.1, -49.0],
      [-16.2, -49.1],
    ],
    nowMs: 2,
  });

  assert.equal(commandA.commandId, commandB.commandId);

  let enqueueCalls = 0;
  const replayResult = await autoFenceSync.runPropertyPolygonAutoSync({
    propertyId: "property-1",
    beforeData: {
      points: [
        [-16.0, -49.0],
        [-16.1, -49.0],
        [-16.1, -49.1],
      ],
    },
    afterData: {
      points: [
        [-16.0, -49.0],
        [-16.1, -49.0],
        [-16.2, -49.1],
      ],
      updatedByUid: "user-1",
    },
    deps: {
      resolvePropertyMeta: async () => ({
        propertyScopeId: "DEADBEEF00000001",
        matrixGatewayId: "matrix-1",
      }),
      listPropertyTargetDeviceIds: async () => ["3", "1"],
      resolveRequester: async () => ({ uid: "user-1", role: "adm" }),
      enqueueAutoCommand: async () => {
        enqueueCalls++;
        return false;
      },
      nowMs: () => 3,
    },
  });

  assert.equal(enqueueCalls, 1);
  assert.equal(replayResult.reason, "duplicate");
  assert.equal(replayResult.enqueued, false);
});

test("removed collars only clear activeAreaId when they still point to the same area", () => {
  const mutations = autoFenceSync.buildAreaLinkMutations({
    areaId: "area-9",
    beforeLinkedDeviceIds: ["1", "2", "3"],
    afterLinkedDeviceIds: ["2"],
    activeAreaByDeviceId: {
      "1": "area-9",
      "3": "another-area",
    },
  });

  assert.deepEqual(
    mutations.upserts,
    [{ deviceId: "2", patch: { activeAreaId: "area-9" } }],
  );
  assert.deepEqual(
    mutations.clears,
    [{ deviceId: "1", clearActiveAreaId: true }],
  );
});
