import {
  corsHeaders,
  createAdminClient,
  getAuthContext,
  getJsonBody,
  jsonResponse,
  normalizeId,
  normalizeIdList,
  normalizeText,
  type JsonMap,
} from "../_shared/supabase.ts";

interface PushToken {
  legacy_uid: string;
  platform: string;
  token: string;
}

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

  const userIds = normalizeIdList(body.user_ids ?? body.userIds);
  if (userIds.length === 0) {
    return jsonResponse(400, { error: "missing_user_ids" });
  }

  const title = normalizeText(body.title);
  const message = normalizeText(body.message ?? body.body);
  const data = (body.data && typeof body.data === "object" && !Array.isArray(body.data))
    ? body.data as JsonMap
    : {};

  if (!title && !message && Object.keys(data).length === 0) {
    return jsonResponse(400, { error: "missing_payload" });
  }

  const { data: tokens, error: tokensError } = await admin
    .from("user_push_tokens")
    .select("legacy_uid, platform, token")
    .in_("legacy_uid", userIds);

  if (tokensError) {
    return jsonResponse(500, { error: tokensError.message });
  }

  const pushTokens = (tokens ?? []) as PushToken[];
  if (pushTokens.length === 0) {
    return jsonResponse(200, { sent: 0, skipped: userIds.length, errors: [] });
  }

  const fcmServerKey = normalizeText(Deno.env.get("FCM_SERVER_KEY"));
  const apnsKeyId = normalizeText(Deno.env.get("APNS_KEY_ID"));
  const apnsTeamId = normalizeText(Deno.env.get("APNS_TEAM_ID"));
  const apnsBundleId = normalizeText(Deno.env.get("APNS_BUNDLE_ID"));
  const apnsPrivateKey = normalizeText(Deno.env.get("APNS_PRIVATE_KEY"));

  let sent = 0;
  const errors: string[] = [];

  for (const pt of pushTokens) {
    try {
      if (pt.platform === "ios" && apnsPrivateKey && apnsKeyId && apnsTeamId) {
        const ok = await sendApns(pt.token, { title, message, data }, {
          keyId: apnsKeyId,
          teamId: apnsTeamId,
          bundleId: apnsBundleId,
          privateKey: apnsPrivateKey,
        });
        if (ok) sent++;
        else errors.push(`apns_fail:${pt.legacy_uid}`);
      } else if (fcmServerKey) {
        const ok = await sendFcm(pt.token, { title, message, data }, fcmServerKey);
        if (ok) sent++;
        else errors.push(`fcm_fail:${pt.legacy_uid}`);
      } else {
        errors.push(`no_transport:${pt.platform}:${pt.legacy_uid}`);
      }
    } catch (e) {
      errors.push(`exception:${pt.legacy_uid}:${(e as Error).message}`);
    }
  }

  return jsonResponse(200, {
    sent,
    skipped: pushTokens.length - sent,
    errors,
  });
});

async function sendFcm(
  token: string,
  payload: { title: string; message: string; data: JsonMap },
  serverKey: string,
): Promise<boolean> {
  const body: JsonMap = {
    to: token,
    data: payload.data,
  };
  if (payload.title || payload.message) {
    body.notification = {
      title: payload.title || undefined,
      body: payload.message || undefined,
    };
  }

  const response = await fetch("https://fcm.googleapis.com/fcm/send", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `key=${serverKey}`,
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) return false;
  const result = await response.json();
  return result.success === 1;
}

async function sendApns(
  deviceToken: string,
  payload: { title: string; message: string; data: JsonMap },
  config: { keyId: string; teamId: string; bundleId: string; privateKey: string },
): Promise<boolean> {
  const jwt = await generateApnsJwt(config.keyId, config.teamId, config.privateKey);

  const apnsPayload: JsonMap = {
    aps: {
      alert: {
        title: payload.title || undefined,
        body: payload.message || undefined,
      },
      "content-available": 1,
    },
    ...payload.data,
  };

  const response = await fetch(
    `https://api.push.apple.com/3/device/${deviceToken}`,
    {
      method: "POST",
      headers: {
        Authorization: `bearer ${jwt}`,
        "apns-topic": config.bundleId,
        "apns-push-type": "alert",
        "apns-priority": "10",
      },
      body: JSON.stringify(apnsPayload),
    },
  );

  return response.ok;
}

async function generateApnsJwt(
  keyId: string,
  teamId: string,
  privateKeyPem: string,
): Promise<string> {
  const header = { alg: "ES256", kid: keyId };
  const now = Math.floor(Date.now() / 1000);
  const claims = { iss: teamId, iat: now };

  const enc = new TextEncoder();
  const headerB64 = base64UrlEncode(enc.encode(JSON.stringify(header)));
  const claimsB64 = base64UrlEncode(enc.encode(JSON.stringify(claims)));
  const signingInput = `${headerB64}.${claimsB64}`;

  const pemBody = privateKeyPem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const keyData = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));

  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    enc.encode(signingInput),
  );

  return `${signingInput}.${base64UrlEncode(new Uint8Array(signature))}`;
}

function base64UrlEncode(data: Uint8Array): string {
  let binary = "";
  for (const byte of data) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
