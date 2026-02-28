import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { after, before, beforeEach, describe, it } from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import { ref, set } from "firebase/database";

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
  });
});

after(async () => {
  await testEnv.cleanup();
});

describe("Realtime Database rules", () => {
  it("allows unauthenticated matrix writer with valid key", async () => {
    const unauthCtx = testEnv.unauthenticatedContext();
    const db = unauthCtx.database();

    const payload = {
      deviceId: "101",
      lat: -20.1234,
      lon: -43.9876,
      receivedAt: 1730000000,
      writer: "gateway_matrix",
      matrixId: "MATRIX_A",
      writerKey: "super-secret-key",
    };

    await assertSucceeds(set(ref(db, "telemetryLatest/101"), payload));
    await assertSucceeds(
      set(ref(db, "telemetryHistory/101/20260227/1730000000000"), payload),
    );
  });

  it("rejects unauthenticated matrix writer with invalid key", async () => {
    const unauthCtx = testEnv.unauthenticatedContext();
    const db = unauthCtx.database();

    const invalidPayload = {
      deviceId: "101",
      lat: -20.1234,
      lon: -43.9876,
      receivedAt: 1730000000,
      writer: "gateway_matrix",
      matrixId: "MATRIX_A",
      writerKey: "wrong-key",
    };

    await assertFails(set(ref(db, "telemetryLatest/101"), invalidPayload));
  });

  it("rejects matrix payload with invalid coordinates", async () => {
    const unauthCtx = testEnv.unauthenticatedContext();
    const db = unauthCtx.database();

    await assertFails(
      set(ref(db, "telemetryLatest/101"), {
        deviceId: "101",
        lat: -200,
        lon: -43.9876,
        receivedAt: 1730000000,
        writer: "gateway_matrix",
        matrixId: "MATRIX_A",
        writerKey: "super-secret-key",
      }),
    );
  });

  it("rejects unauthenticated writer with unknown matrixId", async () => {
    const unauthCtx = testEnv.unauthenticatedContext();
    const db = unauthCtx.database();

    await assertFails(
      set(ref(db, "telemetryLatest/101"), {
        deviceId: "101",
        lat: -20.1234,
        lon: -43.9876,
        receivedAt: 1730000000,
        writer: "gateway_matrix",
        matrixId: "UNKNOWN_MATRIX",
        writerKey: "super-secret-key",
      }),
    );
  });

  it("allows authenticated user to write telemetry", async () => {
    const authCtx = testEnv.authenticatedContext("adm-user");
    const db = authCtx.database();

    await assertSucceeds(
      set(ref(db, "telemetryLatest/201"), {
        deviceId: "201",
        lat: -19.9,
        lon: -44.0,
        receivedAt: 1730000001,
        writer: "app",
      }),
    );
  });
});
