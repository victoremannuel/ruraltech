import {
  corsHeaders,
  createAdminClient,
  jsonResponse,
  normalizeId,
  normalizeIdList,
  normalizeText,
  type JsonMap,
} from "../_shared/supabase.ts";

function parseJsonBody(request: Request): Promise<JsonMap> {
  return request.json()
    .then((body) => (body && typeof body === "object" && !Array.isArray(body)
      ? body as JsonMap
      : {}))
    .catch(() => ({}));
}

function pickRuntimeId(pathSegments: string[], body: JsonMap): string {
  if (pathSegments[0] === "matrixCommandQueues" && pathSegments.length >= 2) {
    return normalizeId(pathSegments[1]);
  }
  if (
    pathSegments[0] === "matrixBindings" || pathSegments[0] === "matrixQueueKeys" ||
    pathSegments[0] === "matrixCommandResults"
  ) {
    const fromBody = normalizeId(body.matrixRuntimeId ?? body.matrixId);
    return fromBody || normalizeId(pathSegments[1]);
  }
  return normalizeId(body.matrixRuntimeId ?? body.matrixId);
}

async function validateWriterKey(
  method: string,
  pathSegments: string[],
  body: JsonMap,
): Promise<boolean> {
  const admin = createAdminClient();
  const runtimeId = pickRuntimeId(pathSegments, body);
  const providedWriterKey = normalizeText(
    body.writerKey ?? body.writer_key,
  );
  const headerWriterKey = normalizeText(
    body.__writerKeyHeader,
  );
  const writerKey = headerWriterKey || providedWriterKey;
  if (!writerKey) return false;

  if (pathSegments[0] === "matrixQueueKeys" && method === "PUT") {
    const { data, error } = await admin
      .from("matrix_queue_keys")
      .select("writer_key")
      .eq("runtime_id", normalizeId(pathSegments[1]))
      .maybeSingle();
    if (error) throw new Error(error.message);
    const existing = normalizeText(data?.writer_key);
    return !existing || existing === writerKey;
  }

  if (!runtimeId) return false;
  const { data, error } = await admin
    .from("matrix_queue_keys")
    .select("writer_key")
    .eq("runtime_id", runtimeId)
    .maybeSingle();
  if (error) throw new Error(error.message);
  const expected = normalizeText(data?.writer_key);
  return !!expected && expected === writerKey;
}

function normalizePath(rawPath: string): string[] {
  return rawPath.split("/").map((part) => part.trim()).filter(Boolean);
}

function dayKeyFromMs(value: number): string {
  return new Date(value).toISOString().slice(0, 10).replaceAll("-", "");
}

async function updateCollarTelemetry(
  propertyId: string,
  deviceId: string,
  body: JsonMap,
) {
  const admin = createAdminClient();
  const lat = typeof body.lat === "number" ? body.lat : null;
  const lon = typeof body.lon === "number" ? body.lon : null;
  const receivedAtMs = Number(body.receivedAtMs ?? body.received_at_ms ?? 0) || null;
  const collarId = normalizeId(deviceId);
  const hasPosition = lat != null && lon != null;
  const payloadName = normalizeText(body.name ?? body.collarName ?? body.collar_name);
  const { data: existingCollar, error: existingError } = await admin
    .from("collars")
    .select("name")
    .eq("id", collarId)
    .maybeSingle();
  if (existingError) throw new Error(existingError.message);
  const existingCollarName = normalizeText(existingCollar?.name);
  const safeCollarName = payloadName || existingCollarName || `Coleira ${collarId}`;
  const upsertPayload: JsonMap = {
    id: collarId,
    device_id: collarId,
    property_id: propertyId,
    name: safeCollarName,
    telemetry_received_at_ms: receivedAtMs,
  };
  if (hasPosition) {
    upsertPayload.position = [lat, lon];
    upsertPayload.position_received_at_ms = receivedAtMs;
  }
  const update = await admin.from("collars").upsert(upsertPayload);
  if (update.error) {
    console.error("collar_telemetry_upsert_failed", {
      device_id: collarId,
      property_id: propertyId,
      has_payload_name: !!payloadName,
      existing_collar_name: existingCollarName || null,
      safe_collar_name: safeCollarName,
      error: update.error.message,
    });
    throw new Error(update.error.message);
  }
}

