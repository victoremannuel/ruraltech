import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { after, before, beforeEach, describe, it } from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import { get, ref, set } from "firebase/database";

const projectId = "demo-ruraltech";
const rules = readFileSync(resolve(process.cwd(), "../database.rules.json"), "utf8");

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    database: { rules },
  });
});

beforeEach(async () => {
  await testEnv.clearDatabase();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.database();
    await set(ref(db, "matrixWriterKeys/MATRIX_A"), "super-secret-key");
    await set(ref(db, "matrixQueueKeys/MATRIX_A"), {
      queueKey: "queue-secret-key",
      matrixRuntimeId: "MATRIX_A",
      updatedAtMs: 1730000000000,
      writer: "gateway_matrix",
      writerKey: "super-secret-key",
    });
    await set(ref(db, "matrixBindings/MATRIX_A"), {
      propertyId: "farm-1",
      propertyScopeId: "DEADBEEF00000001",
      matrixGatewayId: "matrix-1",
      matrixRuntimeId: "MATRIX_A",
      enabled: true,
      updatedAtMs: 1730000000000,
      writer: "gateway_matrix",
      writerKey: "super-secret-key",
    });
    await set(ref(db, "propertyAccess/farm-1/owner-user"), true);
    await set(ref(db, "propertyAccess/farm-1/linked-user"), true);
    await set(ref(db, "matrixCommandQueues/MATRIX_A/queue-secret-key/cmd-1"), {
      commandId: "cmd-1",
      command: "PING",
      propertyId: "farm-1",
      propertyScopeId: "DEADBEEF00000001",
      matrixGatewayId: "matrix-1",
      matrixRuntimeId: "MATRIX_A",
      requestedByUid: "owner-user",
      requestedByRole: "user",
      createdAtMs: 1730000000000,
      expiresAtMs: 1730000060000,
    });
  });
});

after(async () => {
  await testEnv.cleanup();
});

