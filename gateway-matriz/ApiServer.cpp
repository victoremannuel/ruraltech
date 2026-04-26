/** @file ApiServer.cpp */
#include "ApiServer.h"
#include "config.h"
#include "LoRaGateway.h"
#include "../firmware/shared/command_contract.h"
#include "../firmware/shared/matrix_uplink_antireplay.h"
#include "../firmware/shared/build_info.h"
#include <ctype.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <WiFi.h>

extern char bindingPropertyId[48];
extern char bindingPropertyScopeId[17];
extern char bindingMatrixGatewayId[32];
extern uint32_t bindingVersion;
extern bool bindingReady;
extern bool supportsScopedLora;
extern uint64_t lastQueuePollAtUnixMs;
extern bool queueStreamConnected;
extern uint64_t queueStreamLastEventAtUnixMs;
extern uint64_t queueStreamReconnectAtUnixMs;
extern char queueStreamLastError[96];
extern char lastCloudWriteError[96];
extern LoRaGateway lora;
extern uint8_t acceptedUplinkQueueCount;
extern uint32_t acceptedUplinkDropCount;
extern uint32_t acceptedUplinkLastDrainAtMs;
extern uint8_t deferredUplinkQueueCount;
extern bool simpleAckWaitActive;
extern uint32_t simpleAckWaitDeviceId;
extern uint32_t simpleAckWaitDeadlineAtMs;
extern char simpleAckWaitCommandId[48];
extern char lastSimpleCommandFeedbackOutcome[24];
extern uint32_t lastSimpleCommandAckMatchedAtMs;
extern rtrdiag::PageSnapshot lastPageDiag;
extern rtrdiag::WakeLoopSnapshot wakeLoopDiag;
void fillBackhaulDiagJson(JsonObject obj);
void runBackhaulManualDiagnostic();

static ApiServer* g_server = nullptr;