async function updateCollarHealth(
  propertyId: string,
  deviceId: string,
  body: JsonMap,
) {
  const admin = createAdminClient();
  const healthReceivedAtMs = Number(
    body.receivedAtMs ?? body.healthReceivedAtMs ?? body.received_at_ms ?? 0,
  ) || null;
  const update = await admin.from("collars").upsert({
    id: normalizeId(deviceId),
    device_id: normalizeId(deviceId),
    property_id: propertyId,
    health_received_at_ms: healthReceivedAtMs,
    health_gps_day_key: Number(body.gpsDayKey ?? body.healthGpsDayKey ?? 0) || null,
    health_flags: Number(body.healthFlags ?? 0) || null,
    health_uptime_sec: Number(body.uptimeSec ?? body.healthUptimeSec ?? 0) || null,
    health_temperature_deci_c: Number(body.temperatureDeciC ?? body.healthTemperatureDeciC ?? 0) || null,
    health_satellites: Number(body.sat ?? body.healthSatellites ?? 0) || null,
    health_hdop_centi: Number(body.hdopCenti ?? body.healthHdopCenti ?? 0) || null,
    health_i2c_devices: Number(body.i2cDevices ?? body.healthI2cDevices ?? 0) || null,
  });
  if (update.error) throw new Error(update.error.message);
}

async function updateHerdingOperationFromCommand(body: JsonMap) {
  const originDocType = normalizeText(body.originDocType ?? body.origin_doc_type);
  if (originDocType !== "herdingOperation") return;
  const operationId = normalizeId(body.originDocId ?? body.origin_doc_id);
  if (!operationId) return;

  const commandStatus = normalizeText(body.status).toLowerCase();
  let operationStatus = "";
  switch (commandStatus) {
    case "queued":
      operationStatus = "submitted";
      break;
    case "dispatching":
      operationStatus = "dispatching";
      break;
    case "acknowledged":
      operationStatus = "requested";
      break;
    case "completed":
      operationStatus = "completed";
      break;
    case "failed":
    case "expired":
    case "rejected":
    case "nacked":
      operationStatus = "failed";
      break;
    default:
      operationStatus = "";
      break;
  }

  const admin = createAdminClient();
  const update: JsonMap = {
    lora_command_id: normalizeId(body.commandId ?? body.command_id),
    property_scope_id: normalizeText(body.propertyScopeId ?? body.property_scope_id),
    updated_at: new Date().toISOString(),
  };
  if (operationStatus) update.status = operationStatus;
  if (body.deviceResults && typeof body.deviceResults === "object") {
    update.device_statuses = body.deviceResults;
  }
  if (body.reason != null) {
    update.client_failure_reason = normalizeText(body.reason);
  }
  const result = await admin.from("herding_operations").update(update).eq("id", operationId);
  if (result.error) throw new Error(result.error.message);
}

