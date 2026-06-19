/**
 * Testes unitários — auto-sync-area-fence
 *
 * Cobrem:
 * - canonicalização e hash de perímetro
 * - detecção de mudança em perimeter e linked_device_ids
 * - bypass para source = herding_operation
 * - formato final de points ([[lat, lon]])
 * - commandId determinístico para área
 * - lógica de espelho active_area_id (mudanças de vínculo)
 */

import { assertEquals, assertNotEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

// ---------------------------------------------------------------------------
// Reimplementação inline das funções puras
// ---------------------------------------------------------------------------

type LatLon = { lat: number; lon: number };

function canonicalizePoints(raw: unknown): LatLon[] {
  if (!Array.isArray(raw)) return [];
  const out: LatLon[] = [];
  for (const p of raw) {
    if (Array.isArray(p) && p.length >= 2) {
      const lat = Number(p[0]);
      const lon = Number(p[1]);
      if (!isFinite(lat) || !isFinite(lon)) continue;
      out.push({ lat, lon });
      continue;
    }
    if (p && typeof p === "object") {
      const lat = Number((p as Record<string, unknown>).lat ?? (p as Record<string, unknown>).latitude);
      const lon = Number(
        (p as Record<string, unknown>).lon ??
          (p as Record<string, unknown>).lng ??
          (p as Record<string, unknown>).longitude,
      );
      if (!isFinite(lat) || !isFinite(lon)) continue;
      out.push({ lat, lon });
    }
  }
  return out;
}

async function hashString(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 16)
    .toUpperCase();
}

async function perimeterHash(points: LatLon[]): Promise<string> {
  const canonical = points
    .map((p) => `${p.lat.toFixed(7)},${p.lon.toFixed(7)}`)
    .join("|");
  return hashString(canonical);
}

async function targetSetHash(ids: string[]): Promise<string> {
  return hashString([...ids].sort().join(","));
}

function deterministicCommandId(
  areaId: string,
  pHash: string,
  tHash: string,
): string {
  return `AUTO_AREA_FENCE:${areaId}:${pHash}:${tHash}`;
}

function normalizeDeviceIdList(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  const ids = (raw as unknown[])
    .map((v) => String(v ?? "").trim())
    .filter((v) => /^[1-9][0-9]*$/.test(v));
  return [...new Set(ids)].sort();
}

function pointsForFirmware(points: LatLon[]): number[][] {
  return points.map((p) => [p.lat, p.lon]);
}

// ---------------------------------------------------------------------------
// Helpers de simulação do handler
// ---------------------------------------------------------------------------

type HandlerInput = {
  type: string;
  record: Record<string, unknown>;
  old_record: Record<string, unknown>;
};