static String compactIdentifier(const String& raw) {
  String out;
  out.reserve(raw.length());
  for (size_t i = 0; i < raw.length(); ++i) {
    const char c = raw[i];
    if ((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') ||
        (c >= 'a' && c <= 'f')) {
      out += (char)toupper((unsigned char)c);
    }
  }
  return out;
}

static String statusMatrixRuntimeId() {
  if (cfg::RTDB_MATRIX_ID[0] != '\0' &&
      strncmp(cfg::RTDB_MATRIX_ID, "SET_", 4) != 0) {
    return String(cfg::RTDB_MATRIX_ID);
  }
  if (bindingMatrixGatewayId[0]) {
    return String(bindingMatrixGatewayId);
  }
  return compactIdentifier(WiFi.softAPmacAddress());
}

static void copyToBuffer(char* dst, size_t dstSize, const char* src) {
  if (dstSize == 0) return;
  if (!src) {
    dst[0] = '\0';
    return;
  }
  strncpy(dst, src, dstSize - 1);
  dst[dstSize - 1] = '\0';
}

static bool parseDeviceId(const JsonVariantConst& value, uint32_t& out) {
  if (value.is<uint32_t>() || value.is<int>() || value.is<long>()) {
    const uint32_t parsed = value.as<uint32_t>();
    if (parsed == 0) return false;
    out = parsed;
    return true;
  }
  if (!value.is<const char*>()) return false;
  const char* text = value.as<const char*>();
  if (!text || !text[0]) return false;
  char* end = nullptr;
  const unsigned long parsed = strtoul(text, &end, 10);
  if (end == text || parsed == 0) return false;
  out = (uint32_t)parsed;
  return true;
}

static bool parseCoordinate(const JsonVariantConst& value, double& out) {
  if (value.is<double>() || value.is<float>() || value.is<int>() ||
      value.is<long>()) {
    out = value.as<double>();
  } else if (value.is<const char*>()) {
    const char* text = value.as<const char*>();
    if (!text || !text[0]) return false;
    char* end = nullptr;
    out = strtod(text, &end);
    if (end == text) return false;
  } else {
    return false;
  }
  return isfinite(out);
}

static bool parseKeyId(const JsonVariantConst& value, uint16_t& out) {
  uint32_t parsed = 0;
  if (value.is<uint32_t>() || value.is<int>() || value.is<long>()) {
    parsed = value.as<uint32_t>();
  } else if (value.is<const char*>()) {
    const char* text = value.as<const char*>();
    if (!text || !text[0]) return false;
    char* end = nullptr;
    parsed = (uint32_t)strtoul(text, &end, 10);
    if (end == text) return false;
  } else {
    return false;
  }
  if (parsed == 0 || parsed > 0xFFFFu) return false;
  out = static_cast<uint16_t>(parsed);
  return true;
}

static bool parseScopeIdText(
    const JsonVariantConst& value,
    uint64_t& out,
    String* normalizedText) {
  if (!value.is<const char*>()) return false;
  const String compact = compactIdentifier(value.as<const char*>());
  if (!rtcmd::isValidScopeId(compact.c_str())) return false;
  if (normalizedText) *normalizedText = compact;
  out = strtoull(compact.c_str(), nullptr, 16);
  return out != 0;
}

void ApiServer::begin() {
  g_server = this;
  if (cfg::FEATURE_HTTP) {
    http_.on("/status", HTTP_GET, [this]() {
      StaticJsonDocument<4096> doc;
      const buildinfo::BuildInfo build = buildinfo::current();
      doc["ok"] = true;
      doc["service"] = "gateway_matrix";
      doc["fw"] = cfg::FW_VERSION;
      doc["firmwareVersion"] = cfg::FW_VERSION;
      doc["firmwareRole"] = "matrix";
      doc["gitSha"] = build.gitSha;
      doc["gitShortSha"] = build.gitShortSha;
      doc["buildUtc"] = build.buildUtc;
      doc["buildDirty"] = build.dirty;
      doc["buildSource"] = build.buildSource;
      doc["diagStage"] = cfg::DIAG_STAGE;
      doc["diagProfile"] = cfg::DIAG_PROFILE_NAME;
      doc["protoVersion"] = cfg::LORA_PROTO_VERSION;
      doc["keyId"] = cfg::LORA_KEY_ID;
      doc["radioProfileId"] = cfg::LORA_RADIO_PROFILE_ID;
      const String apSsid = WiFi.softAPSSID();
      doc["ap_ssid"] = apSsid.isEmpty() ? String(cfg::AP_SSID) : apSsid;
      doc["ap_ip"] = WiFi.softAPIP().toString();
      doc["gatewayId"] = compactIdentifier(WiFi.softAPmacAddress());
      doc["ota"] = cfg::FEATURE_OTA && cfg::OTA_ENABLED;
      doc["wifi_ota_enabled"] = WiFi.getMode() != WIFI_OFF;
      doc["role"] = "matrix";
      doc["supportsScopedLora"] = supportsScopedLora;
      doc["bindingReady"] = bindingReady;
      doc["bindingVersion"] = bindingVersion;
      doc["featureWifiAp"] = cfg::FEATURE_WIFI_AP;
      doc["featureHttp"] = cfg::FEATURE_HTTP;
      doc["featureWs"] = cfg::FEATURE_WS;
      doc["featureOta"] = cfg::FEATURE_OTA;
      doc["featureBle"] = cfg::FEATURE_BLE;
      doc["featureBackhaul"] = cfg::FEATURE_BACKHAUL;
      doc["featureCloud"] = cfg::FEATURE_CLOUD;
      doc["featureSd"] = cfg::FEATURE_SD;
      doc["matrixRuntimeId"] = statusMatrixRuntimeId();
      if (cfg::RTDB_MATRIX_ID[0] != '\0') {
        doc["configuredMatrixId"] = cfg::RTDB_MATRIX_ID;
      }
      doc["cloudConfigured"] =
        cfg::FEATURE_CLOUD &&
        cfg::BACKHAUL_WIFI_SSID[0] != '\0' &&
        strncmp(cfg::BACKHAUL_WIFI_SSID, "SET_", 4) != 0 &&
        cfg::SUPABASE_EDGE_HOST[0] != '\0' &&
        strncmp(cfg::SUPABASE_EDGE_HOST, "SET_", 4) != 0 &&
        cfg::RTDB_WRITER_KEY[0] != '\0' &&
        strncmp(cfg::RTDB_WRITER_KEY, "SET_", 4) != 0;
      doc["queueConfigured"] = cfg::FEATURE_CLOUD &&
        cfg::RTDB_QUEUE_KEY[0] != '\0' &&
        strncmp(cfg::RTDB_QUEUE_KEY, "SET_", 4) != 0;
      doc["queuePollingConfigured"] = doc["cloudConfigured"].as<bool>() &&
        doc["queueConfigured"].as<bool>();
      doc["lastQueuePollAtMs"] = lastQueuePollAtUnixMs;
      doc["queueStreamConnected"] = queueStreamConnected;
      doc["queueStreamLastEventAtMs"] = queueStreamLastEventAtUnixMs;
      doc["queueStreamReconnectAtMs"] = queueStreamReconnectAtUnixMs;
      doc["queueStreamLastError"] = queueStreamLastError;
      doc["lastCloudWriteError"] = lastCloudWriteError;
      doc["apClientCount"] = WiFi.softAPgetStationNum();
      doc["loraReady"] = lora.isReady();
      doc["lastLoraReceiveCode"] = lora.lastReceiveCode();
      doc["lastLoraRawLen"] = (uint32_t)lora.lastReceiveLen();
      doc["lastLoraRssi"] = lora.lastRssi();
      doc["lastLoraSnr"] = lora.lastSnr();
      doc["lastLoraRawRxAtMs"] = lora.lastRawRxAtMs();
      doc["lastLoraAcceptedRxAtMs"] = lora.lastAcceptedRxAtMs();
      doc["loraRxArmCount"] = lora.rxArmCount();
      doc["loraTxCount"] = lora.txCount();
      doc["loraTxFailCount"] = lora.txFailCount();
      doc["loraDecryptFailCount"] = lora.decryptFailCount();
      doc["loraNonceMismatchCount"] = lora.nonceMismatchCount();
      doc["loraReplayRejectCount"] = lora.replayRejectCount();
      doc["lastAcceptedSeq"] = lora.lastAcceptedSeq();
      doc["lastLoraIrqFlags"] = lora.lastIrqFlags();
      doc["lastLoraState"] = lora.lastRadioState();
      JsonObject antiReplay = doc["antiReplay"].to<JsonObject>();
      antiReplay["diagResetEnabled"] = cfg::DIAG_ANTI_REPLAY_RESET_ENABLED;
      antiReplay["activeKeyId"] = cfg::LORA_KEY_ID;
      const AntiReplayBlockedSnapshot& blocked = lora.lastBlockedUplink();
      if (blocked.valid) {
        JsonObject lastBlocked = antiReplay["lastBlocked"].to<JsonObject>();
        char blockedScopeHex[rtmatrix::antireplay::kScopeHexSize]{};
        rtmatrix::antireplay::scopeIdToHex(
            blocked.scopeId, blockedScopeHex, sizeof(blockedScopeHex));
        lastBlocked["direction"] = "uplink";
        lastBlocked["deviceId"] = blocked.deviceId;
        lastBlocked["scopeId"] = blockedScopeHex;
        lastBlocked["keyId"] = blocked.keyId;
        lastBlocked["rxSeq"] = blocked.rxSeq;
        lastBlocked["lastAcceptedSeq"] = blocked.lastAcceptedSeq;
        lastBlocked["delta"] = blocked.delta;
        lastBlocked["frameType"] = blocked.frameType;
        lastBlocked["protoVersion"] = blocked.protoVersion;
        lastBlocked["radioProfile"] = blocked.radioProfile;
        lastBlocked["reason"] = blocked.reason;
        lastBlocked["atMs"] = blocked.atMs;
      }
      const rtrdiag::DecryptFailSnapshot& decryptFail = lora.lastDecryptFail();
      const rtrdiag::RawRxSnapshot& rawRx = lora.rawRxDiag();
      doc["lastDecryptFailAtMs"] = decryptFail.atMs;
      doc["lastDecryptFailLen"] = decryptFail.len;
      doc["lastDecryptFailRssi"] = decryptFail.rssi;
      doc["lastDecryptFailSnr"] = decryptFail.snr;
      doc["lastDecryptFailIrqFlags"] = decryptFail.irqFlags;
      doc["lastDecryptFailRadioState"] = decryptFail.radioState;
      doc["lastDecryptFailReason"] = decryptFail.reason;
      doc["lastDecryptFailHeadHex"] = decryptFail.headHex;
      doc["lastDecryptFailNonceHex"] = decryptFail.nonceHex;
      doc["lastDecryptFailTagHex"] = decryptFail.tagHex;
      doc["lastDecryptFailCount"] = decryptFail.count;
      doc["rawRxSeenCount"] = rawRx.rawRxSeenCount;
      doc["rawRxNoiseDropCount"] = rawRx.rawRxNoiseDropCount;
      doc["rawRxInvalidPatternDropCount"] = rawRx.rawRxInvalidPatternDropCount;
      doc["rawRxDecryptAttemptCount"] = rawRx.rawRxDecryptAttemptCount;
      doc["rawRxDecryptFailedCount"] = rawRx.rawRxDecryptFailedCount;
      doc["rawRxAcceptedCount"] = rawRx.rawRxAcceptedCount;
      doc["lastRawNoiseReason"] = rawRx.lastRawNoiseReason;
      doc["lastRawPatternHex"] = rawRx.lastRawPatternHex;
      doc["lastRawCandidateLen"] = rawRx.lastRawCandidateLen;
      doc["lastRawCandidateRssi"] = rawRx.lastRawCandidateRssi;
      doc["lastRawCandidateSnr"] = rawRx.lastRawCandidateSnr;
      char lastPageSessionId[24]{};
      snprintf(
          lastPageSessionId,
          sizeof(lastPageSessionId),
          "%llu",
          (unsigned long long)lastPageDiag.lastPageSessionId);
      doc["lastPageTargetDeviceId"] = lastPageDiag.lastPageTargetDeviceId;
      doc["lastPageSessionId"] = lastPageSessionId;
      doc["lastPageMessageId"] = lastPageDiag.lastPageMessageId;
      doc["lastPageCampaignCount"] = lastPageDiag.lastPageCampaignCount;
      doc["lastPageSentAtMs"] = lastPageDiag.lastPageSentAtMs;
      doc["lastPageAckDeadlineAtMs"] = lastPageDiag.lastPageAckDeadlineAtMs;
      doc["lastPageRetryAtMs"] = lastPageDiag.lastPageRetryAtMs;
      doc["lastWakeToPageLatencyMs"] = lastPageDiag.lastWakeToPageLatencyMs;
      doc["lastSoftDeadlineMs"] = lastPageDiag.lastSoftDeadlineMs;
      doc["lastSoftDeadlineMet"] = lastPageDiag.lastSoftDeadlineMet;
      char inFlightPageSessionId[24]{};
      snprintf(
          inFlightPageSessionId,
          sizeof(inFlightPageSessionId),
          "%llu",
          (unsigned long long)lastPageDiag.inFlightPageSessionId);
      doc["inFlightPageValid"] = lastPageDiag.inFlightPageValid;
      doc["inFlightPageSessionId"] = inFlightPageSessionId;
      doc["inFlightPageMessageId"] = lastPageDiag.inFlightPageMessageId;
      doc["inFlightPageCampaignCount"] = lastPageDiag.inFlightPageCampaignCount;
      doc["inFlightPageSentAtMs"] = lastPageDiag.inFlightPageSentAtMs;
      doc["inFlightPageSoftDeadlineAtMs"] = lastPageDiag.inFlightPageSoftDeadlineAtMs;
      doc["inFlightPageHardDeadlineAtMs"] = lastPageDiag.inFlightPageHardDeadlineAtMs;
      doc["inFlightPageAckAccepted"] = lastPageDiag.inFlightPageAckAccepted;
      doc["retryPending"] = lastPageDiag.retryPending;
      doc["retryAtMs"] = lastPageDiag.retryAtMs;
      doc["retryCampaignCount"] = lastPageDiag.retryCampaignCount;
      doc["lastAckMatchedInGrace"] = lastPageDiag.lastAckMatchedInGrace;
      doc["lastAckRejectedReason"] = lastPageDiag.lastAckRejectedReason;
      doc["lastWakeLoopStage"] = wakeLoopDiag.lastWakeLoopStage;
      doc["lastWakeLoopStageAtMs"] = wakeLoopDiag.lastWakeLoopStageAtMs;
      char lastWakeLoopStageSessionId[24]{};
      snprintf(
          lastWakeLoopStageSessionId,
          sizeof(lastWakeLoopStageSessionId),
          "%llu",
          (unsigned long long)wakeLoopDiag.lastWakeLoopStageSessionId);
      doc["lastWakeLoopStageSessionId"] = lastWakeLoopStageSessionId;
      doc["lastWakeLoopStageDeviceId"] = wakeLoopDiag.lastWakeLoopStageDeviceId;
      doc["wakeLoopIterationCount"] = wakeLoopDiag.wakeLoopIterationCount;
      doc["wakeLoopBudgetHitCount"] = wakeLoopDiag.wakeLoopBudgetHitCount;
      doc["wakeLoopYieldCount"] = wakeLoopDiag.wakeLoopYieldCount;
      doc["lastSoftTimeoutAtMs"] = wakeLoopDiag.lastSoftTimeoutAtMs;
      doc["lastRetryScheduleAtMs"] = wakeLoopDiag.lastRetryScheduleAtMs;
      doc["lastBeginDispatchAtMs"] = wakeLoopDiag.lastBeginDispatchAtMs;
      doc["lastPageOutcome"] = lastPageDiag.lastPageOutcome;
      doc["lastWakeHintAtMs"] = lastPageDiag.lastWakeHintAtMs;
      doc["lastWakeHintSeq"] = lastPageDiag.lastWakeHintSeq;
      doc["lastWakeHintAccepted"] = lastPageDiag.lastWakeHintAccepted;
      JsonObject wakeFastPath = doc["wakeFastPath"].to<JsonObject>();
      wakeFastPath["lastImmediateEnterAtMs"] = lastPageDiag.lastImmediateEnterAtMs;
      wakeFastPath["lastImmediateResultAtMs"] = lastPageDiag.lastImmediateResultAtMs;
      wakeFastPath["lastImmediateDeviceId"] = lastPageDiag.lastImmediateDeviceId;
      wakeFastPath["lastImmediateUplinkSeq"] = lastPageDiag.lastImmediateUplinkSeq;
      wakeFastPath["lastImmediateAgeMs"] = lastPageDiag.lastImmediateAgeMs;
      wakeFastPath["lastImmediateResult"] = lastPageDiag.lastImmediateResult;
      wakeFastPath["lastOrderViolation"] = lastPageDiag.lastOrderViolation;
      wakeFastPath["lastCloudDeferredForPage"] = lastPageDiag.lastCloudDeferredForPage;
      doc["acceptedUplinkQueueDepth"] = acceptedUplinkQueueCount;
      doc["acceptedUplinkDropCount"] = acceptedUplinkDropCount;
      doc["acceptedUplinkLastDrainAtMs"] = acceptedUplinkLastDrainAtMs;
      doc["ackWaitActive"] = simpleAckWaitActive;
      doc["ackWaitDeviceId"] = simpleAckWaitDeviceId;
      doc["ackWaitDeadlineAtMs"] = simpleAckWaitDeadlineAtMs;
      doc["deferredUplinkCount"] = deferredUplinkQueueCount;
      doc["lastFeedbackOutcome"] = lastSimpleCommandFeedbackOutcome;
      doc["lastAckMatchedAtMs"] = lastSimpleCommandAckMatchedAtMs;
      if (simpleAckWaitCommandId[0]) doc["ackWaitCommandId"] = simpleAckWaitCommandId;
      if (bindingPropertyId[0]) doc["propertyId"] = bindingPropertyId;
      if (bindingPropertyScopeId[0]) doc["propertyScopeId"] = bindingPropertyScopeId;
      if (bindingMatrixGatewayId[0]) doc["matrixGatewayId"] = bindingMatrixGatewayId;
      fillBackhaulDiagJson(doc["backhaul"].to<JsonObject>());
      String out;
      serializeJson(doc, out);
      http_.send(200, "application/json", out);
    });
    http_.on("/diag/backhaul", HTTP_GET, [this]() {
      StaticJsonDocument<768> doc;
      runBackhaulManualDiagnostic();
      doc["ok"] = true;
      fillBackhaulDiagJson(doc["backhaul"].to<JsonObject>());
      String out;
      serializeJson(doc, out);
      http_.send(200, "application/json", out);
    });
    http_.on("/diag/anti-replay/reset-uplink", HTTP_POST, [this]() {
      handleAntiReplayResetRequest();
    });
    http_.on("/devices", HTTP_GET, [this]() { handleDevicesRequest(); });
    http_.on("/logs", HTTP_GET, [this]() { handleLogsRequest(); });
    http_.begin();
    appendLogLine("HTTP_READY");
  }

  if (cfg::FEATURE_WS) {
    ws_.begin();
    ws_.onEvent([](uint8_t num, WStype_t type, uint8_t* payload, size_t len) {
      if (g_server) g_server->onWsEvent(num, type, payload, len);
    });
    appendLogLine("WS_READY");
  }
}

void ApiServer::handleAntiReplayResetRequest() {
  StaticJsonDocument<512> payload;
  StaticJsonDocument<512> response;
  const String body = http_.arg("plain");
  if (body.isEmpty()) {
    response["ok"] = false;
    response["reason"] = "missing_body";
    String out;
    serializeJson(response, out);
    http_.send(400, "application/json", out);
    return;
  }
  if (deserializeJson(payload, body) != DeserializationError::Ok) {
    response["ok"] = false;
    response["reason"] = "invalid_json";
    String out;
    serializeJson(response, out);
    http_.send(400, "application/json", out);
    return;
  }

  uint32_t deviceId = 0;
  uint64_t scopeId = 0;
  uint16_t keyId = 0;
  String scopeHex;
  if (!parseDeviceId(payload["deviceId"], deviceId)) {
    response["ok"] = false;
    response["reason"] = "invalid_device_id";
    String out;
    serializeJson(response, out);
    http_.send(400, "application/json", out);
    return;
  }
  if (!parseScopeIdText(payload["scopeId"], scopeId, &scopeHex)) {
    response["ok"] = false;
    response["reason"] = "invalid_scope_id";
    String out;
    serializeJson(response, out);
    http_.send(400, "application/json", out);
    return;
  }
  if (!parseKeyId(payload["keyId"], keyId)) {
    response["ok"] = false;
    response["reason"] = "invalid_key_id";
    String out;
    serializeJson(response, out);
    http_.send(400, "application/json", out);
    return;
  }
  const char* confirm = payload["confirm"] | "";
  if (strcmp(confirm, "RESET_UPLINK_ANTI_REPLAY") != 0) {
    response["ok"] = false;
    response["reason"] = "invalid_confirmation";
    String out;
    serializeJson(response, out);
    http_.send(400, "application/json", out);
    return;
  }

  AntiReplayResetResult result;
  const bool ok = lora.resetUplinkAntiReplayForDevice(
      deviceId, scopeId, keyId, "diag_http", &result);
  response["ok"] = ok;
  if (!ok) {
    response["reason"] = result.reason;
    String out;
    serializeJson(response, out);
    const int statusCode =
        strcmp(result.reason, "diag_mode_required") == 0 ? 403 : 400;
    http_.send(statusCode, "application/json", out);
    return;
  }

  response["direction"] = "uplink";
  response["deviceId"] = result.deviceId;
  response["scopeId"] = scopeHex;
  response["keyId"] = result.keyId;
  response["lastSeqBefore"] = result.lastSeqBefore;
  response["lastSeqAfter"] = result.lastSeqAfter;
  response["mode"] = "diag_only";
  String out;
  serializeJson(response, out);
  http_.send(200, "application/json", out);
}

void ApiServer::appendLogLine(const String& line) {
  String entry = line;
  entry.replace('\r', ' ');
  entry.replace('\n', ' ');
  if (entry.length() > 220) {
    entry = entry.substring(0, 220);
  }
  const String stamped = String(millis()) + "|" + entry;
  logs_[logsHead_] = stamped;
  logsHead_ = (uint8_t)((logsHead_ + 1U) % kLogRingSize);
  if (logsCount_ < kLogRingSize) logsCount_++;
}

int ApiServer::findDeviceSlot(uint32_t deviceId) const {
  for (int i = 0; i < kMaxTrackedDevices; ++i) {
    if (devices_[i].used && devices_[i].deviceId == deviceId) return i;
  }
  return -1;
}

int ApiServer::allocateDeviceSlot(uint32_t deviceId) {
  for (int i = 0; i < kMaxTrackedDevices; ++i) {
    if (!devices_[i].used) {
      devices_[i] = DeviceState{};
      devices_[i].used = true;
      devices_[i].deviceId = deviceId;
      return i;
    }
  }
  const int idx = nextDeviceReplace_ % kMaxTrackedDevices;
  nextDeviceReplace_ = (uint8_t)((nextDeviceReplace_ + 1U) % kMaxTrackedDevices);
  devices_[idx] = DeviceState{};
  devices_[idx].used = true;
  devices_[idx].deviceId = deviceId;
  return idx;
}

void ApiServer::updateDeviceFromPacket(const String& json) {
  StaticJsonDocument<768> packet;
  if (deserializeJson(packet, json) != DeserializationError::Ok) return;

  uint32_t deviceId = 0;
  if (!parseDeviceId(packet["device_id"], deviceId)) return;

  int idx = findDeviceSlot(deviceId);
  if (idx < 0) idx = allocateDeviceSlot(deviceId);
  DeviceState& device = devices_[idx];

  device.deviceId = deviceId;
  device.lastSeenMs = millis();

  if (packet["seq"].is<uint32_t>() || packet["seq"].is<int>()) {
    device.seq = packet["seq"].as<uint32_t>();
  }
  if (packet["timestamp"].is<uint32_t>() || packet["timestamp"].is<int>()) {
    device.timestamp = packet["timestamp"].as<uint32_t>();
  }
  if (packet["msg_type"].is<int>()) {
    device.msgType = packet["msg_type"].as<int>();
  }
  if (packet["ok"].is<bool>()) {
    device.hasCommandOk = true;
    device.commandOk = packet["ok"].as<bool>();
  }

  copyToBuffer(device.type, sizeof(device.type), packet["type"] | "");
  copyToBuffer(
      device.gatewayId, sizeof(device.gatewayId), packet["gateway_id"] | "");

  const char* payloadText = packet["payload"] | "";
  if (!payloadText || !payloadText[0]) return;

  StaticJsonDocument<384> payload;
  if (deserializeJson(payload, payloadText) != DeserializationError::Ok) return;

  double lat = 0.0;
  double lon = 0.0;
  bool hasLatLon = parseCoordinate(payload["lat"], lat) &&
                   parseCoordinate(payload["lon"], lon);

  if (!hasLatLon && payload["gps"].is<JsonObjectConst>()) {
    const JsonObjectConst gps = payload["gps"].as<JsonObjectConst>();
    hasLatLon =
        parseCoordinate(gps["lat"], lat) && parseCoordinate(gps["lon"], lon);
  }

  if (!hasLatLon) return;
  if (lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0) return;

  device.lat = (float)lat;
  device.lon = (float)lon;
  device.hasLocation = true;
}

void ApiServer::handleDevicesRequest() {
  int limit = kMaxTrackedDevices;
  if (http_.hasArg("limit")) {
    const int parsed = http_.arg("limit").toInt();
    if (parsed > 0 && parsed < limit) {
      limit = parsed;
    }
  }

  uint8_t order[kMaxTrackedDevices];
  uint8_t count = 0;
  for (uint8_t i = 0; i < kMaxTrackedDevices; ++i) {
    if (!devices_[i].used) continue;
    order[count++] = i;
  }

  for (uint8_t i = 0; i < count; ++i) {
    for (uint8_t j = i + 1; j < count; ++j) {
      if (devices_[order[j]].lastSeenMs > devices_[order[i]].lastSeenMs) {
        const uint8_t tmp = order[i];
        order[i] = order[j];
        order[j] = tmp;
      }
    }
  }

  const uint8_t take = (count < (uint8_t)limit) ? count : (uint8_t)limit;
  DynamicJsonDocument outDoc(4096);
  JsonArray arr = outDoc.to<JsonArray>();
  const uint32_t now = millis();

  for (uint8_t i = 0; i < take; ++i) {
    const DeviceState& device = devices_[order[i]];
    JsonObject item = arr.createNestedObject();
    item["device_id"] = device.deviceId;
    item["last_seen_ms"] = device.lastSeenMs;
    item["age_ms"] = now - device.lastSeenMs;
    item["online"] = (now - device.lastSeenMs) <= 120000UL;
    item["seq"] = device.seq;
    item["timestamp"] = device.timestamp;
    if (device.msgType >= 0) item["msg_type"] = device.msgType;
    if (device.type[0]) item["type"] = device.type;
    if (device.gatewayId[0]) item["gateway_id"] = device.gatewayId;
    if (device.hasLocation) {
      item["lat"] = device.lat;
      item["lon"] = device.lon;
    }
    if (device.hasCommandOk) {
      item["last_command_ok"] = device.commandOk;
    }
  }

  String out;
  serializeJson(outDoc, out);
  http_.send(200, "application/json", out);
}

void ApiServer::handleLogsRequest() {
  int limit = 30;
  if (http_.hasArg("limit")) {
    const int parsed = http_.arg("limit").toInt();
    if (parsed > 0) limit = parsed;
  }
  if (limit > kLogRingSize) limit = kLogRingSize;

  if (logsCount_ == 0) {
    http_.send(200, "text/plain", "Sem logs em memoria.\n");
    return;
  }

  const int start = (logsHead_ + kLogRingSize - logsCount_) % kLogRingSize;
  const int skip = (logsCount_ > limit) ? (logsCount_ - limit) : 0;
  String out;
  out.reserve((size_t)limit * 96U);

  for (int i = 0; i < logsCount_; ++i) {
    if (i < skip) continue;
    const int idx = (start + i) % kLogRingSize;
    out += logs_[idx];
    out += '\n';
  }

  http_.send(200, "text/plain", out);
}

void ApiServer::onWsEvent(
    uint8_t num, WStype_t type, uint8_t* payload, size_t length) {
  if (type == WStype_CONNECTED) {
    appendLogLine(String("WS_CONNECTED|client=") + String(num));
    ws_.sendTXT(num, "{\"type\":\"hello\",\"status\":\"connected\"}");
  } else if (type == WStype_TEXT) {
    const String incoming = String((char*)payload).substring(0, length);
    appendLogLine(String("WS_IN|") + incoming);
    queue_[head_] = incoming;
    head_ = (uint8_t)((head_ + 1U) % kCommandQueueSize);
    if (head_ == tail_) {
      tail_ = (uint8_t)((tail_ + 1U) % kCommandQueueSize);
    }
  }
}

void ApiServer::loop() {
  if (cfg::FEATURE_HTTP) http_.handleClient();
  if (cfg::FEATURE_WS) ws_.loop();
}

void ApiServer::broadcastTelemetry(const String& json) {
  appendLogLine(String("WS_OUT|") + json);
  updateDeviceFromPacket(json);
  String payload = json;
  ws_.broadcastTXT(payload);
}

bool ApiServer::hasPendingCommand() const { return head_ != tail_; }

bool ApiServer::popCommand(StaticJsonDocument<4096>& out) {
  if (!hasPendingCommand()) return false;
  String s = queue_[tail_];
  tail_ = (uint8_t)((tail_ + 1U) % kCommandQueueSize);
  return deserializeJson(out, s) == DeserializationError::Ok;
}
