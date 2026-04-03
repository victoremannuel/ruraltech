import {
  createRemoteJWKSet,
  importPKCS8,
  jwtVerify,
  SignJWT,
} from "npm:jose@5.9.6";

const FIREBASE_JWKS = createRemoteJWKSet(
  new URL(
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
  ),
);

const FIREBASE_SCOPES = [
  "https://www.googleapis.com/auth/firebase.database",
  "https://www.googleapis.com/auth/datastore",
  "https://www.googleapis.com/auth/userinfo.email",
];

type JsonValue =
  | null
  | boolean
  | number
  | string
  | JsonValue[]
  | { [key: string]: JsonValue };

type FirestoreValue = Record<string, unknown>;
type FirestoreDocument = {
  name?: string;
  fields?: Record<string, FirestoreValue>;
};

type ServiceAccountConfig = {
  client_email: string;
  private_key: string;
  token_uri?: string;
};

type AccessTokenCache = {
  token: string;
  expiresAtMs: number;
};

let accessTokenCache: AccessTokenCache | null = null;

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function corsHeaders() {
  return {
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "POST,OPTIONS",
    "access-control-allow-headers":
      "authorization,apikey,content-type,x-client-info",
    "content-type": "application/json; charset=utf-8",
  };
}

export function jsonResponse(
  status: number,
  body: Record<string, unknown>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders(),
  });
}

export function normalizeText(value: unknown): string {
  if (value == null) return "";
  return String(value).trim();
}

export function normalizeRole(value: unknown): string {
  const normalized = normalizeText(value).toLowerCase();
  return normalized || "user";
}

export function normalizeId(value: unknown): string {
  if (value == null) return "";
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (!trimmed) return "";
    if (!trimmed.includes("/")) return trimmed;
    const parts = trimmed.split("/").filter(Boolean);
    return parts.length ? parts[parts.length - 1] : trimmed;
  }
  if (typeof value === "object") {
    const candidate = value as Record<string, unknown>;
    if (typeof candidate.id === "string" && candidate.id.trim()) {
      return candidate.id.trim();
    }
    if (typeof candidate.path === "string" && candidate.path.trim()) {
      return normalizeId(candidate.path);
    }
  }
  return "";
}

export function normalizeIdList(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return [...new Set(raw.map((entry) => normalizeId(entry)).filter(Boolean))].sort();
}

export function normalizeDeviceIdList(raw: unknown): string[] {
  return normalizeIdList(raw).filter((deviceId) => /^[1-9][0-9]*$/.test(deviceId));
}

export function sanitizeRtdbKey(value: string): string {
  return normalizeText(value).replace(/[.#$\[\]/]/g, "_");
}

export function normalizeScopeId(value: unknown): string {
  return normalizeText(value).replace(/[^0-9a-fA-F]/g, "").toUpperCase();
}

export async function computePropertyScopeId(propertyId: string): Promise<string> {
  const normalized = normalizeId(propertyId).toLowerCase();
  if (!normalized) return "";
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(normalized),
  );
  const bytes = new Uint8Array(digest);
  return [...bytes]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 16)
    .toUpperCase();
}

function parseServiceAccountJson(): ServiceAccountConfig {
  const rawJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON") ??
    Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON") ??
    "";
  const base64Json = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_BASE64") ??
    Deno.env.get("GOOGLE_SERVICE_ACCOUNT_BASE64") ??
    "";
  const payload = rawJson || (base64Json
    ? new TextDecoder().decode(Uint8Array.from(atob(base64Json), (char) => char.charCodeAt(0)))
    : "");
  if (!payload) {
    throw new Error("missing_firebase_service_account");
  }
  const parsed = JSON.parse(payload) as ServiceAccountConfig;
  if (!parsed.client_email || !parsed.private_key) {
    throw new Error("invalid_firebase_service_account");
  }
  return parsed;
}

function firebaseProjectId(): string {
  const projectId = normalizeText(
    Deno.env.get("FIREBASE_PROJECT_ID") ?? Deno.env.get("FIREBASE_AUTH_PROJECT_ID"),
  );
  if (!projectId) throw new Error("missing_firebase_project_id");
  return projectId;
}

