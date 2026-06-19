import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { after, before, beforeEach, describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  deleteDoc,
  doc,
  getDoc,
  setDoc,
} from "firebase/firestore";

const projectId = "demo-ruraltech";
const rules = readFileSync(resolve(process.cwd(), "../firestore.rules"), "utf8");

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { rules },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/adm-user"), {
      uid: "adm-user",
      email: "adm@ruraltech.test",
      role: "adm",
    });
    await setDoc(doc(db, "users/owner-user"), {
      uid: "owner-user",
      email: "owner@ruraltech.test",
      role: "user",
    });
    await setDoc(doc(db, "users/other-user"), {
      uid: "other-user",
      email: "other@ruraltech.test",
      role: "user",
    });
    await setDoc(doc(db, "users/linked-user"), {
      uid: "linked-user",
      email: "linked@ruraltech.test",
      role: "user",
    });

    await setDoc(doc(db, "ruralProperties/farm-1"), {
      name: "Farm 1",
      propertyScopeId: "DEADBEEF00000001",
      createdByUid: doc(db, "users/owner-user"),
      userUids: [
        doc(db, "users/owner-user"),
        doc(db, "users/adm-user"),
        doc(db, "users/linked-user"),
      ],
    });

    await setDoc(doc(db, "gateways/matrix-1"), {
      propertyId: "farm-1",
      propertyScopeId: "DEADBEEF00000001",
      is_matrix: true,
      supportsScopedLora: true,
      bindingReady: true,
      runtimeStatus: {
        propertyScopeId: "DEADBEEF00000001",
        supportsScopedLora: true,
        bindingReady: true,
      },
      userUids: [
        doc(db, "users/owner-user"),
        doc(db, "users/adm-user"),
        doc(db, "users/linked-user"),
      ],
    });

    await setDoc(doc(db, "collars/101"), {
      ownerUid: doc(db, "users/owner-user"),
      deviceId: "101",
      propertyId: "farm-1",
      propertyScopeId: "DEADBEEF00000001",
      name: "Coleira 101",
      status: "active",
      supportsScopedLora: true,
      bindingReady: true,
      runtimeStatus: {
        propertyScopeId: "DEADBEEF00000001",
        supportsScopedLora: true,
        bindingReady: true,
      },
    });
  });
});

after(async () => {
  await testEnv.cleanup();
});

