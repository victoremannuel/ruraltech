import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.50.2";

export type JsonMap = Record<string, unknown>;

export function corsHeaders() {
  return {
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET,POST,PUT,DELETE,OPTIONS",
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
  const role = normalizeText(value).toLowerCase();
  return role || "user";
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
    const record = value as Record<string, unknown>;
    if (typeof record.id === "string" && record.id.trim()) {
      return record.id.trim();
    }
    if (typeof record.path === "string" && record.path.trim()) {
      return normalizeId(record.path);
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

export function normalizeScopeId(value: unknown): string {
  return normalizeText(value).replace(/[^0-9a-fA-F]/g, "").toUpperCase();
}

export function sanitizeCloudKey(value: string): string {
  return normalizeText(value).replace(/[.#$\[\]/]/g, "_");
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

export function extractQueueKey(raw: unknown): string {
  if (typeof raw === "string") return raw.trim();
  if (raw && typeof raw === "object") {
    const data = raw as Record<string, unknown>;
    return normalizeText(data.queueKey ?? data.queue_key);
  }
  return "";
}

export function normalizeBusinessRef(
  raw: unknown,
): { type: string; id: string } | null {
  if (!raw || typeof raw !== "object") return null;
  const value = raw as Record<string, unknown>;
  const type = normalizeText(value.type);
  const id = normalizeId(value.id ?? value.refId ?? value.operationId);
  if (!type || !id) return null;
  return { type, id };
}

export const COMMAND_TTL_MS: Record<string, number> = {
  SET_FENCE: 30 * 60 * 1000,
  SET_HERDING_PLAN: 20 * 60 * 1000,
  SET_PARAMS: 10 * 60 * 1000,
  PING: 6 * 60 * 1000,
};

export const ALLOWED_COMMANDS = new Set(Object.keys(COMMAND_TTL_MS));

export function commandExpiryMs(command: string, createdAtMs: number): number {
  return createdAtMs + (COMMAND_TTL_MS[command] ?? 10 * 60 * 1000);
}

export function matrixRuntimeIdFromGatewayData(
  gatewayId: string,
  data: JsonMap,
): string {
  const runtimeStatus = data.runtime_status && typeof data.runtime_status === "object"
    ? data.runtime_status as JsonMap
    : data.runtimeStatus && typeof data.runtimeStatus === "object"
    ? data.runtimeStatus as JsonMap
    : {};
  const explicit = normalizeId(
    data.matrix_id ??
      data.matrixId ??
      data.rtdb_matrix_id ??
      data.rtdbMatrixId ??
      runtimeStatus.matrix_id ??
      runtimeStatus.matrixId ??
      runtimeStatus.rtdb_matrix_id ??
      runtimeStatus.rtdbMatrixId,
  );
  return sanitizeCloudKey(explicit || gatewayId);
}

export function resolveEntityScopeId(data: JsonMap): string {
  const runtimeStatus = data.runtime_status && typeof data.runtime_status === "object"
    ? data.runtime_status as JsonMap
    : data.runtimeStatus && typeof data.runtimeStatus === "object"
    ? data.runtimeStatus as JsonMap
    : {};
  return normalizeScopeId(
    data.property_scope_id ??
      data.propertyScopeId ??
      runtimeStatus.property_scope_id ??
      runtimeStatus.propertyScopeId,
  );
}

export function entityMatchesProperty(
  data: JsonMap,
  propertyId: string,
  propertyScopeId: string,
): boolean {
  const directPropertyId = normalizeId(
    data.property_id ?? data.propertyId ??
      (data.runtime_status as JsonMap | undefined)?.property_id ??
      (data.runtime_status as JsonMap | undefined)?.propertyId ??
      (data.runtimeStatus as JsonMap | undefined)?.property_id ??
      (data.runtimeStatus as JsonMap | undefined)?.propertyId,
  );
  if (directPropertyId) return directPropertyId === propertyId;
  return resolveEntityScopeId(data) === propertyScopeId;
}

export function isTargetReady(
  data: JsonMap,
  propertyScopeId: string,
): boolean {
  const runtimeStatus = data.runtime_status && typeof data.runtime_status === "object"
    ? data.runtime_status as JsonMap
    : data.runtimeStatus && typeof data.runtimeStatus === "object"
    ? data.runtimeStatus as JsonMap
    : {};
  const supportsScopedLora = data.supports_scoped_lora === true ||
    data.supportsScopedLora === true ||
    runtimeStatus.supports_scoped_lora === true ||
    runtimeStatus.supportsScopedLora === true;
  const bindingReady = data.binding_ready === true ||
    data.bindingReady === true ||
    runtimeStatus.binding_ready === true ||
    runtimeStatus.bindingReady === true;
  return supportsScopedLora && bindingReady && resolveEntityScopeId(data) === propertyScopeId;
}

export function createAdminClient(): SupabaseClient {
  const url = normalizeText(Deno.env.get("SUPABASE_URL"));
  const serviceRoleKey = normalizeText(Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
  if (!url || !serviceRoleKey) {
    throw new Error("missing_supabase_service_role");
  }
  return createClient(url, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

export async function getJsonBody(request: Request): Promise<JsonMap> {
  try {
    const json = await request.json();
    if (json && typeof json === "object" && !Array.isArray(json)) {
      return json as JsonMap;
    }
  } catch (_) {
    // no-op
  }
  return {};
}

export type AuthContext = {
  authUserId: string;
  legacyUid: string;
  email: string;
  role: string;
};

export async function getAuthContext(
  request: Request,
  admin: SupabaseClient,
): Promise<AuthContext> {
  const authHeader = request.headers.get("authorization") ?? "";
  const token = authHeader.toLowerCase().startsWith("bearer ")
    ? authHeader.slice(7).trim()
    : "";
  if (!token) throw new Error("missing_auth_token");

  const userResult = await admin.auth.getUser(token);
  if (userResult.error || !userResult.data.user) {
    throw new Error("invalid_auth_token");
  }
  const authUser = userResult.data.user;
  const { data: profile, error } = await admin
    .from("profiles")
    .select("legacy_uid, email, role")
    .eq("auth_user_id", authUser.id)
    .maybeSingle();
  if (error) throw new Error(error.message);

  const legacyUid = normalizeId(profile?.legacy_uid ?? authUser.id);
  const role = normalizeRole(profile?.role);
  const email = normalizeText(profile?.email ?? authUser.email).toLowerCase();
  return {
    authUserId: authUser.id,
    legacyUid: legacyUid || authUser.id,
    email,
    role,
  };
}

export const requireAuthContext = getAuthContext;

export async function getPropertyById(
  admin: SupabaseClient,
  propertyId: string,
): Promise<JsonMap | null> {
  const { data, error } = await admin
    .from("rural_properties")
    .select("*")
    .eq("id", normalizeId(propertyId))
    .maybeSingle();
  if (error) throw new Error(error.message);
  return data as JsonMap | null;
}

export async function getGatewayById(
  admin: SupabaseClient,
  gatewayId: string,
): Promise<JsonMap | null> {
  const { data, error } = await admin
    .from("gateways")
    .select("*")
    .eq("id", normalizeId(gatewayId))
    .maybeSingle();
  if (error) throw new Error(error.message);
  return data as JsonMap | null;
}

export async function getCollarById(
  admin: SupabaseClient,
  collarId: string,
): Promise<JsonMap | null> {
  const { data, error } = await admin
    .from("collars")
    .select("*")
    .eq("id", normalizeId(collarId))
    .maybeSingle();
  if (error) throw new Error(error.message);
  return data as JsonMap | null;
}

export async function listGateways(
  admin: SupabaseClient,
): Promise<JsonMap[]> {
  const { data, error } = await admin.from("gateways").select("*");
  if (error) throw new Error(error.message);
  return (data ?? []) as JsonMap[];
}

export function userHasPropertyAccess(
  legacyUid: string,
  role: string,
  propertyData: JsonMap,
): boolean {
  const normalizedRole = normalizeRole(role);
  if (normalizedRole === "adm" || normalizedRole === "admin") return true;
  const normalizedUid = normalizeId(legacyUid);
  if (!normalizedUid) return false;
  const ownerUid = normalizeId(propertyData.owner_uid ?? propertyData.ownerUid);
  const createdByUid = normalizeId(
    propertyData.created_by_uid ?? propertyData.createdByUid,
  );
  const rawUserUids = Array.isArray(propertyData.user_uids)
    ? propertyData.user_uids
    : Array.isArray(propertyData.userUids)
    ? propertyData.userUids
    : [];
  const linkedUserIds = normalizeIdList(rawUserUids);
  return ownerUid === normalizedUid ||
    createdByUid === normalizedUid ||
    linkedUserIds.includes(normalizedUid);
}