function firestoreBaseUrl(): string {
  const projectId = firebaseProjectId();
  return `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
}

function rtdbBaseUrl(): string {
  const url = normalizeText(Deno.env.get("FIREBASE_RTDB_URL"));
  if (!url) throw new Error("missing_firebase_rtdb_url");
  return url.replace(/\/+$/, "");
}

async function getGoogleAccessToken(): Promise<string> {
  const nowMs = Date.now();
  if (accessTokenCache && accessTokenCache.expiresAtMs - 60_000 > nowMs) {
    return accessTokenCache.token;
  }

  const account = parseServiceAccountJson();
  const tokenUri = account.token_uri || "https://oauth2.googleapis.com/token";
  const privateKey = await importPKCS8(account.private_key, "RS256");
  const issuedAt = Math.floor(nowMs / 1000);
  const assertion = await new SignJWT({
    scope: FIREBASE_SCOPES.join(" "),
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(account.client_email)
    .setSubject(account.client_email)
    .setAudience(tokenUri)
    .setIssuedAt(issuedAt)
    .setExpirationTime(issuedAt + 3600)
    .sign(privateKey);

  const response = await fetch(tokenUri, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!response.ok) {
    throw new Error(`google_token_exchange_failed:${response.status}`);
  }
  const json = await response.json() as {
    access_token?: string;
    expires_in?: number;
  };
  const accessToken = normalizeText(json.access_token);
  if (!accessToken) throw new Error("missing_google_access_token");
  accessTokenCache = {
    token: accessToken,
    expiresAtMs: nowMs + Math.max(300, Number(json.expires_in ?? 3600)) * 1000,
  };
  return accessToken;
}

async function authorizedFetch(
  url: string,
  init: RequestInit = {},
): Promise<Response> {
  const maxAttempts = 4;
  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    const accessToken = await getGoogleAccessToken();
    const headers = new Headers(init.headers ?? {});
    headers.set("authorization", `Bearer ${accessToken}`);
    if (init.body != null && !headers.has("content-type")) {
      headers.set("content-type", "application/json");
    }
    const response = await fetch(url, {
      ...init,
      headers,
    });
    if (response.ok) {
      return response;
    }

    if (response.status === 401 && attempt < maxAttempts - 1) {
      accessTokenCache = null;
      await sleep(200 * (attempt + 1));
      continue;
    }

    const retryAfterHeader = Number(response.headers.get("retry-after") ?? "");
    const retryableStatus = response.status === 429 || response.status >= 500;
    if (retryableStatus && attempt < maxAttempts - 1) {
      const retryAfterMs = Number.isFinite(retryAfterHeader) &&
          retryAfterHeader > 0
        ? retryAfterHeader * 1000
        : 400 * (2 ** attempt) + Math.floor(Math.random() * 250);
      await sleep(Math.min(retryAfterMs, 8_000));
      continue;
    }

    return response;
  }

  throw new Error("authorized_fetch_unreachable");
}

async function describeRemoteError(response: Response): Promise<string> {
  try {
    const json = await response.json() as {
      error?: {
        status?: string;
        message?: string;
      };
    };
    const status = normalizeText(json.error?.status);
    const message = normalizeText(json.error?.message).replace(/\s+/g, " ");
    return [status, message].filter(Boolean).join(":");
  } catch (_) {
    try {
      return normalizeText(await response.text()).replace(/\s+/g, " ");
    } catch (_) {
      return "";
    }
  }
}

function fromFirestoreValue(value: FirestoreValue | null | undefined): unknown {
  if (!value || typeof value !== "object") return null;
  if ("nullValue" in value) return null;
  if ("stringValue" in value) return value.stringValue ?? "";
  if ("booleanValue" in value) return Boolean(value.booleanValue);
  if ("integerValue" in value) return Number(value.integerValue ?? 0);
  if ("doubleValue" in value) return Number(value.doubleValue ?? 0);
  if ("timestampValue" in value) return String(value.timestampValue ?? "");
  if ("referenceValue" in value) return String(value.referenceValue ?? "");
  if ("arrayValue" in value) {
    const values = (value.arrayValue as { values?: FirestoreValue[] }).values ?? [];
    return values.map((entry) => fromFirestoreValue(entry));
  }
  if ("mapValue" in value) {
    const fields = (value.mapValue as { fields?: Record<string, FirestoreValue> }).fields ?? {};
    const out: Record<string, unknown> = {};
    for (const [key, nested] of Object.entries(fields)) {
      out[key] = fromFirestoreValue(nested);
    }
    return out;
  }
  return null;
}

function toFirestoreValue(value: unknown): FirestoreValue {
  if (value == null) return { nullValue: null };
  if (typeof value === "string") return { stringValue: value };
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number") {
    if (Number.isInteger(value)) return { integerValue: String(value) };
    return { doubleValue: value };
  }
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map((entry) => toFirestoreValue(entry)) } };
  }
  const mapValue: Record<string, FirestoreValue> = {};
  for (const [key, nested] of Object.entries(value as Record<string, unknown>)) {
    mapValue[key] = toFirestoreValue(nested);
  }
  return { mapValue: { fields: mapValue } };
}

function documentToObject(doc: FirestoreDocument | null): Record<string, unknown> | null {
  if (!doc) return null;
  const fields = doc.fields ?? {};
  const out = fromFirestoreValue({ mapValue: { fields } }) as Record<string, unknown>;
  const name = normalizeText(doc.name);
  if (name) {
    out.__path = name.split("/documents/")[1] ?? "";
    out.id = normalizeId(name);
  }
  return out;
}

export async function getFirestoreDocument(
  path: string,
): Promise<Record<string, unknown> | null> {
  const normalizedPath = normalizeText(path).replace(/^\/+/, "");
  if (!normalizedPath) return null;
  const response = await authorizedFetch(
    `${firestoreBaseUrl()}/${normalizedPath}`,
    { method: "GET" },
  );
  if (response.status === 404) return null;
  if (!response.ok) {
    const detail = await describeRemoteError(response);
    throw new Error(
      `firestore_get_failed:${normalizedPath}:${response.status}${
        detail ? `:${detail}` : ""
      }`,
    );
  }
  return documentToObject(await response.json() as FirestoreDocument);
}

export async function patchFirestoreDocument(
  path: string,
  patch: Record<string, unknown>,
): Promise<void> {
  const normalizedPath = normalizeText(path).replace(/^\/+/, "");
  if (!normalizedPath) return;
  const fieldPaths = Object.keys(patch);
  if (!fieldPaths.length) return;

  const url = new URL(`${firestoreBaseUrl()}/${normalizedPath}`);
  for (const fieldPath of fieldPaths) {
    url.searchParams.append("updateMask.fieldPaths", fieldPath);
  }

  const fields: Record<string, FirestoreValue> = {};
  for (const [key, value] of Object.entries(patch)) {
    fields[key] = toFirestoreValue(value);
  }

  const response = await authorizedFetch(url.toString(), {
    method: "PATCH",
    body: JSON.stringify({ fields }),
  });
  if (!response.ok) {
    const detail = await describeRemoteError(response);
    throw new Error(
      `firestore_patch_failed:${normalizedPath}:${response.status}${
        detail ? `:${detail}` : ""
      }`,
    );
  }
}

export async function listFirestoreCollectionDocuments(
  collectionId: string,
  pageSize = 500,
): Promise<Record<string, unknown>[]> {
  const normalizedCollection = normalizeText(collectionId).replace(/^\/+/, "");
  if (!normalizedCollection) return [];
  const out: Record<string, unknown>[] = [];
  let pageToken = "";
  do {
    const url = new URL(`${firestoreBaseUrl()}/${normalizedCollection}`);
    url.searchParams.set("pageSize", String(pageSize));
    if (pageToken) url.searchParams.set("pageToken", pageToken);
    const response = await authorizedFetch(url.toString(), { method: "GET" });
    if (!response.ok) {
      const detail = await describeRemoteError(response);
      throw new Error(
        `firestore_list_failed:${normalizedCollection}:${response.status}${
          detail ? `:${detail}` : ""
        }`,
      );
    }
    const json = await response.json() as {
      documents?: FirestoreDocument[];
      nextPageToken?: string;
    };
    for (const doc of json.documents ?? []) {
      const parsed = documentToObject(doc);
      if (parsed) out.push(parsed);
    }
    pageToken = normalizeText(json.nextPageToken);
  } while (pageToken);
  return out;
}

export async function getRtdbValue(path: string): Promise<unknown> {
  const normalizedPath = normalizeText(path).replace(/^\/+/, "");
  const response = await authorizedFetch(
    `${rtdbBaseUrl()}/${normalizedPath}.json`,
    { method: "GET" },
  );
  if (!response.ok) {
    throw new Error(`rtdb_get_failed:${normalizedPath}:${response.status}`);
  }
  return await response.json();
}

export async function putRtdbValue(path: string, value: JsonValue): Promise<void> {
  const normalizedPath = normalizeText(path).replace(/^\/+/, "");
  const response = await authorizedFetch(
    `${rtdbBaseUrl()}/${normalizedPath}.json`,
    {
      method: "PUT",
      body: JSON.stringify(value),
    },
  );
  if (!response.ok) {
    throw new Error(`rtdb_put_failed:${normalizedPath}:${response.status}`);
  }
}

export async function patchRtdbRoot(
  patch: Record<string, JsonValue>,
): Promise<void> {
  const response = await authorizedFetch(`${rtdbBaseUrl()}/.json`, {
    method: "PATCH",
    body: JSON.stringify(patch),
  });
  if (!response.ok) {
    throw new Error(`rtdb_patch_failed:${response.status}`);
  }
}

export function matrixRuntimeIdFromGatewayData(
  gatewayId: string,
  gatewayData: Record<string, unknown>,
): string {
  const runtimeStatus = gatewayData.runtimeStatus &&
      typeof gatewayData.runtimeStatus === "object"
    ? gatewayData.runtimeStatus as Record<string, unknown>
    : {};
  const runtimeId = normalizeId(
    gatewayData.rtdbMatrixId ??
      gatewayData.matrixId ??
      runtimeStatus.matrixId ??
      runtimeStatus.rtdbMatrixId ??
      gatewayId,
  );
  return sanitizeRtdbKey(runtimeId);
}

function runtimeStatusMap(
  targetData: Record<string, unknown> | null,
): Record<string, unknown> {
  return targetData?.runtimeStatus && typeof targetData.runtimeStatus === "object"
    ? targetData.runtimeStatus as Record<string, unknown>
    : {};
}

export function resolveEntityScopeId(
  targetData: Record<string, unknown> | null,
): string {
  if (!targetData) return "";
  const runtimeStatus = runtimeStatusMap(targetData);
  return normalizeScopeId(runtimeStatus.propertyScopeId ?? targetData.propertyScopeId);
}

export function entityMatchesProperty(
  targetData: Record<string, unknown> | null,
  propertyId: string,
  propertyScopeId: string,
): boolean {
  if (!targetData) return false;
  const runtimeStatus = runtimeStatusMap(targetData);
  const directPropertyId = normalizeId(
    targetData.propertyId ?? runtimeStatus.propertyId,
  );
  if (directPropertyId) {
    return directPropertyId === propertyId;
  }
  const resolvedScopeId = resolveEntityScopeId(targetData);
  return resolvedScopeId.length > 0 && resolvedScopeId === propertyScopeId;
}

export function isTargetReady(
  targetData: Record<string, unknown> | null,
  expectedScopeId: string,
): boolean {
  if (!targetData) return false;
  const runtimeStatus = runtimeStatusMap(targetData);
  const supportsScopedLora =
    targetData.supportsScopedLora === true ||
    runtimeStatus.supportsScopedLora === true;
  const runtimeScopeId = resolveEntityScopeId(targetData);
  const bindingReady =
    targetData.bindingReady === true ||
    runtimeStatus.bindingReady === true ||
    (supportsScopedLora && runtimeScopeId === expectedScopeId);
  return supportsScopedLora &&
    bindingReady &&
    runtimeScopeId.length > 0 &&
    runtimeScopeId === expectedScopeId;
}

export function userHasPropertyAccess(
  uid: string,
  role: string,
  propertyData: Record<string, unknown> | null,
): boolean {
  if (role === "adm" || role === "admin") return true;
  if (!propertyData) return false;
  if (normalizeId(propertyData.createdByUid) === uid) return true;
  if (normalizeId(propertyData.ownerUid) === uid) return true;
  return normalizeIdList(propertyData.userUids).includes(uid);
}

export function normalizeBusinessRef(
  raw: unknown,
): Record<string, string> | null {
  if (!raw || typeof raw !== "object") return null;
  const value = raw as Record<string, unknown>;
  const type = normalizeText(value.type);
  const id = normalizeId(value.id ?? value.refId ?? value.operationId);
  if (!type || !id) return null;
  return { type, id };
}

export const COMMAND_TTL_MS: Record<string, number> = {
  SET_FENCE: 15 * 60 * 1000,
  SET_HERDING_PLAN: 20 * 60 * 1000,
  SET_PARAMS: 10 * 60 * 1000,
  PING: 6 * 60 * 1000,
};

export const ALLOWED_COMMANDS = new Set(Object.keys(COMMAND_TTL_MS));

export function commandExpiryMs(command: string, createdAtMs: number): number {
  return createdAtMs + (COMMAND_TTL_MS[command] ?? 10 * 60 * 1000);
}

export function extractQueueKey(raw: unknown): string {
  if (typeof raw === "string") return sanitizeRtdbKey(raw);
  if (raw && typeof raw === "object") {
    return sanitizeRtdbKey((raw as Record<string, unknown>).queueKey as string);
  }
  return "";
}

export async function verifyFirebaseBearerToken(
  authorizationHeader: string | null,
): Promise<{ uid: string; token: Record<string, unknown> }> {
  const bearer = normalizeText(authorizationHeader);
  if (!bearer.toLowerCase().startsWith("bearer ")) {
    throw new Error("missing_bearer_token");
  }
  const token = bearer.slice(7).trim();
  if (!token) throw new Error("missing_bearer_token");
  const projectId = firebaseProjectId();
  const verified = await jwtVerify(token, FIREBASE_JWKS, {
    issuer: `https://securetoken.google.com/${projectId}`,
    audience: projectId,
  });
  const uid = normalizeId(verified.payload.user_id ?? verified.payload.sub);
  if (!uid) throw new Error("invalid_firebase_token_uid");
  return {
    uid,
    token: verified.payload as Record<string, unknown>,
  };
}