describe("Firestore rules", () => {
  it("blocks collar read for unrelated user", async () => {
    const otherCtx = testEnv.authenticatedContext("other-user");
    const ownerCtx = testEnv.authenticatedContext("owner-user");

    const otherDb = otherCtx.firestore();
    const ownerDb = ownerCtx.firestore();

    await assertFails(getDoc(doc(otherDb, "collars/101")));
    await assertSucceeds(getDoc(doc(ownerDb, "collars/101")));
  });

  it("allows admin to delete collar", async () => {
    const admCtx = testEnv.authenticatedContext("adm-user");
    const admDb = admCtx.firestore();

    await assertSucceeds(deleteDoc(doc(admDb, "collars/101")));
  });

  it("allows owner to save fence for owned collar and blocks unrelated user", async () => {
    const ownerCtx = testEnv.authenticatedContext("owner-user");
    const otherCtx = testEnv.authenticatedContext("other-user");
    const ownerDb = ownerCtx.firestore();
    const otherDb = otherCtx.firestore();

    const ownerPayload = {
      ownerUid: doc(ownerDb, "users/owner-user"),
      deviceId: "101",
      points: [
        { lat: -20.1, lon: -43.8 },
        { lat: -20.2, lon: -43.9 },
        { lat: -20.3, lon: -43.7 },
      ],
    };

    const otherPayload = {
      ownerUid: doc(otherDb, "users/other-user"),
      deviceId: "101",
      points: [
        { lat: -20.1, lon: -43.8 },
        { lat: -20.2, lon: -43.9 },
        { lat: -20.3, lon: -43.7 },
      ],
    };

    await assertSucceeds(setDoc(doc(ownerDb, "fences/101"), ownerPayload));
    await assertFails(setDoc(doc(otherDb, "fences/101"), otherPayload));

    const snap = await getDoc(doc(ownerDb, "fences/101"));
    assert.equal(snap.exists(), true);
  });

  it("allows linked user to read rural property and blocks unrelated user", async () => {
    const linkedCtx = testEnv.authenticatedContext("linked-user");
    const otherCtx = testEnv.authenticatedContext("other-user");
    const linkedDb = linkedCtx.firestore();
    const otherDb = otherCtx.firestore();

    await assertSucceeds(getDoc(doc(linkedDb, "ruralProperties/farm-1")));
    await assertFails(getDoc(doc(otherDb, "ruralProperties/farm-1")));
  });

  it("allows owner to create herding operation for accessible property and linked user to read it", async () => {
    const ownerCtx = testEnv.authenticatedContext("owner-user");
    const linkedCtx = testEnv.authenticatedContext("linked-user");
    const otherCtx = testEnv.authenticatedContext("other-user");
    const ownerDb = ownerCtx.firestore();
    const linkedDb = linkedCtx.firestore();
    const otherDb = otherCtx.firestore();

    const payload = {
      ownerUid: doc(ownerDb, "users/owner-user"),
      requestedByUid: doc(ownerDb, "users/owner-user"),
      requestedByRole: "user",
      propertyId: "farm-1",
      matrixGatewayId: "matrix-1",
      status: "submitted",
      selectedDeviceIds: ["101"],
      notifyUserIds: ["owner-user", "linked-user"],
      targetPolygon: [
        { lat: -20.1, lon: -43.8 },
        { lat: -20.2, lon: -43.9 },
        { lat: -20.3, lon: -43.7 },
      ],
      deviceStatuses: {
        "101": {
          status: "pending",
          retryCount: 0,
          updatedAtMs: 1730000000000,
        },
      },
    };

    await assertSucceeds(
      setDoc(doc(ownerDb, "herdingOperations/op-1"), payload),
    );
    await assertSucceeds(getDoc(doc(linkedDb, "herdingOperations/op-1")));
    await assertFails(
      setDoc(doc(otherDb, "herdingOperations/op-2"), {
        ...payload,
        ownerUid: doc(otherDb, "users/other-user"),
        requestedByUid: doc(otherDb, "users/other-user"),
        notifyUserIds: ["other-user"],
      }),
    );
  });

  it("blocks herding operation create when property access is invalid even if the collar is owned", async () => {
    const ownerCtx = testEnv.authenticatedContext("owner-user");
    const ownerDb = ownerCtx.firestore();

    await assertFails(
      setDoc(doc(ownerDb, "herdingOperations/op-fallback"), {
        ownerUid: doc(ownerDb, "users/owner-user"),
        requestedByUid: doc(ownerDb, "users/owner-user"),
        requestedByRole: "user",
        propertyId: "missing-property-id",
        matrixGatewayId: "matrix-1",
        status: "submitted",
        selectedDeviceIds: ["101"],
        notifyUserIds: ["owner-user"],
        targetPolygon: [
          { lat: -20.1, lon: -43.8 },
          { lat: -20.2, lon: -43.9 },
          { lat: -20.3, lon: -43.7 },
        ],
      }),
    );
  });

  it("allows owner to create loraCommands with matching property scope and linked user to read them", async () => {
    const ownerCtx = testEnv.authenticatedContext("owner-user");
    const linkedCtx = testEnv.authenticatedContext("linked-user");
    const ownerDb = ownerCtx.firestore();
    const linkedDb = linkedCtx.firestore();

    await assertSucceeds(
      setDoc(doc(ownerDb, "loraCommands/cmd-1"), {
        commandId: "cmd-1",
        command: "SET_FENCE",
        propertyId: "farm-1",
        propertyScopeId: "DEADBEEF00000001",
        matrixGatewayId: "matrix-1",
        targetDeviceIds: ["101"],
        targetGatewayIds: [],
        payload: {
          points: [
            { lat: -20.1, lon: -43.8 },
            { lat: -20.2, lon: -43.9 },
            { lat: -20.3, lon: -43.7 },
          ],
        },
        requestedByUid: doc(ownerDb, "users/owner-user"),
        requestedByRole: "user",
      }),
    );
    await assertSucceeds(getDoc(doc(linkedDb, "loraCommands/cmd-1")));
  });

  it("blocks loraCommands when the property scope id does not match", async () => {
    const ownerCtx = testEnv.authenticatedContext("owner-user");
    const ownerDb = ownerCtx.firestore();

    await assertFails(
      setDoc(doc(ownerDb, "loraCommands/cmd-bad-scope"), {
        commandId: "cmd-bad-scope",
        command: "SET_FENCE",
        propertyId: "farm-1",
        propertyScopeId: "BADSCOPE00000000",
        matrixGatewayId: "matrix-1",
        targetDeviceIds: ["101"],
        targetGatewayIds: [],
        payload: {
          points: [
            { lat: -20.1, lon: -43.8 },
            { lat: -20.2, lon: -43.9 },
            { lat: -20.3, lon: -43.7 },
          ],
        },
        requestedByUid: doc(ownerDb, "users/owner-user"),
        requestedByRole: "user",
      }),
    );
  });
});
