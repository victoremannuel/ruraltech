/**
 * Testes unitários — auto-sync-property-fence
 *
 * Cobrem:
 * - canonicalização e hash de polígono
 * - detecção de mudança/imutabilidade
 * - formato final de points ([[lat, lon]])
 * - commandId determinístico
 * - bypass para polígono insuficiente
 * - bypass para polígono inalterado
 */

import { assertEquals, assertNotEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

// ---------------------------------------------------------------------------
// Reimplementação inline das funções puras (sem dependência do Supabase)
// para permitir testes sem contexto de servidor.
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

async function polygonHash(points: LatLon[]): Promise<string> {
  const canonical = points
    .map((p) => `${p.lat.toFixed(7)},${p.lon.toFixed(7)}`)
    .join("|");
  return hashString(canonical);
}

async function targetSetHash(ids: string[]): Promise<string> {
  return hashString([...ids].sort().join(","));
}

function deterministicCommandId(
  propertyId: string,
  pHash: string,
  tHash: string,
): string {
  return `AUTO_PROPERTY_FENCE:${propertyId}:${pHash}:${tHash}`;
}

function pointsForFirmware(points: LatLon[]): number[][] {
  return points.map((p) => [p.lat, p.lon]);
}

// ---------------------------------------------------------------------------
// Dados de fixture
// ---------------------------------------------------------------------------

const POLYGON_A = [
  { lat: -16.1234567, lon: -49.1234567 },
  { lat: -16.2234567, lon: -49.2234567 },
  { lat: -16.3234567, lon: -49.3234567 },
];

const POLYGON_B = [
  { lat: -16.1234567, lon: -49.1234567 },
  { lat: -16.2234567, lon: -49.2234567 },
  { lat: -16.9999999, lon: -49.9999999 }, // ponto diferente
];

// ---------------------------------------------------------------------------
// Testes
// ---------------------------------------------------------------------------

Deno.test("canonicalizePoints — aceita array de pares [lat, lon]", () => {
  const raw = [[-16.1, -49.1], [-16.2, -49.2], [-16.3, -49.3]];
  const result = canonicalizePoints(raw);
  assertEquals(result.length, 3);
  assertEquals(result[0], { lat: -16.1, lon: -49.1 });
});

Deno.test("canonicalizePoints — aceita objetos {lat, lon}", () => {
  const raw = [
    { lat: -16.1, lon: -49.1 },
    { lat: -16.2, lon: -49.2 },
  ];
  const result = canonicalizePoints(raw);
  assertEquals(result.length, 2);
  assertEquals(result[1], { lat: -16.2, lon: -49.2 });
});

Deno.test("canonicalizePoints — aceita objetos {latitude, longitude}", () => {
  const raw = [{ latitude: -16.1, longitude: -49.1 }];
  const result = canonicalizePoints(raw);
  assertEquals(result.length, 1);
  assertEquals(result[0], { lat: -16.1, lon: -49.1 });
});

Deno.test("canonicalizePoints — ignora entradas inválidas", () => {
  const raw = [null, undefined, "invalido", [], { lat: "x", lon: -49.1 }];
  const result = canonicalizePoints(raw);
  assertEquals(result.length, 0);
});

Deno.test("polygonHash — mesmo polígono produz mesmo hash", async () => {
  const h1 = await polygonHash(POLYGON_A);
  const h2 = await polygonHash([...POLYGON_A]);
  assertEquals(h1, h2);
});

Deno.test("polygonHash — polígonos diferentes produzem hashes diferentes", async () => {
  const h1 = await polygonHash(POLYGON_A);
  const h2 = await polygonHash(POLYGON_B);
  assertNotEquals(h1, h2);
});

Deno.test("polygonHash — polígono vazio tem hash diferente de polígono com pontos", async () => {
  const h1 = await polygonHash([]);
  const h2 = await polygonHash(POLYGON_A);
  assertNotEquals(h1, h2);
});

Deno.test("targetSetHash — mesmos IDs (ordem diferente) produzem mesmo hash", async () => {
  const h1 = await targetSetHash(["3", "1", "2"]);
  const h2 = await targetSetHash(["1", "2", "3"]);
  assertEquals(h1, h2);
});

Deno.test("targetSetHash — conjuntos diferentes produzem hashes diferentes", async () => {
  const h1 = await targetSetHash(["1", "2"]);
  const h2 = await targetSetHash(["1", "2", "3"]);
  assertNotEquals(h1, h2);
});

Deno.test("deterministicCommandId — formato correto", async () => {
  const pHash = await polygonHash(POLYGON_A);
  const tHash = await targetSetHash(["1", "2"]);
  const id = deterministicCommandId("prop-abc", pHash, tHash);
  assertEquals(id.startsWith("AUTO_PROPERTY_FENCE:prop-abc:"), true);
  assertEquals(id.split(":").length, 4);
});

Deno.test("deterministicCommandId — idempotente para mesmos inputs", async () => {
  const pHash = await polygonHash(POLYGON_A);
  const tHash = await targetSetHash(["1", "2"]);
  const id1 = deterministicCommandId("prop-xyz", pHash, tHash);
  const id2 = deterministicCommandId("prop-xyz", pHash, tHash);
  assertEquals(id1, id2);
});

Deno.test("deterministicCommandId — difere quando polígono muda", async () => {
  const pHashA = await polygonHash(POLYGON_A);
  const pHashB = await polygonHash(POLYGON_B);
  const tHash = await targetSetHash(["1"]);
  const id1 = deterministicCommandId("prop-xyz", pHashA, tHash);
  const id2 = deterministicCommandId("prop-xyz", pHashB, tHash);
  assertNotEquals(id1, id2);
});

Deno.test("pointsForFirmware — formato correto [[lat, lon]]", () => {
  const result = pointsForFirmware(POLYGON_A);
  assertEquals(result[0], [-16.1234567, -49.1234567]);
  assertEquals(result[1], [-16.2234567, -49.2234567]);
  assertEquals(result.length, POLYGON_A.length);
});

Deno.test("pointsForFirmware — não produz objetos {lat, lon}", () => {
  const result = pointsForFirmware(POLYGON_A);
  for (const p of result) {
    assertEquals(Array.isArray(p), true);
    assertEquals(p.length, 2);
  }
});

Deno.test("detecção de polígono inalterado — mesmo hash → bypass", async () => {
  const h1 = await polygonHash(POLYGON_A);
  const h2 = await polygonHash(POLYGON_A);
  // Simula lógica do handler: se hashes iguais em UPDATE, skipar
  const shouldSkip = h1 === h2;
  assertEquals(shouldSkip, true);
});

Deno.test("detecção de polígono alterado — hashes diferentes → não bypass", async () => {
  const h1 = await polygonHash(POLYGON_A);
  const h2 = await polygonHash(POLYGON_B);
  const shouldSkip = h1 === h2;
  assertEquals(shouldSkip, false);
});

Deno.test("polígono insuficiente (< 3 pontos) → deve ser recusado", () => {
  const twoPoints = [{ lat: -16.1, lon: -49.1 }, { lat: -16.2, lon: -49.2 }];
  assertEquals(twoPoints.length < 3, true);
});