describe("Realtime Database rules", () => {
  it("allows unauthenticated matrix writer with valid key on property-scoped paths", async () => {
    const unauthCtx = testEnv.unauthenticatedContext();
    const db = unauthCtx.database();

    const telemetryPayload = {
      deviceId: "101",
      propertyId: "farm-1",
      propertyScopeId: "DEADBEEF00000001",
      lat: -20.1234,
      lon: -43.9876,
      receivedAt: 1730000000,
      writer: "gateway_matrix",
      matrixId: "MATRIX_A",
      writerKey: "super-secret-key",
    };

    await assertSucceeds(
      set(ref(db, "propertyTelemetryLatest/farm-1/101"), telemetryPayload),
    );
    await assertSucceeds(
      set(
        ref(db, "propertyTelemetryHistory/farm-1/101/20260227/1730000000000"),
        telemetryPayload,
      ),
    );
    await assertSucceeds(
      set(ref(db, "propertyHealthLatest/farm-1/101"), {
        deviceId: "101",
        propertyId: "farm-1",
        propertyScopeId: "DEADBEEF00000001",
        kind: "health_daily",
        receivedAt: 1730000000,
        writer: "gateway_matrix",
        matrixId: "MATRIX_A",
        writerKey: "super-secret-key",
      }),
    );
    await assertSucceeds(
      set(ref(db, "propertyEvents/farm-1/20260227/evt-1"), {
        propertyId: "farm-1",
        propertyScopeId: "DEADBEEF00000001",
        receivedAt: 1730000000,
        writer: "gateway_matrix",
        matrixId: "MATRIX_A",
        writerKey: "super-secret-key",
        deviceId: "101",
        eventType: "boundary_breach",
      }),
    );
    await assertSucceeds(
      set(ref(db, "matrixCommandResults/MATRIX_A/cmd-1"), {
        commandId: "cmd-1",
        propertyId: "farm-1",
        propertyScopeId: "DEADBEEF00000001",
        status: "completed",
        updatedAtMs: 1730000000000,
        writer: "gateway_matrix",
        matrixId: "MATRIX_A",
        writerKey: "super-secret-key",
      }),
    );
    await assertSucceeds(
      set(ref(db, "propertyCommands/farm-1/cmd-1"), {
        commandId: "cmd-1",
        command: "PING",
        propertyId: "farm-1",
        propertyScopeId: "DEADBEEF00000001",
        matrixGatewayId: "matrix-1",
        matrixRuntimeId: "MATRIX_A",
        requestedByUid: "owner-user",
        requestedByRole: "user",
        status: "acknowledged",
        updatedAtMs: 1730000000000,
        expiresAtMs: 1730000060000,
        writer: "gateway_matrix",
        writerKey: "super-secret-key",
      }),
    );
    await assertSucceeds(
      set(ref(db, "propertyCommandEvents/farm-1/cmd-1/evt-1"), {
        type: "acknowledged",
        status: "acknowledged",
        matrixId: "MATRIX_A",
        createdAtMs: 1730000000000,
        writer: "gateway_matrix",
        writerKey: "super-secret-key",
      }),
    );
  });

  it("rejects unauthenticated matrix writer with invalid key", async () => {
    const unauthCtx = testEnv.unauthenticatedContext();
    const db = unauthCtx.database();

    await assertFails(
      set(ref(db, "propertyTelemetryLatest/farm-1/101"), {
        deviceId: "101",
        propertyId: "farm-1",
        propertyScopeId: "DEADBEEF00000001",
        lat: -20.1234,
        lon: -43.9876,
        receivedAt: 1730000000,
        writer: "gateway_matrix",
        matrixId: "MATRIX_A",
        writerKey: "wrong-key",
      }),
    );
  });

  it("rejects matrix payload with invalid coordinates", async () => {
    const unauthCtx = testEnv.unauthenticatedContext();
    const db = unauthCtx.database();

    await assertFails(
      set(ref(db, "propertyTelemetryLatest/farm-1/101"), {
        deviceId: "101",
        propertyId: "farm-1",
        propertyScopeId: "DEADBEEF00000001",
        lat: -200,
        lon: -43.9876,
        receivedAt: 1730000000,
        writer: "gateway_matrix",
        matrixId: "MATRIX_A",
        writerKey: "super-secret-key",
      }),
    );
  });

  it("allows the matrix to read its queue only with the right queue key", async () => {
    const unauthCtx = testEnv.unauthenticatedContext();
    const db = unauthCtx.database();

    await assertSucceeds(
      get(ref(db, "matrixCommandQueues/MATRIX_A/queue-secret-key/cmd-1")),
    );
    await assertSucceeds(
      set(ref(db, "matrixCommandQueues/MATRIX_A/queue-secret-key/cmd-1"), null),
    );
    await assertFails(
      get(ref(db, "matrixCommandQueues/MATRIX_A/wrong-key/cmd-1")),
    );
    await assertFails(
      set(ref(db, "matrixCommandQueues/MATRIX_A/wrong-key/cmd-1"), null),
    );
  });

  it("allows the matrix to self-publish queue key and binding mirrors with writer auth", async () => {
    const unauthCtx = testEnv.unauthenticatedContext();
    const db = unauthCtx.database();

    await assertSucceeds(
      set(ref(db, "matrixQueueKeys/MATRIX_A"), {
        queueKey: "queue-secret-key",
        matrixRuntimeId: "MATRIX_A",
        updatedAtMs: 1730000100000,
        writer: "gateway_matrix",
        writerKey: "super-secret-key",
      }),
    );

    await assertSucceeds(
      set(ref(db, "matrixBindings/MATRIX_A"), {
        propertyId: "farm-1",
        propertyScopeId: "DEADBEEF00000001",
        matrixGatewayId: "matrix-1",
        matrixRuntimeId: "MATRIX_A",
        enabled: true,
        updatedAtMs: 1730000100000,
        writer: "gateway_matrix",
        writerKey: "super-secret-key",
      }),
    );
  });

  it("allows authenticated property users to read their property-scoped telemetry and events", async () => {
    const ownerCtx = testEnv.authenticatedContext("owner-user");
    const otherCtx = testEnv.authenticatedContext("other-user");
    const ownerDb = ownerCtx.database();
    const otherDb = otherCtx.database();

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.database();
      await set(ref(db, "propertyTelemetryLatest/farm-1/101"), {
        deviceId: "101",
        propertyId: "farm-1",
        propertyScopeId: "DEADBEEF00000001",
        lat: -20.1234,
        lon: -43.9876,
        receivedAt: 1730000000,
        writer: "gateway_matrix",
        matrixId: "MATRIX_A",
        writerKey: "super-secret-key",
      });
      await set(
        ref(db, "propertyTelemetryHistory/farm-1/101/20260227/1730000000000"),
        {
          deviceId: "101",
          propertyId: "farm-1",
          propertyScopeId: "DEADBEEF00000001",
          lat: -20.1234,
          lon: -43.9876,
          receivedAt: 1730000000,
          writer: "gateway_matrix",
          matrixId: "MATRIX_A",
          writerKey: "super-secret-key",
        },
      );
      await set(ref(db, "propertyHealthLatest/farm-1/101"), {
        deviceId: "101",
        propertyId: "farm-1",
        propertyScopeId: "DEADBEEF00000001",
        kind: "health_daily",
        receivedAt: 1730000000,
        writer: "gateway_matrix",
        matrixId: "MATRIX_A",
        writerKey: "super-secret-key",
      });
      await set(
        ref(db, "propertyHealthHistory/farm-1/101/20260227/1730000000001"),
        {
          deviceId: "101",
          propertyId: "farm-1",
          propertyScopeId: "DEADBEEF00000001",
          kind: "health_daily",
          receivedAt: 1730000001,
          writer: "gateway_matrix",
          matrixId: "MATRIX_A",
          writerKey: "super-secret-key",
        },
      );
      await set(ref(db, "propertyEvents/farm-1/20260227/evt-1"), {
        propertyId: "farm-1",
        propertyScopeId: "DEADBEEF00000001",
        receivedAt: 1730000000,
        writer: "gateway_matrix",
        matrixId: "MATRIX_A",
        writerKey: "super-secret-key",
        deviceId: "101",
      });
      await set(ref(db, "propertyCommands/farm-1/cmd-1"), {
        commandId: "cmd-1",
        command: "PING",
        propertyId: "farm-1",
        propertyScopeId: "DEADBEEF00000001",
        matrixGatewayId: "matrix-1",
        matrixRuntimeId: "MATRIX_A",
        requestedByUid: "owner-user",
        requestedByRole: "user",
        status: "completed",
        updatedAtMs: 1730000000000,
        expiresAtMs: 1730000060000,
        writer: "gateway_matrix",
        writerKey: "super-secret-key",
      });
      await set(ref(db, "propertyCommandEvents/farm-1/cmd-1/evt-1"), {
        type: "completed",
        status: "completed",
        matrixId: "MATRIX_A",
        createdAtMs: 1730000000000,
        writer: "gateway_matrix",
        writerKey: "super-secret-key",
      });
    });

    await assertSucceeds(get(ref(ownerDb, "propertyTelemetryLatest/farm-1")));
    await assertSucceeds(get(ref(ownerDb, "propertyTelemetryLatest/farm-1/101")));
    await assertSucceeds(get(ref(ownerDb, "propertyTelemetryHistory/farm-1/101")));
    await assertSucceeds(get(ref(ownerDb, "propertyHealthLatest/farm-1")));
    await assertSucceeds(get(ref(ownerDb, "propertyHealthHistory/farm-1/101")));
    await assertSucceeds(get(ref(ownerDb, "propertyEvents/farm-1")));
    await assertSucceeds(get(ref(ownerDb, "propertyEvents/farm-1/20260227/evt-1")));
    await assertSucceeds(get(ref(ownerDb, "propertyCommands/farm-1/cmd-1")));
    await assertSucceeds(get(ref(ownerDb, "propertyCommandEvents/farm-1/cmd-1")));
    await assertFails(get(ref(otherDb, "propertyTelemetryLatest/farm-1")));
    await assertFails(get(ref(otherDb, "propertyTelemetryHistory/farm-1/101")));
    await assertFails(get(ref(otherDb, "propertyEvents/farm-1")));
    await assertFails(get(ref(otherDb, "propertyCommands/farm-1/cmd-1")));
    await assertFails(get(ref(otherDb, "propertyTelemetryLatest/farm-1/101")));
  });

  it("blocks authenticated users from writing operational uplink paths", async () => {
    const authCtx = testEnv.authenticatedContext("owner-user");
    const db = authCtx.database();

    await assertFails(
      set(ref(db, "propertyTelemetryLatest/farm-1/201"), {
        deviceId: "201",
        propertyId: "farm-1",
        propertyScopeId: "DEADBEEF00000001",
        lat: -19.9,
        lon: -44.0,
        receivedAt: 1730000001,
        writer: "app",
      }),
    );
  });
});