async function simulateHandlerDecision(input: HandlerInput): Promise<{
  skip: boolean;
  reason: string;
  perimeterChanged: boolean;
  devicesChanged: boolean;
}> {
  const source = String(input.record.source ?? "").trim();
  if (source === "herding_operation") {
    return { skip: true, reason: "bypass_herding_source", perimeterChanged: false, devicesChanged: false };
  }

  const newPerimeter = canonicalizePoints(input.record.perimeter);
  const oldPerimeter = canonicalizePoints(input.old_record.perimeter);
  if (newPerimeter.length < 3) {
    return { skip: true, reason: "insufficient_perimeter_points", perimeterChanged: false, devicesChanged: false };
  }

  const [newPH, oldPH] = await Promise.all([perimeterHash(newPerimeter), perimeterHash(oldPerimeter)]);
  const newLinked = normalizeDeviceIdList(input.record.linked_device_ids);
  const oldLinked = normalizeDeviceIdList(input.old_record.linked_device_ids);

  const perimeterChanged = newPH !== oldPH;
  const devicesChanged = newLinked.sort().join(",") !== oldLinked.sort().join(",");

  if (input.type === "UPDATE" && !perimeterChanged && !devicesChanged) {
    return { skip: true, reason: "no_relevant_change", perimeterChanged, devicesChanged };
  }

  return { skip: false, reason: "", perimeterChanged, devicesChanged };
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const PERIMETER_A = [
  { lat: -16.1, lon: -49.1 },
  { lat: -16.2, lon: -49.2 },
  { lat: -16.3, lon: -49.3 },
];

const PERIMETER_B = [
  { lat: -16.1, lon: -49.1 },
  { lat: -16.2, lon: -49.2 },
  { lat: -16.9, lon: -49.9 },
];

// ---------------------------------------------------------------------------
// Testes
// ---------------------------------------------------------------------------

Deno.test("bypass — source herding_operation pula a propagação", async () => {
  const result = await simulateHandlerDecision({
    type: "UPDATE",
    record: { id: "area-1", property_id: "prop-1", perimeter: PERIMETER_A, source: "herding_operation" },
    old_record: { perimeter: PERIMETER_B },
  });
  assertEquals(result.skip, true);
  assertEquals(result.reason, "bypass_herding_source");
});

Deno.test("bypass — source vazio NÃO pula", async () => {
  const result = await simulateHandlerDecision({
    type: "UPDATE",
    record: { id: "area-1", property_id: "prop-1", perimeter: PERIMETER_A, source: "" },
    old_record: { perimeter: PERIMETER_B },
  });
  assertEquals(result.skip, false);
});

Deno.test("bypass — perimeter insuficiente (< 3 pontos)", async () => {
  const result = await simulateHandlerDecision({
    type: "UPDATE",
    record: {
      id: "area-1",
      property_id: "prop-1",
      perimeter: [{ lat: -16.1, lon: -49.1 }, { lat: -16.2, lon: -49.2 }],
    },
    old_record: { perimeter: PERIMETER_A },
  });
  assertEquals(result.skip, true);
  assertEquals(result.reason, "insufficient_perimeter_points");
});

Deno.test("detecção — perimeter mudou → não skipar", async () => {
  const result = await simulateHandlerDecision({
    type: "UPDATE",
    record: { id: "area-1", property_id: "prop-1", perimeter: PERIMETER_B, linked_device_ids: ["1"] },
    old_record: { perimeter: PERIMETER_A, linked_device_ids: ["1"] },
  });
  assertEquals(result.skip, false);
  assertEquals(result.perimeterChanged, true);
  assertEquals(result.devicesChanged, false);
});

Deno.test("detecção — linked_device_ids mudou → não skipar", async () => {
  const result = await simulateHandlerDecision({
    type: "UPDATE",
    record: { id: "area-1", property_id: "prop-1", perimeter: PERIMETER_A, linked_device_ids: ["1", "2"] },
    old_record: { perimeter: PERIMETER_A, linked_device_ids: ["1"] },
  });
  assertEquals(result.skip, false);
  assertEquals(result.perimeterChanged, false);
  assertEquals(result.devicesChanged, true);
});

Deno.test("detecção — nada mudou → skipar (UPDATE)", async () => {
  const result = await simulateHandlerDecision({
    type: "UPDATE",
    record: { id: "area-1", property_id: "prop-1", perimeter: PERIMETER_A, linked_device_ids: ["1"] },
    old_record: { perimeter: PERIMETER_A, linked_device_ids: ["1"] },
  });
  assertEquals(result.skip, true);
  assertEquals(result.reason, "no_relevant_change");
});

Deno.test("INSERT — sempre processa mesmo sem mudança detectada", async () => {
  const result = await simulateHandlerDecision({
    type: "INSERT",
    record: { id: "area-1", property_id: "prop-1", perimeter: PERIMETER_A, linked_device_ids: ["1"] },
    old_record: { perimeter: PERIMETER_A, linked_device_ids: ["1"] },
  });
  assertEquals(result.skip, false);
});

Deno.test("normalizeDeviceIdList — filtra IDs inválidos e ordena", () => {
  const result = normalizeDeviceIdList(["3", "0", "1", "abc", null, "2"]);
  assertEquals(result, ["1", "2", "3"]); // 0 e não-numéricos excluídos
});

Deno.test("normalizeDeviceIdList — deduplica", () => {
  const result = normalizeDeviceIdList(["1", "1", "2"]);
  assertEquals(result, ["1", "2"]);
});

Deno.test("deterministicCommandId para área — formato correto", async () => {
  const pHash = await perimeterHash(PERIMETER_A);
  const tHash = await targetSetHash(["1", "2"]);
  const id = deterministicCommandId("area-xyz", pHash, tHash);
  assertEquals(id.startsWith("AUTO_AREA_FENCE:area-xyz:"), true);
  assertEquals(id.split(":").length, 4);
});

Deno.test("deterministicCommandId para área — idempotente", async () => {
  const pHash = await perimeterHash(PERIMETER_A);
  const tHash = await targetSetHash(["1"]);
  const id1 = deterministicCommandId("area-abc", pHash, tHash);
  const id2 = deterministicCommandId("area-abc", pHash, tHash);
  assertEquals(id1, id2);
});

Deno.test("deterministicCommandId para área — difere quando perimeter muda", async () => {
  const pHashA = await perimeterHash(PERIMETER_A);
  const pHashB = await perimeterHash(PERIMETER_B);
  const tHash = await targetSetHash(["1"]);
  const id1 = deterministicCommandId("area-abc", pHashA, tHash);
  const id2 = deterministicCommandId("area-abc", pHashB, tHash);
  assertNotEquals(id1, id2);
});

Deno.test("pointsForFirmware — formato [[lat, lon]] para área", () => {
  const result = pointsForFirmware(PERIMETER_A);
  assertEquals(result[0], [-16.1, -49.1]);
  for (const p of result) {
    assertEquals(Array.isArray(p), true);
    assertEquals(p.length, 2);
  }
});

Deno.test("active_area_id mirror — remoção de collar detectada", () => {
  const oldLinked = ["1", "2", "3"];
  const newLinked = ["1", "3"];
  const removed = oldLinked.filter((id) => !newLinked.includes(id));
  assertEquals(removed, ["2"]);
});

Deno.test("active_area_id mirror — adição de collar detectada", () => {
  const oldLinked = ["1"];
  const newLinked = ["1", "2"];
  const added = newLinked.filter((id) => !oldLinked.includes(id));
  assertEquals(added, ["2"]);
});

Deno.test("active_area_id mirror — sem linked_device_ids → lista vazia", () => {
  const result = normalizeDeviceIdList(undefined);
  assertEquals(result, []);
});
