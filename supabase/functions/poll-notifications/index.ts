import {
  corsHeaders,
  createAdminClient,
  getAuthContext,
  getJsonBody,
  jsonResponse,
  normalizeText,
} from "../_shared/supabase.ts";

// Edge Function: poll-notifications
// Usada pelo WorkManager do Android para buscar notificações pendentes em background.
// Requer JWT válido (verify_jwt = true no config.toml).
//
// POST body: { since_ts?: string }  (ISO 8601 ou ms epoch)
// Retorna: { notifications: [...], count: number }

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders() });
  }

  const admin = createAdminClient();
  let auth;
  try {
    auth = await getAuthContext(request, admin);
  } catch (e) {
    const msg = (e as Error).message ?? "auth_error";
    return jsonResponse(401, { error: msg });
  }

  const body = await getJsonBody(request);
  const rawSince = body.since_ts ?? body.sinceTs;

  let sinceTs: string;
  if (rawSince == null) {
    // sem since_ts: devolver últimas 24h não entregues
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000);
    sinceTs = since.toISOString();
  } else if (typeof rawSince === "number") {
    sinceTs = new Date(rawSince).toISOString();
  } else {
    sinceTs = normalizeText(rawSince);
  }

  const legacyUid = auth.legacyUid;
  if (!legacyUid) {
    return jsonResponse(400, { error: "missing_legacy_uid" });
  }

  const { data: rows, error } = await admin
    .from("pending_notifications")
    .select("id, title, body, data, created_at")
    .eq("legacy_uid", legacyUid)
    .eq("delivered", false)
    .gt("created_at", sinceTs)
    .order("created_at", { ascending: true })
    .limit(50);

  if (error) {
    return jsonResponse(500, { error: error.message });
  }

  const notifications = rows ?? [];

  // Marcar como entregues em batch
  if (notifications.length > 0) {
    const ids = notifications.map((n: { id: string }) => n.id);
    await admin
      .from("pending_notifications")
      .update({ delivered: true })
      .in("id", ids);
  }

  return jsonResponse(200, {
    notifications,
    count: notifications.length,
  });
});