async function handleMatrixBindings(
  method: string,
  pathSegments: string[],
  body: JsonMap,
) {
  const admin = createAdminClient();
  const runtimeId = normalizeId(pathSegments[1]);
  if (!runtimeId) throw new Error("invalid_runtime_id");
  if (method === "GET") {
    const { data, error } = await admin.from("matrix_bindings")
      .select("raw")
      .eq("runtime_id", runtimeId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data?.raw ?? null;
  }
  if (method === "DELETE") {
    const { error } = await admin.from("matrix_bindings").delete().eq("runtime_id", runtimeId);
    if (error) throw new Error(error.message);
    return null;
  }
  const payload = {
    runtime_id: runtimeId,
    property_id: normalizeId(body.propertyId ?? body.property_id),
    property_scope_id: normalizeText(body.propertyScopeId ?? body.property_scope_id),
    matrix_gateway_id: normalizeId(body.matrixGatewayId ?? body.matrix_gateway_id),
    enabled: body.enabled === true,
    updated_at_ms: Number(body.updatedAtMs ?? body.updated_at_ms ?? Date.now()),
    raw: body,
  };
  const { error } = await admin.from("matrix_bindings").upsert(payload);
  if (error) throw new Error(error.message);
  return payload.raw;
}

async function handleMatrixQueueKeys(
  method: string,
  pathSegments: string[],
  body: JsonMap,
) {
  const admin = createAdminClient();
  const runtimeId = normalizeId(pathSegments[1]);
  if (!runtimeId) throw new Error("invalid_runtime_id");
  if (method === "GET") {
    const { data, error } = await admin.from("matrix_queue_keys")
      .select("raw")
      .eq("runtime_id", runtimeId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data?.raw ?? null;
  }
  if (method === "DELETE") {
    const { error } = await admin.from("matrix_queue_keys").delete().eq("runtime_id", runtimeId);
    if (error) throw new Error(error.message);
    return null;
  }
  const payload = {
    runtime_id: runtimeId,
    queue_key: normalizeText(body.queueKey ?? body.queue_key),
    writer_key: normalizeText(body.writerKey ?? body.writer_key),
    updated_at_ms: Number(body.updatedAtMs ?? body.updated_at_ms ?? Date.now()),
    raw: body,
  };
  const { error } = await admin.from("matrix_queue_keys").upsert(payload);
  if (error) throw new Error(error.message);
  return payload.raw;
}

async function handleMatrixCommandQueues(
  method: string,
  pathSegments: string[],
  body: JsonMap,
) {
  const admin = createAdminClient();
  const runtimeId = normalizeId(pathSegments[1]);
  const queueKey = normalizeText(pathSegments[2]);
  if (!runtimeId || !queueKey) throw new Error("invalid_queue_path");

  if (method === "GET" && pathSegments.length === 3) {
    const { data, error } = await admin.from("matrix_command_queues")
      .select("command_id,payload")
      .eq("runtime_id", runtimeId)
      .eq("queue_key", queueKey)
      .order("created_at_ms", { ascending: true });
    if (error) throw new Error(error.message);
    const out: Record<string, unknown> = {};
    for (const row of data ?? []) {
      const commandId = normalizeId((row as JsonMap).command_id);
      if (!commandId) continue;
      out[commandId] = (row as JsonMap).payload ?? null;
    }
    return out;
  }

  const commandId = normalizeId(pathSegments[3]);
  if (!commandId) throw new Error("invalid_command_id");
  if (method === "DELETE") {
    const { error } = await admin.from("matrix_command_queues")
      .delete()
      .eq("runtime_id", runtimeId)
      .eq("queue_key", queueKey)
      .eq("command_id", commandId);
    if (error) throw new Error(error.message);
    return null;
  }
  if (method === "GET") {
    const { data, error } = await admin.from("matrix_command_queues")
      .select("payload")
      .eq("runtime_id", runtimeId)
      .eq("queue_key", queueKey)
      .eq("command_id", commandId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data?.payload ?? null;
  }
  const payload = {
    runtime_id: runtimeId,
    queue_key: queueKey,
    command_id: commandId,
    created_at_ms: Number(body.createdAtMs ?? body.created_at_ms ?? Date.now()),
    expires_at_ms: Number(body.expiresAtMs ?? body.expires_at_ms ?? 0) || null,
    payload: body,
  };
  const { error } = await admin.from("matrix_command_queues").upsert(payload);
  if (error) throw new Error(error.message);
  return payload.payload;
}

async function handleMatrixCommandResults(
  method: string,
  pathSegments: string[],
  body: JsonMap,
) {
  const admin = createAdminClient();
  const runtimeId = normalizeId(pathSegments[1]);
  const commandId = normalizeId(pathSegments[2]);
  if (!runtimeId || !commandId) throw new Error("invalid_command_result_path");
  if (method === "GET") {
    const { data, error } = await admin.from("matrix_command_results")
      .select("payload")
      .eq("runtime_id", runtimeId)
      .eq("command_id", commandId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data?.payload ?? null;
  }
  if (method === "DELETE") {
    const { error } = await admin.from("matrix_command_results")
      .delete()
      .eq("runtime_id", runtimeId)
      .eq("command_id", commandId);
    if (error) throw new Error(error.message);
    return null;
  }
  const payload = {
    runtime_id: runtimeId,
    command_id: commandId,
    updated_at_ms: Number(body.updatedAtMs ?? body.updated_at_ms ?? Date.now()),
    payload: body,
  };
  const { error } = await admin.from("matrix_command_results").upsert(payload);
  if (error) throw new Error(error.message);
  return payload.payload;
}

async function handlePropertyTelemetryLatest(
  method: string,
  pathSegments: string[],
  body: JsonMap,
) {
  const admin = createAdminClient();
  const propertyId = normalizeId(pathSegments[1]);
  const deviceId = normalizeId(pathSegments[2]);
  if (!propertyId || !deviceId) throw new Error("invalid_telemetry_latest_path");
  if (method === "GET") {
    const { data, error } = await admin.from("property_telemetry_latest")
      .select("payload")
      .eq("property_id", propertyId)
      .eq("device_id", deviceId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data?.payload ?? null;
  }
  if (method === "DELETE") {
    const { error } = await admin.from("property_telemetry_latest")
      .delete()
      .eq("property_id", propertyId)
      .eq("device_id", deviceId);
    if (error) throw new Error(error.message);
    return null;
  }
  const payload = {
    property_id: propertyId,
    device_id: deviceId,
    lat: typeof body.lat === "number" ? body.lat : null,
    lon: typeof body.lon === "number" ? body.lon : null,
    received_at_ms: Number(body.receivedAtMs ?? body.received_at_ms ?? 0) || null,
    payload: body,
  };
  const { error } = await admin.from("property_telemetry_latest").upsert(payload);
  if (error) throw new Error(error.message);
  await updateCollarTelemetry(propertyId, deviceId, body);
  return body;
}

async function handlePropertyTelemetryHistory(
  method: string,
  pathSegments: string[],
  body: JsonMap,
) {
  const admin = createAdminClient();
  const propertyId = normalizeId(pathSegments[1]);
  const deviceId = normalizeId(pathSegments[2]);
  const dayKey = normalizeText(pathSegments[3]);
  const historyId = normalizeText(pathSegments[4]);
  if (!propertyId || !deviceId || !dayKey || !historyId) {
    throw new Error("invalid_telemetry_history_path");
  }
  if (method === "DELETE") {
    const { error } = await admin.from("property_telemetry_history")
      .delete()
      .eq("property_id", propertyId)
      .eq("device_id", deviceId)
      .eq("history_id", historyId);
    if (error) throw new Error(error.message);
    return null;
  }
  if (method === "GET") {
    const { data, error } = await admin.from("property_telemetry_history")
      .select("payload")
      .eq("property_id", propertyId)
      .eq("device_id", deviceId)
      .eq("history_id", historyId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data?.payload ?? null;
  }
  const payload = {
    property_id: propertyId,
    device_id: deviceId,
    history_id: historyId,
    day_key: dayKey,
    lat: typeof body.lat === "number" ? body.lat : null,
    lon: typeof body.lon === "number" ? body.lon : null,
    received_at_ms: Number(body.receivedAtMs ?? body.received_at_ms ?? 0) || null,
    payload: body,
  };
  const { error } = await admin.from("property_telemetry_history").upsert(payload);
  if (error) throw new Error(error.message);
  return body;
}

async function handlePropertyHealthLatest(
  method: string,
  pathSegments: string[],
  body: JsonMap,
) {
  const admin = createAdminClient();
  const propertyId = normalizeId(pathSegments[1]);
  const deviceId = normalizeId(pathSegments[2]);
  if (!propertyId || !deviceId) throw new Error("invalid_health_latest_path");
  if (method === "GET") {
    const { data, error } = await admin.from("property_health_latest")
      .select("payload")
      .eq("property_id", propertyId)
      .eq("device_id", deviceId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data?.payload ?? null;
  }
  if (method === "DELETE") {
    const { error } = await admin.from("property_health_latest")
      .delete()
      .eq("property_id", propertyId)
      .eq("device_id", deviceId);
    if (error) throw new Error(error.message);
    return null;
  }
  const healthReceivedAtMs = Number(
    body.receivedAtMs ?? body.healthReceivedAtMs ?? body.received_at_ms ?? 0,
  ) || null;
  const payload = {
    property_id: propertyId,
    device_id: deviceId,
    health_received_at_ms: healthReceivedAtMs,
    payload: body,
  };
  const { error } = await admin.from("property_health_latest").upsert(payload);
  if (error) throw new Error(error.message);
  await updateCollarHealth(propertyId, deviceId, body);
  return body;
}

async function handlePropertyHealthHistory(
  method: string,
  pathSegments: string[],
  body: JsonMap,
) {
  const admin = createAdminClient();
  const propertyId = normalizeId(pathSegments[1]);
  const deviceId = normalizeId(pathSegments[2]);
  const dayKey = normalizeText(pathSegments[3]);
  const historyId = normalizeText(pathSegments[4]);
  if (!propertyId || !deviceId || !dayKey || !historyId) {
    throw new Error("invalid_health_history_path");
  }
  if (method === "GET") {
    const { data, error } = await admin.from("property_health_history")
      .select("payload")
      .eq("property_id", propertyId)
      .eq("device_id", deviceId)
      .eq("history_id", historyId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data?.payload ?? null;
  }
  if (method === "DELETE") {
    const { error } = await admin.from("property_health_history")
      .delete()
      .eq("property_id", propertyId)
      .eq("device_id", deviceId)
      .eq("history_id", historyId);
    if (error) throw new Error(error.message);
    return null;
  }
  const payload = {
    property_id: propertyId,
    device_id: deviceId,
    history_id: historyId,
    day_key: dayKey,
    health_received_at_ms: Number(
      body.receivedAtMs ?? body.healthReceivedAtMs ?? body.received_at_ms ?? 0,
    ) || null,
    payload: body,
  };
  const { error } = await admin.from("property_health_history").upsert(payload);
  if (error) throw new Error(error.message);
  return body;
}

async function handlePropertyEvents(
  method: string,
  pathSegments: string[],
  body: JsonMap,
) {
  const admin = createAdminClient();
  const propertyId = normalizeId(pathSegments[1]);
  const dayKey = normalizeText(pathSegments[2]);
  const eventId = normalizeText(pathSegments[3]);
  if (!propertyId || !dayKey || !eventId) throw new Error("invalid_property_event_path");
  if (method === "GET") {
    const { data, error } = await admin.from("property_events")
      .select("payload")
      .eq("property_id", propertyId)
      .eq("day_key", dayKey)
      .eq("event_id", eventId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data?.payload ?? null;
  }
  if (method === "DELETE") {
    const { error } = await admin.from("property_events")
      .delete()
      .eq("property_id", propertyId)
      .eq("day_key", dayKey)
      .eq("event_id", eventId);
    if (error) throw new Error(error.message);
    return null;
  }
  const receivedAtMs = Number(body.receivedAtMs ?? body.received_at_ms ?? 0) || Date.now();
  const payload = {
    property_id: propertyId,
    day_key: dayKey,
    event_id: eventId,
    device_id: normalizeId(body.deviceId ?? body.device_id),
    gateway_id: normalizeId(body.gatewayId ?? body.gateway_id),
    event_type: normalizeText(body.eventType ?? body.event_type ?? body.type),
    lat: typeof body.lat === "number" ? body.lat : null,
    lon: typeof body.lon === "number" ? body.lon : null,
    position_received_at_ms: Number(body.positionReceivedAtMs ?? body.position_received_at_ms ?? receivedAtMs) || null,
    received_at_ms: receivedAtMs,
    payload: body,
  };
  const propertyEventUpsert = await admin.from("property_events").upsert(payload);
  if (propertyEventUpsert.error) throw new Error(propertyEventUpsert.error.message);

  const propertyResult = await admin.from("rural_properties")
    .select("owner_uid")
    .eq("id", propertyId)
    .maybeSingle();
  if (propertyResult.error) throw new Error(propertyResult.error.message);
  const eventUpsert = await admin.from("events").upsert({
    id: eventId,
    owner_uid: normalizeId(propertyResult.data?.owner_uid),
    property_id: propertyId,
    device_id: normalizeId(body.deviceId ?? body.device_id),
    gateway_id: normalizeId(body.gatewayId ?? body.gateway_id),
    type: normalizeText(body.type ?? body.eventType ?? body.event_type),
    event_type: normalizeText(body.eventType ?? body.event_type ?? body.type),
    polygon_kind: normalizeText(body.polygonKind ?? body.polygon_kind),
    origin_doc_type: normalizeText(body.originDocType ?? body.origin_doc_type),
    origin_doc_id: normalizeId(body.originDocId ?? body.origin_doc_id ?? body.operationId),
    received_at_ms: receivedAtMs,
    payload: body,
  });
  if (eventUpsert.error) throw new Error(eventUpsert.error.message);
  return body;
}

async function handlePropertyCommands(
  method: string,
  pathSegments: string[],
  body: JsonMap,
) {
  const admin = createAdminClient();
  const propertyId = normalizeId(pathSegments[1]);
  const commandId = normalizeId(pathSegments[2]);
  if (!propertyId || !commandId) throw new Error("invalid_property_command_path");
  if (method === "GET") {
    const { data, error } = await admin.from("property_commands")
      .select("raw")
      .eq("property_id", propertyId)
      .eq("command_id", commandId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data?.raw ?? null;
  }
  if (method === "DELETE") {
    const { error } = await admin.from("property_commands")
      .delete()
      .eq("property_id", propertyId)
      .eq("command_id", commandId);
    if (error) throw new Error(error.message);
    return null;
  }
  const raw = body;
  const payload = {
    property_id: propertyId,
    command_id: commandId,
    command: normalizeText(body.command),
    status: normalizeText(body.status),
    property_scope_id: normalizeText(body.propertyScopeId ?? body.property_scope_id),
    matrix_gateway_id: normalizeId(body.matrixGatewayId ?? body.matrix_gateway_id),
    requested_by_uid: normalizeId(body.requestedByUid ?? body.requested_by_uid),
    requested_by_role: normalizeText(body.requestedByRole ?? body.requested_by_role),
    created_at_ms: Number(body.createdAtMs ?? body.created_at_ms ?? 0) || null,
    updated_at_ms: Number(body.updatedAtMs ?? body.updated_at_ms ?? Date.now()),
    expires_at_ms: Number(body.expiresAtMs ?? body.expires_at_ms ?? 0) || null,
    polygon_kind: normalizeText(body.polygonKind ?? body.polygon_kind),
    origin_doc_type: normalizeText(body.originDocType ?? body.origin_doc_type),
    origin_doc_id: normalizeId(body.originDocId ?? body.origin_doc_id),
    target_device_ids: normalizeIdList(body.targetDeviceIds),
    target_gateway_ids: normalizeIdList(body.targetGatewayIds),
    device_results: body.deviceResults && typeof body.deviceResults === "object"
      ? body.deviceResults
      : {},
    reason: normalizeText(body.reason),
    payload: body.payload && typeof body.payload === "object" ? body.payload : {},
    raw,
  };
  const { error } = await admin.from("property_commands").upsert(payload);
  if (error) throw new Error(error.message);
  await updateHerdingOperationFromCommand(body);
  return raw;
}

async function handlePropertyCommandEvents(
  method: string,
  pathSegments: string[],
  body: JsonMap,
) {
  const admin = createAdminClient();
  const propertyId = normalizeId(pathSegments[1]);
  const commandId = normalizeId(pathSegments[2]);
  const eventId = normalizeText(pathSegments[3]);
  if (!propertyId || !commandId || !eventId) {
    throw new Error("invalid_property_command_event_path");
  }
  if (method === "GET") {
    const { data, error } = await admin.from("property_command_events")
      .select("raw")
      .eq("property_id", propertyId)
      .eq("event_id", eventId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data?.raw ?? null;
  }
  if (method === "DELETE") {
    const { error } = await admin.from("property_command_events")
      .delete()
      .eq("property_id", propertyId)
      .eq("event_id", eventId);
    if (error) throw new Error(error.message);
    return null;
  }
  const receivedAtMs = Number(body.createdAtMs ?? body.receivedAtMs ?? Date.now());
  const payload = {
    property_id: propertyId,
    day_key: dayKeyFromMs(receivedAtMs),
    event_id: eventId,
    command_id: commandId,
    device_id: normalizeId(body.deviceId ?? body.device_id),
    status: normalizeText(body.status),
    received_at_ms: receivedAtMs,
    payload: body,
    raw: body,
  };
  const { error } = await admin.from("property_command_events").upsert(payload);
  if (error) throw new Error(error.message);
  return body;
}

async function handleRoute(
  method: string,
  pathSegments: string[],
  body: JsonMap,
): Promise<unknown> {
  switch (pathSegments[0]) {
    case "matrixBindings":
      return await handleMatrixBindings(method, pathSegments, body);
    case "matrixQueueKeys":
      return await handleMatrixQueueKeys(method, pathSegments, body);
    case "matrixCommandQueues":
      return await handleMatrixCommandQueues(method, pathSegments, body);
    case "matrixCommandResults":
      return await handleMatrixCommandResults(method, pathSegments, body);
    case "propertyTelemetryLatest":
      return await handlePropertyTelemetryLatest(method, pathSegments, body);
    case "propertyTelemetryHistory":
      return await handlePropertyTelemetryHistory(method, pathSegments, body);
    case "propertyHealthLatest":
      return await handlePropertyHealthLatest(method, pathSegments, body);
    case "propertyHealthHistory":
      return await handlePropertyHealthHistory(method, pathSegments, body);
    case "propertyEvents":
      return await handlePropertyEvents(method, pathSegments, body);
    case "propertyCommands":
      return await handlePropertyCommands(method, pathSegments, body);
    case "propertyCommandEvents":
      return await handlePropertyCommandEvents(method, pathSegments, body);
    default:
      throw new Error("unsupported_path");
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders() });
  }
  const url = new URL(request.url);
  const path = normalizeText(url.searchParams.get("path"));
  const pathSegments = normalizePath(path);
  if (!pathSegments.length) {
    return jsonResponse(400, { ok: false, reason: "missing_path" });
  }

  try {
    const body = request.method === "GET" || request.method === "DELETE"
      ? {}
      : await parseJsonBody(request);
    body.__writerKeyHeader = request.headers.get("x-matrix-writer-key") ?? "";

    const isReadOnly = request.method === "GET";
    if (!isReadOnly) {
      const valid = await validateWriterKey(request.method, pathSegments, body);
      if (!valid) {
        return jsonResponse(403, { ok: false, reason: "invalid_writer_key" });
      }
    } else if (pathSegments[0] === "matrixCommandQueues") {
      const valid = await validateWriterKey("GET", pathSegments, body);
      if (!valid) {
        return jsonResponse(403, { ok: false, reason: "invalid_writer_key" });
      }
    }

    const data = await handleRoute(request.method, pathSegments, body);
    if (request.method === "GET") {
      return new Response(JSON.stringify(data ?? null), {
        status: 200,
        headers: corsHeaders(),
      });
    }
    return jsonResponse(200, { ok: true, data });
  } catch (error) {
    return jsonResponse(500, {
      ok: false,
      reason: error instanceof Error ? error.message : "unknown_error",
    });
  }
});
