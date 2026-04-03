/**
 * @file gateway.ino
 * @brief Firmware gateway matriz RuralTech: LoRa seguro + REST/WS + SD log + OLED.
 * @version 1.0.0
 * @date 2026-02-21
 */
#if !defined(ARDUINO_PARTITION_min_spiffs)
#error "Selecione Partition Scheme: Minimal SPIFFS (1.9MB APP with OTA/128KB SPIFFS)."
#endif

#include <Arduino.h>
#include <ctype.h>
#include <cstring>
#include <math.h>
#include <WiFi.h>
#include <ArduinoOTA.h>
#include <WiFiClientSecure.h>
#include <Wire.h>
#include <SPI.h>
#include <ArduinoJson.h>
#include <esp_task_wdt.h>
#include <esp_system.h>
#include <esp_ota_ops.h>
#include <time.h>
#if __has_include(<esp_idf_version.h>)
#include <esp_idf_version.h>
#endif
#include "config.h"
#if RT_MATRIX_OLED_ENABLED
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#endif
#include <RTClib.h>
#include <Preferences.h>
#include "Logger.h"
#include "BlePresence.h"
#include "LoRaGateway.h"
#include "SdLogger.h"
#include "ApiServer.h"
#include "../firmware/shared/command_contract.h"

LoRaGateway lora;
BlePresence blePresence;
SdLogger sdlog;
ApiServer api;
RTC_DS3231 rtc;
#if RT_MATRIX_OLED_ENABLED
Adafruit_SSD1306 display(128, 64, &Wire, -1);
#endif
uint32_t seqDown = 1;
Preferences seqPrefs;
Preferences bindingPrefs;
bool seqPrefsReady = false;
bool bindingPrefsReady = false;
bool wifiOtaEnabled = cfg::WIFI_OTA_DEFAULT_ENABLED;
bool watchdogTaskRegistered = false;
bool otaUploadInProgress = false;
bool wifiApRunning = false;
uint32_t wifiRecoveryAttemptAtMs = 0;
uint8_t wifiRecoveryAttemptCount = 0;
uint32_t cloudBackhaulAttemptAtMs = 0;
uint32_t cloudLastPublishAtMs = 0;
bool cloudBackhaulConnecting = false;
uint32_t cloudBackhaulConnectStartedAtMs = 0;
wifi_err_reason_t cloudBackhaulLastDisconnectReason = WIFI_REASON_UNSPECIFIED;
uint32_t cloudBackhaulLastDiagScanAtMs = 0;
uint32_t queuePollAtMs = 0;
uint64_t lastQueuePollAtUnixMs = 0;
uint32_t runtimeMirrorPublishAtMs = 0;
char bindingPropertyId[48]{};
char bindingPropertyScopeId[17]{};
char bindingMatrixGatewayId[32]{};
uint32_t bindingVersion = 0;
bool bindingReady = false;
bool supportsScopedLora = true;
char lastCloudWriteError[96]{};

struct HerdPoint {
  double lat = 0.0;
  double lon = 0.0;
};

struct HerdingOperationDeviceState {
  uint32_t deviceId = 0;
  uint32_t lastDispatchAtMs = 0;
  uint32_t updatedAtMs = 0;
  uint32_t assembledAtSec = 0;
  uint32_t completedAtSec = 0;
  uint16_t retryCount = 0;
  uint8_t phaseIndex = 0;
  char lastReason[32]{};
  bool assembled = false;
  bool completed = false;
};

struct HerdingOperationState {
  bool active = false;
  bool finalized = false;
  uint32_t startedAtMs = 0;
  uint32_t updatedAtMs = 0;
  uint32_t lastStatusPublishAtMs = 0;
  uint32_t requestedAtSec = 0;
  uint32_t completedAtSec = 0;
  uint8_t pointCount = 0;
  uint8_t deviceCount = 0;
  uint64_t createdAtMs = 0;
  uint64_t expiresAtMs = 0;
  char operationId[48]{};
  char propertyId[48]{};
  char ownerUid[48]{};
  char requestedByUid[48]{};
  char requestedByRole[16]{};
  char matrixGatewayId[32]{};
  char propertyScopeId[17]{};
  char loraCommandId[48]{};
  char lastCommandStatus[20]{};
  char failureReason[48]{};
  HerdPoint targetPolygon[cfg::MAX_POLYGON_POINTS]{};
  HerdingOperationDeviceState devices[cfg::MAX_HERD_OPERATION_DEVICES]{};
} herdOp;

struct ActiveSimpleCommandTargetState {
  char targetId[32]{};
  bool terminal = false;
  bool ok = false;
  char status[20]{};
  char reason[48]{};
};

struct ActiveSimpleCommandState {
  bool active = false;
  uint32_t dispatchAtMs = 0;
  uint64_t createdAtMs = 0;
  uint64_t expiresAtMs = 0;
  uint8_t targetCount = 0;
  char commandId[48]{};
  char command[24]{};
  char propertyId[48]{};
  char propertyScopeId[17]{};
  char matrixGatewayId[32]{};
  char requestedByUid[48]{};
  char requestedByRole[16]{};
  ActiveSimpleCommandTargetState targets[cfg::MAX_HERD_OPERATION_DEVICES]{};
} activeSimpleCommand;

struct CloudPublishContext {
  uint32_t nowSec = 0;
  uint64_t nowMs = 0;
  String matrixId;
  String deviceId;
  String propertyId;
  String propertyScopeId;
};

static void setWatchdogEnabled(bool enabled);
static void feedWatchdogIfEnabled();
static void printBootChecklist(
    bool displayOk,
    bool wifiOk,
    bool bleInitOk,
    bool rtcOk,
    bool sdOk,
    bool loraOk,
    bool cloudConfigured);
static void copyStringToBuffer(char* dst, size_t dstSize, const char* src);
static void loadBindingConfig();
static bool persistBindingConfig(
    const JsonVariantConst payload,
    const char** reason = nullptr);
static bool startHerdingOperation(const JsonVariantConst payload, const char** reason);
static void dispatchActiveHerdingOperation();
static void handleHerdingOperationFeedback(const LoRaFrame& rx);
static void handleHerdingOperationEvent(const LoRaFrame& rx);
static void handleSimpleCommandFeedback(const LoRaFrame& rx);
static void processNextQueuedCommand();
static void publishHerdingOperationSnapshot(
    bool force = false,
    const char* statusOverride = nullptr);
static bool ensureCloudBackhaulConnected();
static bool publishMatrixRuntimeMirrors(bool force = false);

static const char* otaErrorText(ota_error_t error) {
  switch (error) {
    case OTA_AUTH_ERROR: return "auth";
    case OTA_BEGIN_ERROR: return "begin";
    case OTA_CONNECT_ERROR: return "connect";
    case OTA_RECEIVE_ERROR: return "receive";
    case OTA_END_ERROR: return "end";
    default: return "unknown";
  }
}

static const char* wifiStatusLabel(wl_status_t status) {
  switch (status) {
    case WL_NO_SHIELD: return "no_shield";
    case WL_IDLE_STATUS: return "idle";
    case WL_NO_SSID_AVAIL: return "no_ssid";
    case WL_SCAN_COMPLETED: return "scan_completed";
    case WL_CONNECTED: return "connected";
    case WL_CONNECT_FAILED: return "connect_failed";
    case WL_CONNECTION_LOST: return "connection_lost";
    case WL_DISCONNECTED: return "disconnected";
    case WL_STOPPED: return "stopped";
    default: return "unknown";
  }
}

static const char* wifiDisconnectReasonLabel(wifi_err_reason_t reason) {
  const char* label = WiFi.disconnectReasonName(reason);
  return (label != nullptr && label[0] != '\0') ? label : "unknown";
}

static const char* wifiAuthModeLabel(wifi_auth_mode_t authMode) {
  switch (authMode) {
    case WIFI_AUTH_OPEN: return "OPEN";
    case WIFI_AUTH_WEP: return "WEP";
    case WIFI_AUTH_WPA_PSK: return "WPA_PSK";
    case WIFI_AUTH_WPA2_PSK: return "WPA2_PSK";
    case WIFI_AUTH_WPA_WPA2_PSK: return "WPA_WPA2_PSK";
    case WIFI_AUTH_WPA2_ENTERPRISE: return "WPA2_ENTERPRISE";
    case WIFI_AUTH_WPA3_PSK: return "WPA3_PSK";
    case WIFI_AUTH_WPA2_WPA3_PSK: return "WPA2_WPA3_PSK";
    case WIFI_AUTH_WAPI_PSK: return "WAPI_PSK";
    case WIFI_AUTH_OWE: return "OWE";
    case WIFI_AUTH_WPA3_ENT_192: return "WPA3_ENT_192";
    default: return "UNKNOWN";
  }
}

static void logBackhaulScanDiagnostics(uint32_t now) {
  if (cloudBackhaulLastDiagScanAtMs != 0 &&
      (uint32_t)(now - cloudBackhaulLastDiagScanAtMs) <
          cfg::CLOUD_BACKHAUL_DIAG_SCAN_INTERVAL_MS) {
    return;
  }
  cloudBackhaulLastDiagScanAtMs = now;

  LOGI("Backhaul Wi-Fi: escaneando SSID alvo=%s", cfg::BACKHAUL_WIFI_SSID);
  const int16_t networkCount = WiFi.scanNetworks(false, true);
  if (networkCount < 0) {
    LOGW("Backhaul Wi-Fi: scan falhou codigo=%d", (int)networkCount);
    WiFi.scanDelete();
    return;
  }

  uint8_t matchCount = 0;
  for (int16_t i = 0; i < networkCount; ++i) {
    const String ssid = WiFi.SSID((uint8_t)i);
    if (ssid != cfg::BACKHAUL_WIFI_SSID) continue;
    matchCount++;
    LOGI(
        "Backhaul scan alvo[%u/%d]: bssid=%s canal=%d rssi=%d auth=%s(%d)",
        (unsigned)matchCount,
        (int)networkCount,
        WiFi.BSSIDstr((uint8_t)i).c_str(),
        (int)WiFi.channel((uint8_t)i),
        (int)WiFi.RSSI((uint8_t)i),
        wifiAuthModeLabel(WiFi.encryptionType((uint8_t)i)),
        (int)WiFi.encryptionType((uint8_t)i));
  }

  if (matchCount == 0) {
    LOGW("Backhaul scan: SSID alvo %s nao apareceu entre %d redes visiveis",
         cfg::BACKHAUL_WIFI_SSID, (int)networkCount);
  }
  WiFi.scanDelete();
}

static void logOtaPartitionInfo(const char* context) {
  const esp_partition_t* running = esp_ota_get_running_partition();
  const esp_partition_t* next = esp_ota_get_next_update_partition(NULL);
  LOGI("OTA particoes (%s): running=%s size=0x%lx next=%s size=0x%lx",
       context ? context : "-",
       running ? running->label : "null",
       running ? (unsigned long)running->size : 0UL,
       next ? next->label : "null",
       next ? (unsigned long)next->size : 0UL);
  if (!next) {
    LOGE("OTA sem particao de update. Grave 1x via USB com Partition Scheme OTA (min_spiffs).");
  }
}

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

static String gatewayNodeId() {
  String id = compactIdentifier(WiFi.softAPmacAddress());
  if (id.isEmpty()) id = compactIdentifier(WiFi.macAddress());
  return id;
}

static String gatewayAdvName(const String& nodeId) {
  if (nodeId.isEmpty()) return String(cfg::BLE_DEVICE_PREFIX);
  const String suffix =
      nodeId.length() > 6 ? nodeId.substring(nodeId.length() - 6) : nodeId;
  return String(cfg::BLE_DEVICE_PREFIX) + "-" + suffix;
}

static String gatewayApSsid() {
  String suffix = gatewayNodeId();
  if (suffix.length() > 6) suffix = suffix.substring(suffix.length() - 6);
  String ssid = String(cfg::AP_SSID) + "-" + suffix;
  if (ssid.length() > 31) ssid = ssid.substring(0, 31);
  return ssid;
}

static void copyStringToBuffer(char* dst, size_t dstSize, const char* src) {
  if (dstSize == 0) return;
  if (src == nullptr) {
    dst[0] = '\0';
    return;
  }
  strncpy(dst, src, dstSize - 1);
  dst[dstSize - 1] = '\0';
}

static String scopeIdToHex(uint64_t scopeId) {
  char out[17];
  snprintf(out, sizeof(out), "%016llX", (unsigned long long)scopeId);
  return String(out);
}

static const char* pickFirstText(
    const JsonVariantConst a,
    const JsonVariantConst b = JsonVariantConst(),
    const JsonVariantConst c = JsonVariantConst(),
    const JsonVariantConst d = JsonVariantConst()) {
  const JsonVariantConst values[] = {a, b, c, d};
  for (const JsonVariantConst value : values) {
    if (!value.is<const char*>()) continue;
    const char* text = value.as<const char*>();
    if (text && text[0] != '\0') return text;
  }
  return "";
}

static bool beginBindingPrefs() {
  if (bindingPrefsReady) return true;
  bindingPrefsReady = bindingPrefs.begin("binding", false);
  if (!bindingPrefsReady) LOGW("Falha ao abrir NVS binding");
  return bindingPrefsReady;
}

static bool computeBindingReadyState() {
  return bindingPropertyId[0] != '\0' &&
         bindingMatrixGatewayId[0] != '\0' &&
         rtcmd::isValidScopeId(bindingPropertyScopeId);
}

static uint64_t bindingScopeIdValue() {
  if (!computeBindingReadyState()) return 0;
  return strtoull(bindingPropertyScopeId, nullptr, 16);
}

static void loadBindingConfig() {
  bindingPropertyId[0] = '\0';
  bindingPropertyScopeId[0] = '\0';
  bindingMatrixGatewayId[0] = '\0';
  bindingVersion = 0;
  bindingReady = false;
  if (!beginBindingPrefs()) return;

  bindingPrefs.getString("property_id", bindingPropertyId, sizeof(bindingPropertyId));
  bindingPrefs.getString("scope_id", bindingPropertyScopeId, sizeof(bindingPropertyScopeId));
  bindingPrefs.getString("matrix_gid", bindingMatrixGatewayId, sizeof(bindingMatrixGatewayId));
  bindingVersion = bindingPrefs.getUInt("bind_ver", 0);
  bindingReady = computeBindingReadyState();
  LOGI(
      "Binding matriz: ready=%d property=%s scope=%s matrix=%s ver=%lu",
      bindingReady ? 1 : 0,
      bindingPropertyId[0] ? bindingPropertyId : "-",
      bindingPropertyScopeId[0] ? bindingPropertyScopeId : "-",
      bindingMatrixGatewayId[0] ? bindingMatrixGatewayId : "-",
      (unsigned long)bindingVersion);
}

static bool persistBindingConfig(const JsonVariantConst payload, const char** reason) {
  const char* propertyId = pickFirstText(payload["property_id"], payload["propertyId"]);
  const char* propertyScopeId = pickFirstText(
      payload["property_scope_id"], payload["propertyScopeId"], payload["scope_id"]);
  const char* matrixGatewayId = pickFirstText(
      payload["matrix_gateway_id"], payload["matrixGatewayId"]);
  uint32_t nextBindingVersion =
      payload["binding_version"].is<uint32_t>()
          ? payload["binding_version"].as<uint32_t>()
          : (payload["bindingVersion"] | 1U);

  if (!propertyId[0]) {
    if (reason) *reason = "missing_property_id";
    return false;
  }
  if (!rtcmd::isValidScopeId(propertyScopeId)) {
    if (reason) *reason = "invalid_property_scope_id";
    return false;
  }
  if (!matrixGatewayId[0]) {
    if (reason) *reason = "missing_matrix_gateway_id";
    return false;
  }
  if (nextBindingVersion == 0) nextBindingVersion = 1;
  if (!beginBindingPrefs()) {
    if (reason) *reason = "binding_prefs_unavailable";
    return false;
  }

  copyStringToBuffer(bindingPropertyId, sizeof(bindingPropertyId), propertyId);
  copyStringToBuffer(
      bindingPropertyScopeId, sizeof(bindingPropertyScopeId), propertyScopeId);
  copyStringToBuffer(
      bindingMatrixGatewayId, sizeof(bindingMatrixGatewayId), matrixGatewayId);
  bindingVersion = nextBindingVersion;
  bindingReady = computeBindingReadyState();

  bindingPrefs.putString("property_id", bindingPropertyId);
  bindingPrefs.putString("scope_id", bindingPropertyScopeId);
  bindingPrefs.putString("matrix_gid", bindingMatrixGatewayId);
  bindingPrefs.putUInt("bind_ver", bindingVersion);
  return bindingReady;
}

static bool scopeMatchesBinding(uint64_t scopeId) {
  return bindingReady && scopeId != 0 && scopeId == bindingScopeIdValue();
}

static void restoreDownlinkSeq() {
  seqDown = 1;
  seqPrefsReady = seqPrefs.begin("lora_down", false);
  if (!seqPrefsReady) {
    LOGW("NVS indisponivel para seqDown; iniciando em 1.");
    return;
  }

  if (!seqPrefs.isKey("seq")) {
    // Primeiro boot apos update: evita colisao com lastSeqSeen_ ja alto na coleira.
    seqDown = (esp_random() & 0x7FFFFFFFUL) | 0x40000000UL;
    if (seqPrefs.putULong("seq", seqDown - 1) != sizeof(uint32_t)) {
      LOGW("Falha ao inicializar persistencia de seqDown=%lu", seqDown);
    }
    LOGI("seqDown inicializado=%lu (seed aleatorio)", seqDown);
    return;
  }

  const uint32_t persisted = seqPrefs.getULong("seq", seqDown - 1);
  seqDown = persisted + 1;
  if (seqDown == 0) seqDown = 1;
  LOGI("seqDown restaurado=%lu (persistido=%lu)", seqDown, persisted);
}

static uint32_t nextDownlinkSeq() {
  if (seqDown == 0) seqDown = 1;
  const uint32_t out = seqDown++;
  if (seqDown == 0) seqDown = 1;

  if (seqPrefsReady && seqPrefs.putULong("seq", out) != sizeof(uint32_t)) {
    LOGW("Falha ao persistir seqDown=%lu", out);
  }
  return out;
}

static String sanitizeRtdbKey(String value) {
  value.trim();
  if (value.isEmpty()) return value;
  value.replace('.', '_');
  value.replace('#', '_');
  value.replace('$', '_');
  value.replace('[', '_');
  value.replace(']', '_');
  value.replace('/', '_');
  return value;
}

static bool isUnsetCloudValue(const char* value) {
  if (value == nullptr) return true;
  while (*value == ' ' || *value == '\t' || *value == '\r' || *value == '\n') {
    ++value;
  }
  if (*value == '\0') return true;
  return strncmp(value, "SET_", 4) == 0 ||
         strncmp(value, "CHANGE_ME", 9) == 0 ||
         strncmp(value, "YOUR_", 5) == 0;
}

static bool cloudTelemetryConfigured() {
  if (!cfg::FEATURE_CLOUD) return false;

  const bool backhaulSsidOk = !isUnsetCloudValue(cfg::BACKHAUL_WIFI_SSID);
  const bool backhaulPassOk =
      cfg::BACKHAUL_WIFI_PASS[0] == '\0' || !isUnsetCloudValue(cfg::BACKHAUL_WIFI_PASS);
  const bool hostOk = !isUnsetCloudValue(cfg::FIREBASE_RTDB_HOST);
  const bool matrixIdOk =
      cfg::RTDB_MATRIX_ID[0] == '\0' || !isUnsetCloudValue(cfg::RTDB_MATRIX_ID);
  const bool writerKeyOk = !isUnsetCloudValue(cfg::RTDB_WRITER_KEY);
  const bool configured =
      backhaulSsidOk && backhaulPassOk && hostOk && matrixIdOk && writerKeyOk;

  static bool warned = false;
  if (!configured && !warned) {
    LOGW("Cloud telemetry desativada: substitua placeholders SET_* em manual_settings.local.h");
    warned = true;
  } else if (configured && warned) {
    warned = false;
  }
  return configured;
}

static String matrixCloudId() {
  if (cfg::RTDB_MATRIX_ID[0] != '\0' && !isUnsetCloudValue(cfg::RTDB_MATRIX_ID)) {
    return sanitizeRtdbKey(String(cfg::RTDB_MATRIX_ID));
  }
  return sanitizeRtdbKey(gatewayNodeId());
}

static uint64_t parseScopeIdHex(const JsonVariantConst value) {
  const char* text = value.is<const char*>() ? value.as<const char*>() : "";
  if (!text || !text[0] || !rtcmd::isValidScopeId(text)) return 0;
  return strtoull(text, nullptr, 16);
}

static uint32_t unixNowSec() {
  const time_t wall = time(nullptr);
  if (wall > 1700000000) return (uint32_t)wall;
  const DateTime nowRtc = rtc.now();
  if (nowRtc.year() >= 2023) return nowRtc.unixtime();
  return millis() / 1000;
}

static uint64_t unixNowMs(uint32_t unixSec) {
  // Mantem alinhamento com unixNowSec() e adiciona granularidade sub-segundo.
  return ((uint64_t)unixSec * 1000ULL) + (uint64_t)(millis() % 1000UL);
}

static String utcDayKey(uint32_t unixSec) {
  time_t raw = (time_t)unixSec;
  struct tm tmUtc;
  gmtime_r(&raw, &tmUtc);
  char out[9];
  snprintf(out, sizeof(out), "%04d%02d%02d", tmUtc.tm_year + 1900,
           tmUtc.tm_mon + 1, tmUtc.tm_mday);
  return String(out);
}

static bool rtdbRequest(
    const char* method,
    const String& path,
    const String& body,
    String* responseBody = nullptr) {
  if (WiFi.status() != WL_CONNECTED) {
    setLastCloudWriteError("wifi", path);
    return false;
  }
  if (path.isEmpty()) {
    setLastCloudWriteError("path", "-");
    return false;
  }

  WiFiClientSecure client;
  client.setInsecure();
  client.setTimeout(cfg::CLOUD_HTTP_TIMEOUT_MS);
  if (!client.connect(cfg::FIREBASE_RTDB_HOST, 443)) {
    setLastCloudWriteError("connect", path);
    return false;
  }

  const String reqPath = String("/") + path + ".json";
  const size_t bodyLen = body.length();
  client.print(method);
  client.print(" ");
  client.print(reqPath);
  client.print(" HTTP/1.1\r\nHost: ");
  client.print(cfg::FIREBASE_RTDB_HOST);
  client.print("\r\nUser-Agent: ruraltech-matrix\r\nConnection: close\r\nContent-Type: application/json\r\nContent-Length: ");
  client.print((unsigned long)bodyLen);
  client.print("\r\n\r\n");
  if (bodyLen > 0) client.print(body);

  const String statusLine = client.readStringUntil('\n');
  bool ok = false;
  if (statusLine.startsWith("HTTP/1.1 2") || statusLine.startsWith("HTTP/1.0 2")) {
    ok = true;
  }

  while (client.connected()) {
    const String line = client.readStringUntil('\n');
    if (line == "\r" || line.length() == 0) break;
  }
  if (responseBody) {
    *responseBody = client.readString();
  }

  const uint32_t drainStart = millis();
  while ((uint32_t)(millis() - drainStart) < 250) {
    while (client.available()) {
      client.read();
    }
    if (!client.connected()) break;
    delay(1);
  }
  client.stop();
  if (ok) {
    clearLastCloudWriteError();
  } else {
    setLastCloudWriteError("http", path + "|" + statusLine);
  }
  return ok;
}

static bool rtdbWrite(const char* method, const String& path, const String& body) {
  return rtdbRequest(method, path, body, nullptr);
}

static bool rtdbRead(const String& path, String& body) {
  body = "";
  return rtdbRequest("GET", path, "", &body);
}

static bool rtdbDelete(const String& path) {
  return rtdbRequest("DELETE", path, "", nullptr);
}

static void setLastCloudWriteError(const char* stage, const String& detail) {
  const char* safeStage = (stage && stage[0] != '\0') ? stage : "cloud";
  const String safeDetail = detail.isEmpty() ? String("-") : detail;
  snprintf(
      lastCloudWriteError,
      sizeof(lastCloudWriteError),
      "%s:%s",
      safeStage,
      safeDetail.substring(0, 72).c_str());
}

static void clearLastCloudWriteError() {
  lastCloudWriteError[0] = '\0';
}

static bool appendPropertyCommandEvent(
    const char* propertyId,
    const char* commandId,
    const char* status,
    const char* reason,
    const DynamicJsonDocument* sourceDoc = nullptr) {
  if (!cfg::FEATURE_CLOUD) return false;
  if (!propertyId || !propertyId[0] || !commandId || !commandId[0] || !status ||
      !status[0]) {
    return false;
  }

  DynamicJsonDocument doc(1024);
  doc["type"] = status;
  doc["status"] = status;
  doc["matrixId"] = matrixCloudId();
  doc["matrixGatewayId"] = bindingMatrixGatewayId;
  doc["createdAtMs"] = unixNowMs(unixNowSec());
  doc["writer"] = "gateway_matrix";
  doc["writerKey"] = cfg::RTDB_WRITER_KEY;
  if (reason && reason[0]) doc["reason"] = reason;
  if (sourceDoc && (*sourceDoc)["deviceResults"].is<JsonObjectConst>()) {
    doc["deviceResults"] = (*sourceDoc)["deviceResults"].as<JsonObjectConst>();
  }

  String body;
  serializeJson(doc, body);
  char eventId[72];
  snprintf(
      eventId,
      sizeof(eventId),
      "%llu_%s_%lu",
      (unsigned long long)unixNowMs(unixNowSec()),
      status,
      (unsigned long)esp_random());
  return rtdbWrite(
      "PUT",
      String("propertyCommandEvents/") + sanitizeRtdbKey(String(propertyId)) + "/" +
          commandId + "/" + eventId,
      body);
}

static bool cloudPublishReady() {
  return cloudTelemetryConfigured() && ensureCloudBackhaulConnected();
}

static bool publishMatrixRuntimeMirrors(bool force) {
  if (!cloudTelemetryConfigured()) return false;
  if (!ensureCloudBackhaulConnected()) return false;

  const uint32_t nowTick = millis();
  if (!force && runtimeMirrorPublishAtMs != 0 &&
      (uint32_t)(nowTick - runtimeMirrorPublishAtMs) < 30000UL) {
    return true;
  }

  const String runtimeId = matrixCloudId();
  const uint64_t nowMs = unixNowMs(unixNowSec());
  DynamicJsonDocument bindingDoc(640);
  bindingDoc["propertyId"] = bindingPropertyId;
  bindingDoc["propertyScopeId"] = bindingPropertyScopeId;
  bindingDoc["matrixGatewayId"] = bindingMatrixGatewayId;
  bindingDoc["matrixRuntimeId"] = runtimeId;
  bindingDoc["enabled"] = bindingReady && supportsScopedLora;
  bindingDoc["updatedAtMs"] = nowMs;
  bindingDoc["writer"] = "gateway_matrix";
  bindingDoc["writerKey"] = cfg::RTDB_WRITER_KEY;
  String bindingBody;
  serializeJson(bindingDoc, bindingBody);

  const String runtimeBindingPath = String("matrixBindings/") + runtimeId;
  bool ok = rtdbWrite("PUT", runtimeBindingPath, bindingBody);
  if (!ok) {
    setLastCloudWriteError("binding", runtimeBindingPath);
    return false;
  }

  const String gatewayAlias = sanitizeRtdbKey(gatewayNodeId());
  if (!gatewayAlias.isEmpty() && gatewayAlias != runtimeId) {
    ok = rtdbWrite("PUT", String("matrixBindings/") + gatewayAlias, bindingBody) && ok;
  }
  const String matrixAlias = sanitizeRtdbKey(String(bindingMatrixGatewayId));
  if (!matrixAlias.isEmpty() && matrixAlias != runtimeId && matrixAlias != gatewayAlias) {
    ok = rtdbWrite("PUT", String("matrixBindings/") + matrixAlias, bindingBody) && ok;
  }

  if (!isUnsetCloudValue(cfg::RTDB_QUEUE_KEY)) {
    DynamicJsonDocument queueDoc(384);
    queueDoc["queueKey"] = cfg::RTDB_QUEUE_KEY;
    queueDoc["matrixRuntimeId"] = runtimeId;
    queueDoc["updatedAtMs"] = nowMs;
    queueDoc["writer"] = "gateway_matrix";
    queueDoc["writerKey"] = cfg::RTDB_WRITER_KEY;
    String queueBody;
    serializeJson(queueDoc, queueBody);
    const String queuePath = String("matrixQueueKeys/") + runtimeId;
    ok = rtdbWrite("PUT", queuePath, queueBody) && ok;
    if (!ok) {
      setLastCloudWriteError("queue_key", queuePath);
      return false;
    }
  }

  runtimeMirrorPublishAtMs = nowTick;
  clearLastCloudWriteError();
  return ok;
}

static bool buildCloudPublishContext(const LoRaFrame& rx, CloudPublishContext& ctx) {
  if (!scopeMatchesBinding(rx.scopeId)) return false;
  ctx.nowSec = unixNowSec();
  ctx.nowMs = unixNowMs(ctx.nowSec);
  ctx.matrixId = matrixCloudId();
  ctx.deviceId = sanitizeRtdbKey(String(rx.deviceId));
  ctx.propertyId = sanitizeRtdbKey(String(bindingPropertyId));
  ctx.propertyScopeId = String(bindingPropertyScopeId);
  return !ctx.deviceId.isEmpty() && !ctx.propertyId.isEmpty() &&
         rtcmd::isValidScopeId(ctx.propertyScopeId.c_str());
}

static void populateCommonCloudFields(
    JsonObject payload,
    const CloudPublishContext& ctx,
    const LoRaFrame& rx) {
  payload["seq"] = rx.seq;
  payload["sourceTimestampSec"] = rx.timestamp;
  payload["receivedAt"] = ctx.nowSec;
  payload["receivedAtMs"] = ctx.nowMs;
  payload["gatewayId"] = ctx.matrixId;
  payload["gatewayRole"] = "matrix";
  payload["gatewayWifiOtaEnabled"] = wifiOtaEnabled;
  payload["propertyId"] = ctx.propertyId;
  payload["propertyScopeId"] = ctx.propertyScopeId;
  payload["matrixGatewayId"] = bindingMatrixGatewayId;
  payload["scope_id"] = ctx.propertyScopeId;
  payload["transport"] = "lora";
  payload["writer"] = "gateway_matrix";
  payload["matrixId"] = ctx.matrixId;
  payload["writerKey"] = cfg::RTDB_WRITER_KEY;
  payload["retentionDays"] = cfg::TELEMETRY_RETENTION_DAYS;
  payload["expiresAt"] =
      ctx.nowSec + (uint32_t)cfg::TELEMETRY_RETENTION_DAYS * 24UL * 60UL * 60UL;
}

static bool publishCloudLatestAndHistory(
    const char* latestRoot,
    const char* historyRoot,
    const CloudPublishContext& ctx,
    const String& historyDayKey,
    const String& body,
    const char* logLabel,
    uint32_t entrySeq) {
  const String latestPath =
      String(latestRoot) + "/" + ctx.propertyId + "/" + ctx.deviceId;
  char historyEntryId[40];
  snprintf(historyEntryId, sizeof(historyEntryId), "%llu_%lu",
           (unsigned long long)ctx.nowMs, (unsigned long)entrySeq);
  const String historyPath =
      String(historyRoot) + "/" + ctx.propertyId + "/" + ctx.deviceId + "/" +
      historyDayKey + "/" + String(historyEntryId);

  const bool latestOk = rtdbWrite("PUT", latestPath, body);
  const bool historyOk = rtdbWrite("PUT", historyPath, body);
  if (latestOk && historyOk) {
    cloudLastPublishAtMs = millis();
  } else {
    LOGW("Falha upload RTDB %s device=%s latest=%d history=%d",
         logLabel, ctx.deviceId.c_str(), latestOk ? 1 : 0, historyOk ? 1 : 0);
  }
  return latestOk && historyOk;
}

static bool ensureCloudBackhaulConnected() {
  if (!cfg::FEATURE_BACKHAUL) return false;
  if (!cloudTelemetryConfigured()) return false;
  if (WiFi.status() == WL_CONNECTED) {
    cloudBackhaulConnecting = false;
    cloudBackhaulConnectStartedAtMs = 0;
    cloudBackhaulLastDisconnectReason = WIFI_REASON_UNSPECIFIED;
    return true;
  }

  const uint32_t now = millis();
  if (cloudBackhaulConnecting) {
    if (cloudBackhaulConnectStartedAtMs != 0 &&
        (uint32_t)(now - cloudBackhaulConnectStartedAtMs) <
            cfg::CLOUD_BACKHAUL_CONNECT_TIMEOUT_MS) {
      return false;
    }
    LOGW(
        "Backhaul Wi-Fi: tentativa expirou sem IP ssid=%s wl=%s(%d) ultimo_motivo=%s(%u); reiniciando STA",
        cfg::BACKHAUL_WIFI_SSID,
        wifiStatusLabel(WiFi.status()),
        (int)WiFi.status(),
        wifiDisconnectReasonLabel(cloudBackhaulLastDisconnectReason),
        (unsigned)cloudBackhaulLastDisconnectReason);
    logBackhaulScanDiagnostics(now);
    cloudBackhaulConnecting = false;
    cloudBackhaulConnectStartedAtMs = 0;
    WiFi.disconnect(false, false);
  }
  if (cloudBackhaulAttemptAtMs != 0 &&
      (uint32_t)(now - cloudBackhaulAttemptAtMs) < cfg::CLOUD_BACKHAUL_RETRY_MS) {
    return false;
  }
  cloudBackhaulAttemptAtMs = now;
  // Em modo OTA/manual, preserva AP local e sobe STA para backhaul cloud.
  const wifi_mode_t desiredMode =
      (cfg::FEATURE_WIFI_AP && wifiOtaEnabled) ? WIFI_AP_STA : WIFI_STA;
  if (WiFi.getMode() != desiredMode) {
    WiFi.mode(desiredMode);
  }
  WiFi.setSleep(false);
  cloudBackhaulConnecting = true;
  cloudBackhaulConnectStartedAtMs = now;
  cloudBackhaulLastDisconnectReason = WIFI_REASON_UNSPECIFIED;
  WiFi.begin(cfg::BACKHAUL_WIFI_SSID, cfg::BACKHAUL_WIFI_PASS);
  LOGI("Backhaul Wi-Fi: tentando conectar em %s", cfg::BACKHAUL_WIFI_SSID);
  return false;
}

static void publishTelemetryToCloud(const LoRaFrame& rx) {
  if (rx.msgType != MsgType::TELEMETRY) return;
  if (!cloudPublishReady()) return;

  StaticJsonDocument<256> telemetry;
  if (deserializeJson(telemetry, rx.payload, rx.payloadLen) != DeserializationError::Ok) {
    return;
  }

  const float lat = telemetry["lat"] | NAN;
  const float lon = telemetry["lon"] | NAN;
  if (!isfinite(lat) || !isfinite(lon) ||
      lat < -90.0f || lat > 90.0f || lon < -180.0f || lon > 180.0f) {
    return;
  }

  CloudPublishContext ctx;
  if (!buildCloudPublishContext(rx, ctx)) return;

  StaticJsonDocument<512> payload;
  payload["deviceId"] = ctx.deviceId;
  payload["lat"] = lat;
  payload["lon"] = lon;
  payload["mode"] = telemetry["mode"] | 0;
  payload["spd"] = telemetry["spd"] | 0.0f;
  payload["hdop"] = telemetry["hdop"] | 99.9f;
  payload["sat"] = telemetry["sat"] | 0;
  payload["rssi"] = telemetry["rssi"] | 0;
  payload["snr"] = telemetry["snr"] | 0.0f;
  populateCommonCloudFields(payload.as<JsonObject>(), ctx, rx);

  String body;
  serializeJson(payload, body);
  publishCloudLatestAndHistory(
      "propertyTelemetryLatest", "propertyTelemetryHistory", ctx, utcDayKey(ctx.nowSec), body,
      "telemetria", rx.seq);
}

static bool isDailyHealthEvent(const JsonVariantConst payload) {
  if (!payload.is<JsonObjectConst>()) return false;
  const char* type = payload["type"] | "";
  if (strcmp(type, "health_daily") == 0) return true;
  const char* eventType = payload["event_type"] | "";
  return strcmp(eventType, "health_daily") == 0;
}

static void publishDailyHealthToCloud(const LoRaFrame& rx) {
  if (rx.msgType != MsgType::EVENT) return;
  if (!cloudPublishReady()) return;

  StaticJsonDocument<256> eventPayload;
  if (deserializeJson(eventPayload, rx.payload, rx.payloadLen) != DeserializationError::Ok) {
    return;
  }
  if (!isDailyHealthEvent(eventPayload.as<JsonVariantConst>())) return;

  CloudPublishContext ctx;
  if (!buildCloudPublishContext(rx, ctx)) return;

  const uint32_t gpsDayKey = eventPayload["dk"] | 0UL;

  StaticJsonDocument<512> payload;
  payload["deviceId"] = ctx.deviceId;
  payload["kind"] = "health_daily";
  payload["healthFlags"] = eventPayload["hf"] | 0;
  payload["gpsDayKey"] = gpsDayKey;
  payload["uptimeSec"] = eventPayload["up"] | 0UL;
  payload["temperatureDeciC"] = eventPayload["tp"] | 0;
  payload["sat"] = eventPayload["sa"] | 0;
  payload["hdopCenti"] = eventPayload["hd"] | 0;
  payload["i2cDevices"] = eventPayload["i2"] | 0;
  populateCommonCloudFields(payload.as<JsonObject>(), ctx, rx);

  String body;
  serializeJson(payload, body);
  const String historyDayKey =
      gpsDayKey > 0 ? String(gpsDayKey) : utcDayKey(ctx.nowSec);
  publishCloudLatestAndHistory(
      "propertyHealthLatest", "propertyHealthHistory", ctx, historyDayKey, body, "health_daily",
      rx.seq);
}

static void publishEventToCloud(const LoRaFrame& rx) {
  if (rx.msgType != MsgType::EVENT) return;
  if (!cloudPublishReady()) return;

  DynamicJsonDocument eventPayload(768);
  if (deserializeJson(eventPayload, rx.payload, rx.payloadLen) != DeserializationError::Ok) {
    return;
  }

  CloudPublishContext ctx;
  if (!buildCloudPublishContext(rx, ctx)) return;

  DynamicJsonDocument payload(1024);
  payload["deviceId"] = ctx.deviceId;
  const char* eventType = pickFirstText(eventPayload["event_type"], eventPayload["type"]);
  if (!eventType[0]) eventType = "event";
  payload["eventType"] = eventType;
  payload["type"] = eventType;
  if (eventPayload["operation_id"].is<const char*>()) {
    payload["operationId"] = eventPayload["operation_id"].as<const char*>();
  }
  if (eventPayload["cmd_id"].is<const char*>()) {
    payload["cmd_id"] = eventPayload["cmd_id"].as<const char*>();
  }
  payload["payload"] = eventPayload.as<JsonVariantConst>();
  populateCommonCloudFields(payload.as<JsonObject>(), ctx, rx);

  String body;
  serializeJson(payload, body);
  char entryId[40];
  snprintf(entryId, sizeof(entryId), "%llu_%lu",
           (unsigned long long)ctx.nowMs, (unsigned long)rx.seq);
  const String eventPath =
      String("propertyEvents/") + ctx.propertyId + "/" + utcDayKey(ctx.nowSec) +
      "/" + String(entryId);
  if (!rtdbWrite("PUT", eventPath, body)) {
    LOGW("Falha upload RTDB event device=%s type=%s",
         ctx.deviceId.c_str(), eventType);
  }
}

static void clearActiveSimpleCommand() {
  activeSimpleCommand = ActiveSimpleCommandState{};
}

static int findActiveSimpleCommandTarget(const char* targetId) {
  if (!targetId || !targetId[0]) return -1;
  for (uint8_t i = 0; i < activeSimpleCommand.targetCount; ++i) {
    if (strcmp(activeSimpleCommand.targets[i].targetId, targetId) == 0) return (int)i;
  }
  return -1;
}

static bool allActiveSimpleTargetsTerminal() {
  if (!activeSimpleCommand.active || activeSimpleCommand.targetCount == 0) return false;
  for (uint8_t i = 0; i < activeSimpleCommand.targetCount; ++i) {
    if (!activeSimpleCommand.targets[i].terminal) return false;
  }
  return true;
}

static bool anyActiveSimpleTargetFailed() {
  for (uint8_t i = 0; i < activeSimpleCommand.targetCount; ++i) {
    if (activeSimpleCommand.targets[i].terminal && !activeSimpleCommand.targets[i].ok) {
      return true;
    }
  }
  return false;
}

static bool publishSimpleCommandResult(const char* status, const char* reason = nullptr) {
  if (!cfg::FEATURE_CLOUD) return false;
  if (!activeSimpleCommand.active || !activeSimpleCommand.commandId[0]) return false;

  DynamicJsonDocument doc(2048);
  doc["commandId"] = activeSimpleCommand.commandId;
  doc["command"] = activeSimpleCommand.command;
  doc["status"] = status;
  doc["createdAtMs"] = activeSimpleCommand.createdAtMs;
  doc["updatedAtMs"] = unixNowMs(unixNowSec());
  doc["expiresAtMs"] = activeSimpleCommand.expiresAtMs;
  doc["propertyId"] = activeSimpleCommand.propertyId;
  doc["propertyScopeId"] = activeSimpleCommand.propertyScopeId;
  doc["matrixId"] = matrixCloudId();
  doc["matrixGatewayId"] = activeSimpleCommand.matrixGatewayId;
  doc["matrixRuntimeId"] = matrixCloudId();
  doc["requestedByUid"] = activeSimpleCommand.requestedByUid;
  doc["requestedByRole"] = activeSimpleCommand.requestedByRole;
  doc["writer"] = "gateway_matrix";
  doc["writerKey"] = cfg::RTDB_WRITER_KEY;
  if (reason && reason[0]) doc["reason"] = reason;

  JsonObject deviceResults = doc["deviceResults"].to<JsonObject>();
  for (uint8_t i = 0; i < activeSimpleCommand.targetCount; ++i) {
    const ActiveSimpleCommandTargetState& target = activeSimpleCommand.targets[i];
    JsonObject item = deviceResults.createNestedObject(target.targetId);
    item["ok"] = target.ok;
    item["status"] = target.status[0] ? target.status : (target.terminal ? "completed" : "dispatching");
    if (target.reason[0]) item["reason"] = target.reason;
  }

  String body;
  serializeJson(doc, body);
  const bool matrixOk = rtdbWrite(
      "PUT",
      String("matrixCommandResults/") + matrixCloudId() + "/" + activeSimpleCommand.commandId,
      body);
  const bool propertyOk = rtdbWrite(
      "PUT",
      String("propertyCommands/") + sanitizeRtdbKey(String(activeSimpleCommand.propertyId)) +
          "/" + activeSimpleCommand.commandId,
      body);
  const bool eventOk = appendPropertyCommandEvent(
      activeSimpleCommand.propertyId,
      activeSimpleCommand.commandId,
      status,
      reason,
      &doc);
  if (!(matrixOk && propertyOk && eventOk)) {
    setLastCloudWriteError("command_status", activeSimpleCommand.commandId);
  }
  return matrixOk && propertyOk && eventOk;
}

static void markActiveSimpleCommandTarget(
    const char* targetId,
    bool ok,
    const char* status,
    const char* reason) {
  const int idx = findActiveSimpleCommandTarget(targetId);
  if (idx < 0) return;

  ActiveSimpleCommandTargetState& target = activeSimpleCommand.targets[idx];
  target.terminal = true;
  target.ok = ok;
  copyStringToBuffer(target.status, sizeof(target.status), status ? status : (ok ? "completed" : "failed"));
  copyStringToBuffer(target.reason, sizeof(target.reason), reason ? reason : "");
}

static bool publishImmediateMatrixCommandResult(
    const char* commandId,
    const char* command,
    const char* propertyId,
    const char* propertyScopeId,
    const char* matrixGatewayId,
    const char* requestedByUid,
    const char* requestedByRole,
    uint64_t createdAtMs,
    uint64_t expiresAtMs,
    const char* status,
    const char* reason) {
  if (!cfg::FEATURE_CLOUD) return false;
  if (!commandId || !commandId[0]) return false;
  DynamicJsonDocument doc(1024);
  doc["commandId"] = commandId;
  if (command && command[0]) doc["command"] = command;
  doc["status"] = status;
  doc["createdAtMs"] = createdAtMs;
  doc["updatedAtMs"] = unixNowMs(unixNowSec());
  doc["expiresAtMs"] = expiresAtMs;
  doc["propertyId"] = propertyId ? propertyId : "";
  doc["propertyScopeId"] = propertyScopeId ? propertyScopeId : "";
  doc["matrixId"] = matrixCloudId();
  doc["matrixGatewayId"] = matrixGatewayId ? matrixGatewayId : "";
  doc["matrixRuntimeId"] = matrixCloudId();
  if (requestedByUid && requestedByUid[0]) doc["requestedByUid"] = requestedByUid;
  if (requestedByRole && requestedByRole[0]) doc["requestedByRole"] = requestedByRole;
  doc["writer"] = "gateway_matrix";
  doc["writerKey"] = cfg::RTDB_WRITER_KEY;
  if (reason && reason[0]) doc["reason"] = reason;

  String body;
  serializeJson(doc, body);
  const bool matrixOk = rtdbWrite(
      "PUT",
      String("matrixCommandResults/") + matrixCloudId() + "/" + commandId,
      body);
  const bool propertyOk = rtdbWrite(
      "PUT",
      String("propertyCommands/") + sanitizeRtdbKey(String(propertyId ? propertyId : "")) +
          "/" + commandId,
      body);
  const bool eventOk = appendPropertyCommandEvent(
      propertyId,
      commandId,
      status,
      reason,
      &doc);
  if (!(matrixOk && propertyOk && eventOk)) {
    setLastCloudWriteError("command_status", String(commandId));
  }
  return matrixOk && propertyOk && eventOk;
}

static bool setupWiFi() {
  if (!cfg::FEATURE_WIFI_AP) return false;
  WiFi.mode(cfg::FEATURE_BACKHAUL ? WIFI_AP_STA : WIFI_AP);
  WiFi.setSleep(false);
  const String apSsid = gatewayApSsid();
  const bool apOk = WiFi.softAP(apSsid.c_str(), cfg::AP_PASS);
  if (!apOk) {
    wifiApRunning = false;
    WiFi.mode(WIFI_OFF);
    LOGE("Falha ao subir AP.");
    return false;
  }
  wifiApRunning = true;
  wifiRecoveryAttemptCount = 0;
  LOGI("AP ativo: %s", apSsid.c_str());
  return true;
}

static void setupOta() {
  if (!wifiOtaEnabled || !cfg::FEATURE_OTA || !cfg::OTA_ENABLED) return;
  ArduinoOTA.setHostname(cfg::OTA_HOSTNAME);
  ArduinoOTA.setPort(3232);
  ArduinoOTA.setTimeout(cfg::OTA_HANDSHAKE_TIMEOUT_MS);
  ArduinoOTA.setPassword(cfg::OTA_PASSWORD);
  ArduinoOTA.onStart([]() {
    otaUploadInProgress = true;
    setWatchdogEnabled(false);
    LOGI("OTA iniciado");
  });
  ArduinoOTA.onEnd([]() {
    otaUploadInProgress = false;
    if (wifiOtaEnabled) setWatchdogEnabled(true);
    LOGI("OTA concluido");
  });
  ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
    static uint8_t lastStep = 0xFF;
    const uint8_t pct = (uint8_t)((progress * 100U) / total);
    const uint8_t step = pct / 10U;
    if (step != lastStep || pct == 100U) {
      lastStep = step;
      LOGI("OTA progresso: %u%%", pct);
    }
  });
  ArduinoOTA.onError([](ota_error_t error) {
    otaUploadInProgress = false;
    if (wifiOtaEnabled) setWatchdogEnabled(true);
    LOGE("OTA erro=%u (%s)", (unsigned int)error, otaErrorText(error));
    logOtaPartitionInfo("erro");
  });
  ArduinoOTA.begin();
  logOtaPartitionInfo("inicio");
  LOGI("OTA ativo hostname=%s", cfg::OTA_HOSTNAME);
}

static void stopWifiAndOta() {
  wifiApRunning = false;
  wifiRecoveryAttemptCount = 0;
  wifiRecoveryAttemptAtMs = 0;
  cloudBackhaulAttemptAtMs = 0;
  cloudBackhaulConnecting = false;
  cloudBackhaulConnectStartedAtMs = 0;
  if (WiFi.getMode() == WIFI_STA || WiFi.getMode() == WIFI_AP_STA) {
    WiFi.disconnect(true, true);
  }
  if (WiFi.getMode() == WIFI_AP || WiFi.getMode() == WIFI_AP_STA) {
    WiFi.softAPdisconnect(true);
  }
  WiFi.mode(WIFI_OFF);
  LOGI("Gateway matriz em modo LoRa-only");
}

static void onWifiEvent(WiFiEvent_t event, WiFiEventInfo_t info) {
#if defined(ARDUINO_EVENT_WIFI_AP_START)
  if (event == ARDUINO_EVENT_WIFI_AP_START) {
    wifiApRunning = true;
    LOGI("WiFi AP iniciado");
  }
#endif
#if defined(ARDUINO_EVENT_WIFI_AP_STOP)
  if (event == ARDUINO_EVENT_WIFI_AP_STOP) {
    wifiApRunning = false;
    wifiRecoveryAttemptAtMs = 0;
    LOGW("WiFi AP parou");
  }
#endif
#if defined(ARDUINO_EVENT_WIFI_AP_STACONNECTED)
  if (event == ARDUINO_EVENT_WIFI_AP_STACONNECTED) {
    LOGI("Cliente conectado no AP (n=%d)", WiFi.softAPgetStationNum());
  }
#endif
#if defined(ARDUINO_EVENT_WIFI_AP_STADISCONNECTED)
  if (event == ARDUINO_EVENT_WIFI_AP_STADISCONNECTED) {
    LOGI("Cliente desconectado do AP (n=%d)", WiFi.softAPgetStationNum());
  }
#endif
#if defined(ARDUINO_EVENT_WIFI_STA_GOT_IP)
  if (event == ARDUINO_EVENT_WIFI_STA_GOT_IP) {
    cloudBackhaulConnecting = false;
    cloudBackhaulConnectStartedAtMs = 0;
    cloudBackhaulAttemptAtMs = 0;
    cloudBackhaulLastDisconnectReason = WIFI_REASON_UNSPECIFIED;
    LOGI("Backhaul conectado: %s", WiFi.localIP().toString().c_str());
  }
#endif
#if defined(ARDUINO_EVENT_WIFI_STA_CONNECTED)
  if (event == ARDUINO_EVENT_WIFI_STA_CONNECTED) {
    cloudBackhaulConnecting = true;
    cloudBackhaulConnectStartedAtMs = millis();
    LOGI("Backhaul Wi-Fi associado ao AP");
  }
#endif
#if defined(ARDUINO_EVENT_WIFI_STA_DISCONNECTED)
  if (event == ARDUINO_EVENT_WIFI_STA_DISCONNECTED) {
    const uint8_t rawReason = info.wifi_sta_disconnected.reason;
    const wifi_err_reason_t reason =
        rawReason == 0 ? WIFI_REASON_UNSPECIFIED : (wifi_err_reason_t)rawReason;
    cloudBackhaulLastDisconnectReason = reason;
    cloudBackhaulConnecting = false;
    cloudBackhaulConnectStartedAtMs = 0;
    if (cloudTelemetryConfigured() || !wifiOtaEnabled) {
      LOGW(
          "Backhaul desconectado: motivo=%s(%u) wl=%s(%d)",
          wifiDisconnectReasonLabel(reason),
          (unsigned)reason,
          wifiStatusLabel(WiFi.status()),
          (int)WiFi.status());
    }
  }
#endif
}

static bool wifiApClientConnected() {
  if (!cfg::FEATURE_WIFI_AP || !wifiOtaEnabled || !wifiApRunning) return false;
  const wifi_mode_t mode = WiFi.getMode();
  if (mode != WIFI_AP && mode != WIFI_AP_STA) return false;
  return WiFi.softAPgetStationNum() > 0;
}

static bool shouldBlePresenceBeEnabled() {
  if (!cfg::FEATURE_BLE) return false;
  if (!wifiOtaEnabled) return false;
  if (otaUploadInProgress) return false;
  return true;
}

static uint32_t wifiRecoveryBackoffMs() {
  uint8_t step = wifiRecoveryAttemptCount;
  if (step > 5) step = 5;
  return 1000UL << step;
}

static void ensureWifiOtaServices() {
  if (!cfg::FEATURE_WIFI_AP) return;
  if (!wifiOtaEnabled) return;
  const wifi_mode_t mode = WiFi.getMode();
  if (wifiApRunning && (mode == WIFI_AP || mode == WIFI_AP_STA)) return;
  const uint32_t now = millis();
  const uint32_t backoffMs = wifiRecoveryBackoffMs();
  if (wifiRecoveryAttemptAtMs != 0 &&
      (uint32_t)(now - wifiRecoveryAttemptAtMs) < backoffMs) {
    return;
  }
  wifiRecoveryAttemptAtMs = now;
  LOGW("WiFi/AP inativo, retomando servico (tentativa=%u)", (unsigned)(wifiRecoveryAttemptCount + 1U));
  if (setupWiFi()) {
    setupOta();
    wifiRecoveryAttemptCount = 0;
    return;
  }
  if (wifiRecoveryAttemptCount < 10) wifiRecoveryAttemptCount++;
}

static void setWatchdogEnabled(bool enabled) {
  if (enabled && !watchdogTaskRegistered) {
    const esp_err_t err = esp_task_wdt_add(NULL);
    if (err == ESP_OK) {
      watchdogTaskRegistered = true;
    } else if (err != ESP_ERR_INVALID_STATE) {
      LOGW("TWDT add falhou err=%d", (int)err);
    }
  } else if (!enabled && watchdogTaskRegistered) {
    const esp_err_t err = esp_task_wdt_delete(NULL);
    if (err == ESP_OK || err == ESP_ERR_NOT_FOUND) {
      watchdogTaskRegistered = false;
    } else {
      LOGW("TWDT delete falhou err=%d", (int)err);
    }
  }
}

static void feedWatchdogIfEnabled() {
  if (!watchdogTaskRegistered) return;
  const esp_err_t err = esp_task_wdt_reset();
  if (err == ESP_ERR_NOT_FOUND) {
    watchdogTaskRegistered = false;
    return;
  }
  if (err != ESP_OK) {
    LOGW("TWDT reset falhou err=%d", (int)err);
  }
}

static bool parseWifiOtaParam(const JsonVariantConst payload, bool& outEnabled) {
  if (!payload.is<JsonObjectConst>()) return false;
  const JsonVariantConst v = payload["wifi_ota_enabled"];
  if (!v.is<bool>()) return false;
  outEnabled = v.as<bool>();
  return true;
}

static bool hasAdminModePermission(const JsonVariantConst payload) {
  if (!payload.is<JsonObjectConst>()) return false;
  const JsonVariantConst requestedByAdmin = payload["requested_by_admin"];
  return rtcmd::hasAdminModePermission(
      requestedByAdmin.is<bool>() && requestedByAdmin.as<bool>(),
      payload["requested_by_role"] | "",
      payload["actor_role"] | "");
}

static bool targetIncludesGateway(const JsonVariantConst payload) {
  if (!payload.is<JsonObjectConst>()) return true;
  const char* target = payload["target"] | "all";
  return rtcmd::targetIncludesGateway(target);
}

static bool targetIncludesCollars(const JsonVariantConst payload) {
  if (!payload.is<JsonObjectConst>()) return true;
  const char* target = payload["target"] | "all";
  return rtcmd::targetIncludesCollars(target);
}

static void applyWifiOtaMode(bool enabled, const char* source) {
  if (enabled && !cfg::FEATURE_WIFI_AP) {
    LOGW("SET_PARAMS: WiFi/AP indisponivel neste perfil (%s)", cfg::DIAG_PROFILE_NAME);
    return;
  }
  if (wifiOtaEnabled == enabled) {
    LOGI("SET_PARAMS: wifi_ota_enabled ja estava em %d (%s)", enabled ? 1 : 0, source);
    return;
  }

  wifiOtaEnabled = enabled;
  setWatchdogEnabled(enabled);

  if (enabled) {
    if (setupWiFi()) {
      setupOta();
    } else {
      LOGW("SET_PARAMS: WiFi/AP indisponivel; retry automatico ativo");
    }
    if (cfg::BLE_PRESENCE_ENABLED) {
      blePresence.setEnabled(shouldBlePresenceBeEnabled());
      blePresence.setFlags(true, WiFi.status() == WL_CONNECTED);
    }
    LOGI("SET_PARAMS: wifi_ota_enabled=1 aplicado via %s", source);
  } else {
    if (cfg::BLE_PRESENCE_ENABLED) {
      blePresence.setFlags(false, false);
      blePresence.setEnabled(false);
    }
    stopWifiAndOta();
    LOGI("SET_PARAMS: wifi_ota_enabled=0 aplicado via %s", source);
  }
}

static bool isRelayCandidate(const LoRaFrame& frame) {
  return frame.msgType == MsgType::TELEMETRY ||
         frame.msgType == MsgType::EVENT ||
         frame.msgType == MsgType::ACK ||
         frame.msgType == MsgType::NACK ||
         frame.msgType == MsgType::SET_FENCE ||
         frame.msgType == MsgType::SET_HERDING_PLAN ||
         frame.msgType == MsgType::SET_PARAMS ||
         frame.msgType == MsgType::PING;
}

static const char* uplinkTypeLabel(MsgType t) {
  if (t == MsgType::TELEMETRY) return "telemetry";
  if (t == MsgType::EVENT) return "event";
  if (t == MsgType::ACK) return "ack";
  if (t == MsgType::NACK) return "nack";
  return "lora";
}

static bool readPointPair(const JsonArrayConst& pair, double& lat, double& lon) {
  if (pair.isNull() || pair.size() < 2 || pair[0].isNull() || pair[1].isNull()) return false;
  lat = pair[0].as<double>();
  lon = pair[1].as<double>();
  return rtcmd::isValidCoordinate(lat, lon);
}

static bool sendLoRaJsonFrame(uint32_t deviceId, MsgType msgType, const JsonVariantConst payload, const char** reason = nullptr) {
  const size_t bytes = measureJson(payload);
  if (bytes > cfg::LORA_MAX_PAYLOAD_BYTES) {
    if (reason) *reason = "payload_too_large";
    return false;
  }

  LoRaFrame tx;
  tx.deviceId = deviceId;
  tx.scopeId = parseScopeIdHex(payload["scope_id"]);
  if (tx.scopeId == 0) tx.scopeId = bindingScopeIdValue();
  tx.msgType = msgType;
  tx.seq = nextDownlinkSeq();
  tx.timestamp = millis() / 1000;
  for (int i = 0; i < 12; ++i) tx.nonce[i] = (uint8_t)esp_random();
  tx.payloadLen = serializeJson(payload, tx.payload, sizeof(tx.payload));
  if (tx.payloadLen != bytes) {
    if (reason) *reason = "payload_truncated";
    return false;
  }

  const bool ok = lora.send(tx);
  if (!ok && reason && !*reason) *reason = "lora_send_failed";
  return ok;
}

static bool splitPointArrayForPayload(
    const JsonArrayConst& points,
    uint8_t starts[cfg::MAX_POLYGON_POINTS],
    uint8_t ends[cfg::MAX_POLYGON_POINTS],
    uint8_t& chunkCount,
    bool includePhaseMeta,
    uint8_t phaseIdx,
    uint8_t phaseTotal,
    const char** reason = nullptr) {
  chunkCount = 0;
  const uint8_t totalPoints = (uint8_t)points.size();
  const rtcmd::ValidationCode countCode =
      rtcmd::validatePointCount(totalPoints, cfg::MAX_POLYGON_POINTS);
  if (countCode != rtcmd::ValidationCode::kOk) {
    if (reason) *reason = rtcmd::validationCodeToReason(countCode);
    return false;
  }

  StaticJsonDocument<384> probe;
  probe["chunked"] = true;
  // Usa dois digitos para evitar subestimar overhead quando total>=10.
  probe["part"] = 99;
  probe["total"] = 99;
  if (includePhaseMeta) {
    probe["phase_index"] = phaseIdx;
    probe["phase_total"] = phaseTotal;
  }
  JsonArray probePoints = probe["points"].to<JsonArray>();
  const size_t overheadBytes = measureJson(probe);

  uint16_t pointCosts[cfg::MAX_POLYGON_POINTS]{};
  size_t previousSize = overheadBytes;
  for (uint8_t i = 0; i < totalPoints; ++i) {
    const JsonArrayConst srcPair = points[i].as<JsonArrayConst>();
    double lat = 0.0;
    double lon = 0.0;
    if (!readPointPair(srcPair, lat, lon)) {
      if (reason) *reason = "invalid_point_value";
      return false;
    }

    JsonArray dstPair = probePoints.add<JsonArray>();
    dstPair.add(lat);
    dstPair.add(lon);
    const size_t measured = measureJson(probe);
    if (measured <= previousSize) {
      if (reason) *reason = "invalid_point_value";
      return false;
    }
    const size_t delta = measured - previousSize;
    if (delta > 0xFFFF) {
      if (reason) *reason = "point_chunk_too_large";
      return false;
    }
    pointCosts[i] = (uint16_t)delta;
    previousSize = measured;
  }

  rtcmd::ChunkRange ranges[cfg::MAX_POLYGON_POINTS]{};
  const rtcmd::ValidationCode chunkCode = rtcmd::planPointChunks(
      pointCosts,
      totalPoints,
      (uint16_t)overheadBytes,
      cfg::LORA_MAX_PAYLOAD_BYTES,
      cfg::MAX_POLYGON_POINTS,
      ranges,
      cfg::MAX_POLYGON_POINTS,
      &chunkCount);
  if (chunkCode != rtcmd::ValidationCode::kOk) {
    if (reason) *reason = rtcmd::validationCodeToReason(chunkCode);
    return false;
  }

  for (uint8_t i = 0; i < chunkCount; ++i) {
    starts[i] = ranges[i].start;
    ends[i] = ranges[i].end;
  }
  return true;
}

static bool sendFenceCommandChunked(uint32_t deviceId, const JsonVariantConst payload, const char** reason = nullptr) {
  const JsonArrayConst points = payload["points"].as<JsonArrayConst>();
  if (points.isNull()) {
    if (reason) *reason = "missing_points";
    return false;
  }

  uint8_t starts[cfg::MAX_POLYGON_POINTS]{};
  uint8_t ends[cfg::MAX_POLYGON_POINTS]{};
  uint8_t chunkCount = 0;
  if (!splitPointArrayForPayload(points, starts, ends, chunkCount, false, 0, 0, reason)) return false;

  for (uint8_t part = 0; part < chunkCount; ++part) {
    StaticJsonDocument<384> chunkDoc;
    chunkDoc["chunked"] = true;
    chunkDoc["part"] = part;
    chunkDoc["total"] = chunkCount;
    const char* commandId = pickFirstText(payload["cmd_id"], payload["command_id"]);
    const char* scopeId = pickFirstText(payload["scope_id"], payload["property_scope_id"]);
    const char* matrixGatewayId = pickFirstText(payload["matrix_gateway_id"]);
    if (commandId[0] != '\0') chunkDoc["cmd_id"] = commandId;
    if (scopeId[0] != '\0') chunkDoc["scope_id"] = scopeId;
    if (matrixGatewayId[0] != '\0') chunkDoc["matrix_gateway_id"] = matrixGatewayId;
    if (!payload["requested_at_ms"].isNull()) {
      chunkDoc["requested_at_ms"] = payload["requested_at_ms"];
    }
    JsonArray chunkPoints = chunkDoc["points"].to<JsonArray>();
    for (uint8_t i = starts[part]; i < ends[part]; ++i) {
      const JsonArrayConst srcPair = points[i].as<JsonArrayConst>();
      JsonArray dstPair = chunkPoints.add<JsonArray>();
      dstPair.add(srcPair[0].as<double>());
      dstPair.add(srcPair[1].as<double>());
    }

    if (!sendLoRaJsonFrame(deviceId, MsgType::SET_FENCE, chunkDoc.as<JsonVariantConst>(), reason)) return false;
  }
  return true;
}

static bool sendHerdingPlanChunked(uint32_t deviceId, const JsonVariantConst payload, const char** reason = nullptr) {
  const JsonArrayConst phases = payload["phases"].as<JsonArrayConst>();
  if (phases.isNull()) {
    if (reason) *reason = "missing_phases";
    return false;
  }
  const uint8_t phaseTotal = (uint8_t)phases.size();
  if (phaseTotal == 0 || phaseTotal > cfg::MAX_HERD_PHASES) {
    if (reason) *reason = "invalid_phase_count";
    return false;
  }

  for (uint8_t phaseIdx = 0; phaseIdx < phaseTotal; ++phaseIdx) {
    const JsonArrayConst points = phases[phaseIdx].as<JsonArrayConst>();
    if (points.isNull()) {
      if (reason) *reason = "invalid_phase_points";
      return false;
    }

    uint8_t starts[cfg::MAX_POLYGON_POINTS]{};
    uint8_t ends[cfg::MAX_POLYGON_POINTS]{};
    uint8_t chunkCount = 0;
    if (!splitPointArrayForPayload(points, starts, ends, chunkCount, true, phaseIdx, phaseTotal, reason)) return false;

    for (uint8_t part = 0; part < chunkCount; ++part) {
      StaticJsonDocument<384> chunkDoc;
      chunkDoc["chunked"] = true;
      const char* operationId = payload["operation_id"] | "";
      const char* commandId = pickFirstText(payload["cmd_id"], payload["command_id"]);
      const char* scopeId = pickFirstText(payload["scope_id"], payload["property_scope_id"]);
      const char* matrixGatewayId = pickFirstText(payload["matrix_gateway_id"]);
      if (operationId[0] != '\0') chunkDoc["operation_id"] = operationId;
      if (commandId[0] != '\0') chunkDoc["cmd_id"] = commandId;
      if (scopeId[0] != '\0') chunkDoc["scope_id"] = scopeId;
      if (matrixGatewayId[0] != '\0') chunkDoc["matrix_gateway_id"] = matrixGatewayId;
      if (!payload["requested_at_ms"].isNull()) {
        chunkDoc["requested_at_ms"] = payload["requested_at_ms"];
      }
      chunkDoc["phase_index"] = phaseIdx;
      chunkDoc["phase_total"] = phaseTotal;
      chunkDoc["part"] = part;
      chunkDoc["total"] = chunkCount;
      JsonArray chunkPoints = chunkDoc["points"].to<JsonArray>();
      for (uint8_t i = starts[part]; i < ends[part]; ++i) {
        const JsonArrayConst srcPair = points[i].as<JsonArrayConst>();
        JsonArray dstPair = chunkPoints.add<JsonArray>();
        dstPair.add(srcPair[0].as<double>());
        dstPair.add(srcPair[1].as<double>());
      }

      if (!sendLoRaJsonFrame(deviceId, MsgType::SET_HERDING_PLAN, chunkDoc.as<JsonVariantConst>(), reason)) return false;
    }
  }

  return true;
}

static bool queuePollingConfigured() {
  return cloudTelemetryConfigured() && !isUnsetCloudValue(cfg::RTDB_QUEUE_KEY);
}

static String queueRootPath() {
  return String("matrixCommandQueues/") + matrixCloudId() + "/" + String(cfg::RTDB_QUEUE_KEY);
}

static bool loadNextQueuedCommand(String& commandIdOut, DynamicJsonDocument& commandDocOut) {
  if (!queuePollingConfigured()) return false;
  String body;
  if (!rtdbRead(queueRootPath(), body)) return false;
  body.trim();
  if (body.isEmpty() || body == "null") return false;

  DynamicJsonDocument queueDoc(16384);
  if (deserializeJson(queueDoc, body) != DeserializationError::Ok ||
      !queueDoc.is<JsonObjectConst>()) {
    return false;
  }

  String selectedId;
  String selectedBody;
  for (JsonPairConst kv : queueDoc.as<JsonObjectConst>()) {
    const String key = kv.key().c_str();
    if (!selectedId.isEmpty() && key >= selectedId) continue;
    String candidateBody;
    serializeJson(kv.value(), candidateBody);
    selectedId = key;
    selectedBody = candidateBody;
  }
  if (selectedId.isEmpty() || selectedBody.isEmpty()) return false;

  commandDocOut.clear();
  if (deserializeJson(commandDocOut, selectedBody) != DeserializationError::Ok) {
    return false;
  }
  commandIdOut = selectedId;
  return true;
}

static bool deleteQueuedCommand(const String& commandId) {
  if (commandId.isEmpty()) return false;
  return rtdbDelete(queueRootPath() + "/" + commandId);
}

static bool dispatchQueuedSimpleCommand(
    const String& commandId,
    DynamicJsonDocument& commandDoc,
    const char** reason) {
  const char* command = commandDoc["command"] | "";
  const char* propertyId = commandDoc["propertyId"] | "";
  const char* propertyScopeId = commandDoc["propertyScopeId"] | "";
  const char* matrixGatewayId = commandDoc["matrixGatewayId"] | "";
  const JsonArrayConst targetDeviceIds = commandDoc["targetDeviceIds"].as<JsonArrayConst>();
  const JsonArrayConst targetGatewayIds = commandDoc["targetGatewayIds"].as<JsonArrayConst>();
  JsonVariant payloadVariant = commandDoc["payload"];
  if (!payloadVariant.isNull() && !payloadVariant.is<JsonObject>()) {
    if (reason) *reason = "invalid_payload";
    return false;
  }

  DynamicJsonDocument payloadDoc(8192);
  if (payloadVariant.is<JsonObject>()) {
    payloadDoc.set(payloadVariant);
  } else {
    payloadDoc.to<JsonObject>();
  }
  payloadDoc["cmd_id"] = commandId;

  clearActiveSimpleCommand();
  activeSimpleCommand.active = true;
  activeSimpleCommand.dispatchAtMs = millis();
  activeSimpleCommand.createdAtMs = commandDoc["createdAtMs"] | 0ULL;
  activeSimpleCommand.expiresAtMs = commandDoc["expiresAtMs"] | 0ULL;
  copyStringToBuffer(activeSimpleCommand.commandId, sizeof(activeSimpleCommand.commandId), commandId.c_str());
  copyStringToBuffer(activeSimpleCommand.command, sizeof(activeSimpleCommand.command), command);
  copyStringToBuffer(activeSimpleCommand.propertyId, sizeof(activeSimpleCommand.propertyId), propertyId);
  copyStringToBuffer(
      activeSimpleCommand.propertyScopeId,
      sizeof(activeSimpleCommand.propertyScopeId),
      propertyScopeId);
  copyStringToBuffer(
      activeSimpleCommand.matrixGatewayId,
      sizeof(activeSimpleCommand.matrixGatewayId),
      matrixGatewayId);
  copyStringToBuffer(
      activeSimpleCommand.requestedByUid,
      sizeof(activeSimpleCommand.requestedByUid),
      commandDoc["requestedByUid"] | "");
  copyStringToBuffer(
      activeSimpleCommand.requestedByRole,
      sizeof(activeSimpleCommand.requestedByRole),
      commandDoc["requestedByRole"] | "user");

  bool sentAny = false;
  if (!targetDeviceIds.isNull() && targetDeviceIds.size() > 0) {
    for (JsonVariantConst rawId : targetDeviceIds) {
      const char* textId = rawId | "";
      uint32_t deviceId = rawId.is<uint32_t>() ? rawId.as<uint32_t>() : (uint32_t)strtoul(textId, nullptr, 10);
      if (deviceId == 0) {
        if (reason) *reason = "invalid_target_device";
        clearActiveSimpleCommand();
        return false;
      }
      if (activeSimpleCommand.targetCount >= cfg::MAX_HERD_OPERATION_DEVICES) {
        if (reason) *reason = "too_many_targets";
        clearActiveSimpleCommand();
        return false;
      }
      const uint8_t idx = activeSimpleCommand.targetCount++;
      snprintf(
          activeSimpleCommand.targets[idx].targetId,
          sizeof(activeSimpleCommand.targets[idx].targetId),
          "%lu",
          (unsigned long)deviceId);
      bool ok = false;
      if (strcmp(command, "SET_FENCE") == 0) {
        ok = sendFenceCommandChunked(deviceId, payloadDoc.as<JsonVariantConst>(), reason);
      } else if (strcmp(command, "SET_PARAMS") == 0 || strcmp(command, "PING") == 0) {
        const MsgType msgType =
            strcmp(command, "SET_PARAMS") == 0 ? MsgType::SET_PARAMS : MsgType::PING;
        ok = sendLoRaJsonFrame(deviceId, msgType, payloadDoc.as<JsonVariantConst>(), reason);
      }
      if (!ok) {
        clearActiveSimpleCommand();
        return false;
      }
      sentAny = true;
    }
  } else if (!targetGatewayIds.isNull() && targetGatewayIds.size() > 0) {
    JsonArray gatewayTargetIds = payloadDoc["target_gateway_ids"].to<JsonArray>();
    for (JsonVariantConst rawId : targetGatewayIds) {
      const char* textId = rawId | "";
      if (!textId[0]) continue;
      if (activeSimpleCommand.targetCount >= cfg::MAX_HERD_OPERATION_DEVICES) {
        if (reason) *reason = "too_many_targets";
        clearActiveSimpleCommand();
        return false;
      }
      const uint8_t idx = activeSimpleCommand.targetCount++;
      copyStringToBuffer(
          activeSimpleCommand.targets[idx].targetId,
          sizeof(activeSimpleCommand.targets[idx].targetId),
          textId);
      gatewayTargetIds.add(textId);
    }
    const MsgType msgType =
        strcmp(command, "SET_PARAMS") == 0 ? MsgType::SET_PARAMS : MsgType::PING;
    if (!sendLoRaJsonFrame(0, msgType, payloadDoc.as<JsonVariantConst>(), reason)) {
      clearActiveSimpleCommand();
      return false;
    }
    sentAny = activeSimpleCommand.targetCount > 0;
  }

  if (!sentAny || activeSimpleCommand.targetCount == 0) {
    clearActiveSimpleCommand();
    if (reason) *reason = "no_targets";
    return false;
  }
  publishSimpleCommandResult("dispatching", nullptr);
  return true;
}

static void processNextQueuedCommand() {
  if (!queuePollingConfigured() || !bindingReady) return;
  if (herdOp.active || activeSimpleCommand.active) return;
  const uint32_t nowMsTick = millis();
  if (queuePollAtMs != 0 &&
      (uint32_t)(nowMsTick - queuePollAtMs) < 1000UL) {
    return;
  }
  queuePollAtMs = nowMsTick;
  lastQueuePollAtUnixMs = unixNowMs(unixNowSec());

  String commandId;
  DynamicJsonDocument commandDoc(16384);
  if (!loadNextQueuedCommand(commandId, commandDoc)) return;

  const char* command = commandDoc["command"] | "";
  const char* propertyId = commandDoc["propertyId"] | "";
  const char* propertyScopeId = commandDoc["propertyScopeId"] | "";
  const char* matrixGatewayId = commandDoc["matrixGatewayId"] | "";
  const uint64_t expiresAtMs = commandDoc["expiresAtMs"] | 0ULL;
  const uint64_t nowMs = unixNowMs(unixNowSec());

  const char* failReason = nullptr;
  const char* failStatus = nullptr;
  if (!commandId.length() || !command[0]) {
    return;
  } else if (expiresAtMs != 0 && expiresAtMs <= nowMs) {
    failStatus = "expired";
    failReason = "command_expired";
  } else if (!bindingReady) {
    failStatus = "rejected";
    failReason = "property_binding_missing";
  } else if (strcmp(propertyId, bindingPropertyId) != 0) {
    failStatus = "rejected";
    failReason = "property_binding_mismatch";
  } else if (!rtcmd::isValidScopeId(propertyScopeId) ||
             strcmp(propertyScopeId, bindingPropertyScopeId) != 0) {
    failStatus = "rejected";
    failReason = "property_scope_mismatch";
  } else if (bindingMatrixGatewayId[0] != '\0' &&
             strcmp(matrixGatewayId, bindingMatrixGatewayId) != 0) {
    failStatus = "rejected";
    failReason = "matrix_gateway_mismatch";
  }

  if (failStatus) {
    publishImmediateMatrixCommandResult(
        commandId.c_str(),
        command,
        propertyId,
        propertyScopeId,
        matrixGatewayId,
        commandDoc["requestedByUid"] | "",
        commandDoc["requestedByRole"] | "user",
        commandDoc["createdAtMs"] | 0ULL,
        commandDoc["expiresAtMs"] | 0ULL,
        failStatus,
        failReason);
    deleteQueuedCommand(commandId);
    return;
  }

  if (strcmp(command, "SET_HERDING_PLAN") == 0) {
    JsonVariant payloadVariant = commandDoc["payload"];
    const char* startReason = nullptr;
    DynamicJsonDocument payloadDoc(8192);
    if (payloadVariant.is<JsonObject>()) {
      payloadDoc.set(payloadVariant);
    }
    payloadDoc["cmd_id"] = commandId;
    payloadDoc["command_id"] = commandId;
    payloadDoc["scope_id"] = propertyScopeId;
    payloadDoc["property_scope_id"] = propertyScopeId;
    payloadDoc["matrix_gateway_id"] = matrixGatewayId;
    payloadDoc["requested_at_ms"] = commandDoc["createdAtMs"] | 0ULL;
    if (!payloadDoc.is<JsonObject>() ||
        !startHerdingOperation(payloadDoc.as<JsonVariantConst>(), &startReason)) {
      publishImmediateMatrixCommandResult(
          commandId.c_str(),
          command,
          propertyId,
          propertyScopeId,
          matrixGatewayId,
          commandDoc["requestedByUid"] | "",
          commandDoc["requestedByRole"] | "user",
          commandDoc["createdAtMs"] | 0ULL,
          commandDoc["expiresAtMs"] | 0ULL,
          "failed",
          startReason ? startReason : "invalid_operation_payload");
    } else {
      copyStringToBuffer(herdOp.loraCommandId, sizeof(herdOp.loraCommandId), commandId.c_str());
      copyStringToBuffer(
          herdOp.propertyScopeId, sizeof(herdOp.propertyScopeId), propertyScopeId);
      herdOp.createdAtMs = commandDoc["createdAtMs"] | 0ULL;
      herdOp.expiresAtMs = commandDoc["expiresAtMs"] | 0ULL;
      publishHerdingOperationSnapshot(true, "dispatching");
    }
    deleteQueuedCommand(commandId);
    return;
  }

  if (strcmp(command, "SET_FENCE") != 0 &&
      strcmp(command, "SET_PARAMS") != 0 &&
      strcmp(command, "PING") != 0) {
    publishImmediateMatrixCommandResult(
        commandId.c_str(),
        command,
        propertyId,
        propertyScopeId,
        matrixGatewayId,
        commandDoc["requestedByUid"] | "",
        commandDoc["requestedByRole"] | "user",
        commandDoc["createdAtMs"] | 0ULL,
        commandDoc["expiresAtMs"] | 0ULL,
        "rejected",
        "unsupported_command");
    deleteQueuedCommand(commandId);
    return;
  }

  if (!dispatchQueuedSimpleCommand(commandId, commandDoc, &failReason)) {
    publishImmediateMatrixCommandResult(
        commandId.c_str(),
        command,
        propertyId,
        propertyScopeId,
        matrixGatewayId,
        commandDoc["requestedByUid"] | "",
        commandDoc["requestedByRole"] | "user",
        commandDoc["createdAtMs"] | 0ULL,
        commandDoc["expiresAtMs"] | 0ULL,
        "failed",
        failReason ? failReason : "lora_send_failed");
  }
  deleteQueuedCommand(commandId);
}

static void resetHerdingOperationState() {
  herdOp = HerdingOperationState{};
}

static int findHerdingOperationDevice(uint32_t deviceId) {
  for (uint8_t i = 0; i < herdOp.deviceCount; ++i) {
    if (herdOp.devices[i].deviceId == deviceId) return i;
  }
  return -1;
}

static uint8_t herdAssembledCount() {
  uint8_t count = 0;
  for (uint8_t i = 0; i < herdOp.deviceCount; ++i) {
    if (herdOp.devices[i].assembled || herdOp.devices[i].completed) count++;
  }
  return count;
}

static uint8_t herdCompletedCount() {
  uint8_t count = 0;
  for (uint8_t i = 0; i < herdOp.deviceCount; ++i) {
    if (herdOp.devices[i].completed) count++;
  }
  return count;
}

static bool allHerdDevicesAssembled() {
  return herdOp.deviceCount > 0 && herdAssembledCount() == herdOp.deviceCount;
}

static bool allHerdDevicesCompleted() {
  return herdOp.deviceCount > 0 && herdCompletedCount() == herdOp.deviceCount;
}

static const char* herdDeviceStatusLabel(const HerdingOperationDeviceState& device) {
  if (device.completed) return "completed";
  if (device.assembled) return "assembled";
  if (device.retryCount > 0) return "dispatching";
  return "pending";
}

static const char* herdOperationStatusLabel() {
  if (herdOp.failureReason[0] != '\0') return "failed";
  if (allHerdDevicesCompleted()) return "completed";
  if (allHerdDevicesAssembled()) return "requested";
  if (herdAssembledCount() > 0) return "awaiting_assembly";
  return "dispatching";
}

static void broadcastHerdingOperationUpdate(const char* status) {
  StaticJsonDocument<1024> packet;
  packet["type"] = "herding_operation_update";
  packet["operation_id"] = herdOp.operationId;
  packet["status"] = status;
  packet["ok"] = strcmp(status, "failed") != 0;
  packet["property_id"] = herdOp.propertyId;
  packet["matrix_gateway_id"] = herdOp.matrixGatewayId;
  packet["assembled_count"] = herdAssembledCount();
  packet["completed_count"] = herdCompletedCount();
  packet["device_count"] = herdOp.deviceCount;
  if (herdOp.failureReason[0] != '\0') packet["reason"] = herdOp.failureReason;
  String out;
  serializeJson(packet, out);
  api.broadcastTelemetry(out);
  sdlog.log(String("HERD|") + out);
}

static void publishHerdingOperationSnapshot(
    bool force,
    const char* statusOverride) {
  if (!herdOp.operationId[0]) return;

  const uint32_t nowMsTick = millis();
  if (!force && herdOp.lastStatusPublishAtMs != 0 &&
      (uint32_t)(nowMsTick - herdOp.lastStatusPublishAtMs) <
          cfg::HERD_OPERATION_STATUS_PUBLISH_MS) {
    return;
  }

  const uint32_t nowSec = unixNowSec();
  const uint64_t nowMs = unixNowMs(nowSec);
  const char* status = statusOverride ? statusOverride : herdOperationStatusLabel();
  if (strcmp(status, "requested") == 0 && herdOp.requestedAtSec == 0) {
    herdOp.requestedAtSec = nowSec;
  }
  if (strcmp(status, "completed") == 0 && herdOp.completedAtSec == 0) {
    herdOp.completedAtSec = nowSec;
  }

  DynamicJsonDocument doc(6144);
  doc["operationId"] = herdOp.operationId;
  doc["status"] = status;
  doc["propertyId"] = herdOp.propertyId;
  doc["ownerUid"] = herdOp.ownerUid;
  doc["requestedByUid"] = herdOp.requestedByUid;
  doc["requestedByRole"] = herdOp.requestedByRole;
  doc["matrixGatewayId"] = herdOp.matrixGatewayId;
  if (herdOp.propertyScopeId[0] != '\0') doc["propertyScopeId"] = herdOp.propertyScopeId;
  if (herdOp.loraCommandId[0] != '\0') doc["loraCommandId"] = herdOp.loraCommandId;
  doc["updatedAt"] = nowMs;
  doc["writer"] = "gateway_matrix";
  doc["matrixId"] = matrixCloudId();
  doc["writerKey"] = cfg::RTDB_WRITER_KEY;
  if (herdOp.requestedAtSec != 0) {
    doc["requestedAt"] = (uint64_t)herdOp.requestedAtSec * 1000ULL;
  }
  if (herdOp.completedAtSec != 0) {
    doc["completedAt"] = (uint64_t)herdOp.completedAtSec * 1000ULL;
  }
  if (herdOp.failureReason[0] != '\0') doc["failureReason"] = herdOp.failureReason;

  JsonArray selected = doc["selectedDeviceIds"].to<JsonArray>();
  for (uint8_t i = 0; i < herdOp.deviceCount; ++i) {
    selected.add(String(herdOp.devices[i].deviceId));
  }

  JsonArray target = doc["targetPolygon"].to<JsonArray>();
  for (uint8_t i = 0; i < herdOp.pointCount; ++i) {
    JsonObject point = target.createNestedObject();
    point["lat"] = herdOp.targetPolygon[i].lat;
    point["lon"] = herdOp.targetPolygon[i].lon;
  }

  JsonObject statuses = doc["deviceStatuses"].to<JsonObject>();
  for (uint8_t i = 0; i < herdOp.deviceCount; ++i) {
    const HerdingOperationDeviceState& device = herdOp.devices[i];
    JsonObject item = statuses.createNestedObject(String(device.deviceId));
    item["status"] = herdDeviceStatusLabel(device);
    item["retryCount"] = device.retryCount;
    item["updatedAtMs"] = device.updatedAtMs ? device.updatedAtMs : nowMs;
    if (device.phaseIndex > 0) item["phaseIndex"] = device.phaseIndex;
    if (device.lastReason[0] != '\0') item["reason"] = device.lastReason;
  }

  if (herdOp.loraCommandId[0] != '\0' && herdOp.propertyId[0] != '\0' &&
      herdOp.propertyScopeId[0] != '\0') {
    const char* resultStatus = "dispatching";
    if (strcmp(status, "requested") == 0) resultStatus = "acknowledged";
    if (strcmp(status, "completed") == 0) resultStatus = "completed";
    if (strcmp(status, "failed") == 0 || strcmp(status, "superseded") == 0) {
      resultStatus = "failed";
    }

    DynamicJsonDocument resultDoc(2048);
    resultDoc["commandId"] = herdOp.loraCommandId;
    resultDoc["command"] = "SET_HERDING_PLAN";
    resultDoc["status"] = resultStatus;
    resultDoc["createdAtMs"] = herdOp.createdAtMs;
    resultDoc["updatedAtMs"] = nowMs;
    resultDoc["expiresAtMs"] = herdOp.expiresAtMs;
    resultDoc["propertyId"] = herdOp.propertyId;
    resultDoc["propertyScopeId"] = herdOp.propertyScopeId;
    resultDoc["matrixId"] = matrixCloudId();
    resultDoc["matrixGatewayId"] = herdOp.matrixGatewayId;
    resultDoc["matrixRuntimeId"] = matrixCloudId();
    resultDoc["requestedByUid"] = herdOp.requestedByUid;
    resultDoc["requestedByRole"] = herdOp.requestedByRole;
    resultDoc["writer"] = "gateway_matrix";
    resultDoc["writerKey"] = cfg::RTDB_WRITER_KEY;
    if (herdOp.failureReason[0] != '\0') resultDoc["reason"] = herdOp.failureReason;
    JsonObject resultStatuses = resultDoc["deviceResults"].to<JsonObject>();
    for (uint8_t i = 0; i < herdOp.deviceCount; ++i) {
      const HerdingOperationDeviceState& device = herdOp.devices[i];
      JsonObject item = resultStatuses.createNestedObject(String(device.deviceId));
      item["status"] = herdDeviceStatusLabel(device);
      item["retryCount"] = device.retryCount;
      if (device.lastReason[0] != '\0') item["reason"] = device.lastReason;
      item["ok"] = device.lastReason[0] == '\0';
    }
    String resultBody;
    serializeJson(resultDoc, resultBody);
    const bool matrixOk = rtdbWrite(
        "PUT",
        String("matrixCommandResults/") + matrixCloudId() + "/" + herdOp.loraCommandId,
        resultBody);
    const bool propertyOk = rtdbWrite(
        "PUT",
        String("propertyCommands/") + sanitizeRtdbKey(String(herdOp.propertyId)) + "/" +
            herdOp.loraCommandId,
        resultBody);
    bool eventOk = true;
    if (strcmp(herdOp.lastCommandStatus, resultStatus) != 0) {
      eventOk = appendPropertyCommandEvent(
          herdOp.propertyId,
          herdOp.loraCommandId,
          resultStatus,
          herdOp.failureReason[0] != '\0' ? herdOp.failureReason : nullptr,
          &resultDoc);
      copyStringToBuffer(
          herdOp.lastCommandStatus,
          sizeof(herdOp.lastCommandStatus),
          resultStatus);
    }
    if (!(matrixOk && propertyOk && eventOk)) {
      setLastCloudWriteError("herd_status", herdOp.loraCommandId);
    }
  }

  herdOp.updatedAtMs = (uint32_t)(nowMs > 0xFFFFFFFFULL ? 0xFFFFFFFFUL : nowMs);
  herdOp.lastStatusPublishAtMs = nowMsTick;
  broadcastHerdingOperationUpdate(status);
  if (strcmp(status, "completed") == 0 ||
      strcmp(status, "failed") == 0 ||
      strcmp(status, "superseded") == 0) {
    herdOp.finalized = true;
    herdOp.active = false;
  }
}

static bool sendHerdingOperationToDevice(
    HerdingOperationDeviceState& device,
    const char** reason) {
  StaticJsonDocument<1024> payload;
  payload["operation_id"] = herdOp.operationId;
  JsonArray phases = payload["phases"].to<JsonArray>();
  JsonArray phase = phases.createNestedArray();
  for (uint8_t i = 0; i < herdOp.pointCount; ++i) {
    JsonArray pair = phase.createNestedArray();
    pair.add(herdOp.targetPolygon[i].lat);
    pair.add(herdOp.targetPolygon[i].lon);
  }
  const bool ok =
      sendHerdingPlanChunked(device.deviceId, payload.as<JsonVariantConst>(), reason);
  if (ok) {
    device.retryCount++;
    device.lastDispatchAtMs = millis();
    device.updatedAtMs = (uint32_t)unixNowMs(unixNowSec());
    device.lastReason[0] = '\0';
  }
  return ok;
}

static bool startHerdingOperation(const JsonVariantConst payload, const char** reason) {
  if (!payload.is<JsonObjectConst>()) {
    if (reason) *reason = "invalid_operation_payload";
    return false;
  }

  const char* operationId = payload["operation_id"] | "";
  const JsonArrayConst selectedDeviceIds =
      payload["selected_device_ids"].as<JsonArrayConst>();
  const JsonArrayConst targetPolygon = payload["target_polygon"].as<JsonArrayConst>();
  if (operationId[0] == '\0') {
    if (reason) *reason = "missing_operation_id";
    return false;
  }
  if (selectedDeviceIds.isNull() || selectedDeviceIds.size() == 0 ||
      selectedDeviceIds.size() > cfg::MAX_HERD_OPERATION_DEVICES) {
    if (reason) *reason = "invalid_selected_device_count";
    return false;
  }
  const uint8_t pointCount = (uint8_t)targetPolygon.size();
  const rtcmd::ValidationCode pointCode =
      rtcmd::validatePointCount(pointCount, cfg::MAX_POLYGON_POINTS);
  if (pointCode != rtcmd::ValidationCode::kOk) {
    if (reason) *reason = rtcmd::validationCodeToReason(pointCode);
    return false;
  }

  HerdingOperationState next;
  next.active = true;
  next.finalized = false;
  next.startedAtMs = millis();
  next.createdAtMs = payload["created_at_ms"] | (payload["requested_at_ms"] | 0ULL);
  next.expiresAtMs = payload["expires_at_ms"] | 0ULL;
  copyStringToBuffer(next.operationId, sizeof(next.operationId), operationId);
  copyStringToBuffer(next.propertyId, sizeof(next.propertyId), payload["property_id"] | "");
  copyStringToBuffer(next.ownerUid, sizeof(next.ownerUid), payload["owner_uid"] | "");
  copyStringToBuffer(
      next.requestedByUid, sizeof(next.requestedByUid), payload["requested_by_uid"] | "");
  copyStringToBuffer(
      next.requestedByRole,
      sizeof(next.requestedByRole),
      payload["requested_by_role"] | "user");
  copyStringToBuffer(
      next.matrixGatewayId,
      sizeof(next.matrixGatewayId),
      payload["matrix_gateway_id"] | "");
  const char* nextPropertyScopeId =
      pickFirstText(payload["property_scope_id"], payload["scope_id"]);
  if (!nextPropertyScopeId[0]) nextPropertyScopeId = bindingPropertyScopeId;
  copyStringToBuffer(
      next.propertyScopeId,
      sizeof(next.propertyScopeId),
      nextPropertyScopeId);
  copyStringToBuffer(
      next.loraCommandId,
      sizeof(next.loraCommandId),
      pickFirstText(payload["cmd_id"], payload["command_id"]));

  for (uint8_t i = 0; i < pointCount; ++i) {
    double lat = 0.0;
    double lon = 0.0;
    if (!readPointPair(targetPolygon[i].as<JsonArrayConst>(), lat, lon)) {
      if (reason) *reason = "invalid_target_point";
      return false;
    }
    next.targetPolygon[next.pointCount++] = HerdPoint{lat, lon};
  }

  for (JsonVariantConst rawId : selectedDeviceIds) {
    uint32_t deviceId = 0;
    if (rawId.is<uint32_t>() || rawId.is<int>()) {
      deviceId = rawId.as<uint32_t>();
    } else {
      const char* text = rawId | "";
      if (text[0] == '\0') {
        if (reason) *reason = "invalid_selected_device";
        return false;
      }
      deviceId = (uint32_t)strtoul(text, nullptr, 10);
    }
    if (deviceId == 0) {
      if (reason) *reason = "invalid_selected_device";
      return false;
    }
    next.devices[next.deviceCount].deviceId = deviceId;
    next.devices[next.deviceCount].updatedAtMs = (uint32_t)unixNowMs(unixNowSec());
    next.deviceCount++;
  }

  if (herdOp.operationId[0] != '\0' && herdOp.active) {
    publishHerdingOperationSnapshot(true, "superseded");
  }
  herdOp = next;
  publishHerdingOperationSnapshot(true, "dispatching");
  return true;
}

static void dispatchActiveHerdingOperation() {
  if (!herdOp.active || herdOp.finalized || herdOp.operationId[0] == '\0') return;

  const uint32_t nowMsTick = millis();
  if ((uint32_t)(nowMsTick - herdOp.startedAtMs) > cfg::HERD_OPERATION_TIMEOUT_MS &&
      !allHerdDevicesAssembled()) {
    copyStringToBuffer(
        herdOp.failureReason,
        sizeof(herdOp.failureReason),
        "timeout_waiting_assembly");
    for (uint8_t i = 0; i < herdOp.deviceCount; ++i) {
      if (!herdOp.devices[i].assembled && herdOp.devices[i].lastReason[0] == '\0') {
        copyStringToBuffer(
            herdOp.devices[i].lastReason,
            sizeof(herdOp.devices[i].lastReason),
            "timeout_waiting_assembly");
      }
    }
    publishHerdingOperationSnapshot(true, "failed");
    return;
  }

  if (allHerdDevicesCompleted()) {
    publishHerdingOperationSnapshot(true, "completed");
    return;
  }
  if (allHerdDevicesAssembled()) {
    publishHerdingOperationSnapshot(true, "requested");
    return;
  }

  for (uint8_t i = 0; i < herdOp.deviceCount; ++i) {
    HerdingOperationDeviceState& device = herdOp.devices[i];
    if (device.assembled || device.completed) continue;
    if (device.lastDispatchAtMs != 0 &&
        (uint32_t)(nowMsTick - device.lastDispatchAtMs) <
            cfg::HERD_OPERATION_RETRY_MS) {
      continue;
    }

    const char* sendReason = nullptr;
    if (sendHerdingOperationToDevice(device, &sendReason)) {
      publishHerdingOperationSnapshot(true, "dispatching");
      return;
    }
    copyStringToBuffer(
        device.lastReason,
        sizeof(device.lastReason),
        sendReason ? sendReason : "lora_send_failed");
    device.updatedAtMs = (uint32_t)unixNowMs(unixNowSec());
  }

  publishHerdingOperationSnapshot(false, nullptr);
}

static void handleHerdingOperationFeedback(const LoRaFrame& rx) {
  if (!herdOp.operationId[0]) return;
  if (rx.msgType != MsgType::ACK && rx.msgType != MsgType::NACK) return;

  StaticJsonDocument<256> payload;
  if (deserializeJson(payload, rx.payload, rx.payloadLen) != DeserializationError::Ok) {
    return;
  }

  String command;
  if (payload["cmd"].is<const char*>()) {
    command = payload["cmd"].as<const char*>();
  } else if ((payload["cmd"] | 0) == (int)MsgType::SET_HERDING_PLAN ||
             (payload["cmd_code"] | 0) == (int)MsgType::SET_HERDING_PLAN) {
    command = "SET_HERDING_PLAN";
  }
  if (!command.equalsIgnoreCase("SET_HERDING_PLAN")) return;

  const char* operationId = payload["operation_id"] | "";
  if (operationId[0] != '\0' && strcmp(operationId, herdOp.operationId) != 0) return;

  const int idx = findHerdingOperationDevice(rx.deviceId);
  if (idx < 0) return;

  HerdingOperationDeviceState& device = herdOp.devices[idx];
  device.updatedAtMs = (uint32_t)unixNowMs(unixNowSec());
  const char* reason = payload["reason"] | "";
  const char* status = payload["status"] | "";

  if (rx.msgType == MsgType::NACK) {
    copyStringToBuffer(
        device.lastReason,
        sizeof(device.lastReason),
        reason[0] != '\0' ? reason : "nack");
    device.lastDispatchAtMs = 0;
    publishHerdingOperationSnapshot(true, nullptr);
    return;
  }

  device.assembled = true;
  if (device.assembledAtSec == 0) device.assembledAtSec = unixNowSec();
  if (reason[0] != '\0' &&
      strcmp(reason, "assembled") != 0 &&
      strcmp(reason, "applied") != 0) {
    copyStringToBuffer(device.lastReason, sizeof(device.lastReason), reason);
  } else if (status[0] != '\0' &&
             strcmp(status, "assembled") != 0 &&
             strcmp(status, "applied") != 0) {
    copyStringToBuffer(device.lastReason, sizeof(device.lastReason), status);
  } else {
    device.lastReason[0] = '\0';
  }

  if (allHerdDevicesAssembled() && herdOp.requestedAtSec == 0) {
    herdOp.requestedAtSec = unixNowSec();
  }
  publishHerdingOperationSnapshot(true, nullptr);
}

static void handleHerdingOperationEvent(const LoRaFrame& rx) {
  if (!herdOp.operationId[0] || rx.msgType != MsgType::EVENT) return;

  StaticJsonDocument<256> payload;
  if (deserializeJson(payload, rx.payload, rx.payloadLen) != DeserializationError::Ok) {
    return;
  }

  const char* operationId = payload["operation_id"] | "";
  if (operationId[0] != '\0' && strcmp(operationId, herdOp.operationId) != 0) return;

  String eventType;
  if (payload["event_type"].is<const char*>()) {
    eventType = payload["event_type"].as<const char*>();
  } else if (payload["type"].is<const char*>()) {
    eventType = payload["type"].as<const char*>();
  } else {
    const int eventCode = payload["event_code"].is<int>()
                              ? payload["event_code"].as<int>()
                              : (payload["type"] | 0);
    if (eventCode == 8) eventType = "herd_phase_change";
    if (eventCode == 9) eventType = "herd_done";
  }
  eventType.toLowerCase();
  if (eventType.isEmpty()) return;

  const int idx = findHerdingOperationDevice(rx.deviceId);
  if (idx < 0) return;

  HerdingOperationDeviceState& device = herdOp.devices[idx];
  device.updatedAtMs = (uint32_t)unixNowMs(unixNowSec());

  if (eventType == "herd_phase_change") {
    const int phaseIndex = payload["phase_index"].is<int>()
                               ? payload["phase_index"].as<int>()
                               : (payload["d1"] | device.phaseIndex);
    if (phaseIndex >= 0) device.phaseIndex = (uint8_t)phaseIndex;
    publishHerdingOperationSnapshot(true, nullptr);
    return;
  }

  if (eventType == "herd_done") {
    device.assembled = true;
    device.completed = true;
    device.lastReason[0] = '\0';
    if (device.assembledAtSec == 0) device.assembledAtSec = unixNowSec();
    if (device.completedAtSec == 0) device.completedAtSec = unixNowSec();
    if (allHerdDevicesCompleted() && herdOp.completedAtSec == 0) {
      herdOp.completedAtSec = unixNowSec();
    }
    publishHerdingOperationSnapshot(true, nullptr);
  }
}

static void handleSimpleCommandFeedback(const LoRaFrame& rx) {
  if (!activeSimpleCommand.active) return;
  if (rx.msgType != MsgType::ACK && rx.msgType != MsgType::NACK) return;

  StaticJsonDocument<256> payload;
  if (deserializeJson(payload, rx.payload, rx.payloadLen) != DeserializationError::Ok) {
    return;
  }

  const char* commandId = pickFirstText(payload["cmd_id"], payload["command_id"]);
  if (strcmp(commandId, activeSimpleCommand.commandId) != 0) return;

  char targetId[32]{};
  const char* gatewayId = payload["gateway_id"] | "";
  if (gatewayId[0] != '\0') {
    copyStringToBuffer(targetId, sizeof(targetId), gatewayId);
  } else {
    snprintf(targetId, sizeof(targetId), "%lu", (unsigned long)rx.deviceId);
  }

  const char* reason = payload["reason"] | "";
  const char* status = payload["status"] | (rx.msgType == MsgType::ACK ? "completed" : "nacked");
  markActiveSimpleCommandTarget(targetId, rx.msgType == MsgType::ACK, status, reason);
  if (rx.msgType == MsgType::NACK) {
    publishSimpleCommandResult("nacked", reason[0] ? reason : "nack");
    clearActiveSimpleCommand();
    return;
  }

  if (allActiveSimpleTargetsTerminal()) {
    publishSimpleCommandResult(anyActiveSimpleTargetFailed() ? "failed" : "completed", nullptr);
    clearActiveSimpleCommand();
    return;
  }
  publishSimpleCommandResult("acknowledged", nullptr);
}

static void relayFrameToPeerGateways(const LoRaFrame& rx) {
  if (!cfg::GATEWAY_RELAY_ENABLED) return;
  if (!isRelayCandidate(rx)) return;
  if (!scopeMatchesBinding(rx.scopeId)) return;

  LoRaFrame relay = rx;
  for (int i = 0; i < 12; ++i) relay.nonce[i] = (uint8_t)esp_random();
  if (!lora.send(relay)) {
    LOGW("Falha relay device=%lu seq=%lu", relay.deviceId, relay.seq);
  }
}

static void drawStatus(const char* line1, const char* line2) {
#if RT_MATRIX_OLED_ENABLED
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(WHITE);
  display.setCursor(0, 0);
  display.println("RuralTech Matriz");
  display.println(line1);
  display.println(line2);
  display.display();
#else
  (void)line1;
  (void)line2;
#endif
}

static void checklistLine(
    const char* component,
    bool ok,
    const char* offHint,
    const char* okDetail = nullptr) {
  if (ok) {
    if (okDetail && okDetail[0] != '\0') {
      Serial.printf("[CHECK] %-24s : OK (%s)\n", component, okDetail);
    } else {
      Serial.printf("[CHECK] %-24s : OK\n", component);
    }
    return;
  }
  Serial.printf("[CHECK] %-24s : OFF\n", component);
  if (offHint && offHint[0] != '\0') {
    LOGW("CHECKLIST %s OFF: %s", component, offHint);
  }
}

static void printBootChecklist(
    bool displayOk,
    bool wifiOk,
    bool bleInitOk,
    bool rtcOk,
    bool sdOk,
    bool loraOk,
    bool cloudConfigured) {
  Serial.println("==== HW CHECKLIST | GATEWAY MATRIX ====");
  checklistLine(
      "NVS_SEQ_DOWN",
      seqPrefsReady,
      "Falha ao abrir NVS lora_down; revisar flash/NVS.");
#if RT_MATRIX_OLED_ENABLED
  checklistLine(
      "OLED_0x3C",
      displayOk,
      "OLED nao inicializou; revisar SDA/SCL, VCC, GND e endereco 0x3C.");
#else
  checklistLine("OLED_0x3C", true, nullptr, "desabilitado em config");
#endif
  checklistLine(
      "WIFI_AP_OTA",
      !wifiOtaEnabled || wifiOk,
      "wifi_ota_enabled=true sem AP/OTA; revisar SSID/AP e RF.");
  checklistLine(
      "BLE_PRESENCE",
      !cfg::BLE_PRESENCE_ENABLED || bleInitOk,
      "BLE nao inicializou; revisar memoria BT e stack.");
  checklistLine(
      "API_HTTP_WS",
      true,
      nullptr,
      "porta 80 + ws:81");
  checklistLine(
      "RTC_DS3231",
      rtcOk,
      "RTC indisponivel; revisar SDA/SCL, VCC, GND e bateria.");
  checklistLine(
      "SD_CARD",
      sdOk,
      "SD indisponivel; revisar CS/MOSI/MISO/SCK e cartao.");
  checklistLine(
      "LORA_RFM95",
      loraOk,
      "Falha LoRa begin; revisar CS/RST/DIO0/DIO1, antena e modulo.");
  checklistLine(
      "CLOUD_BACKHAUL_CFG",
      cloudConfigured,
      "Telemetria cloud sem credenciais validas; revisar manual_settings.local.h.");
  Serial.println("=======================================");
}

void setup() {
  Serial.begin(cfg::SERIAL_BAUD);
  LOGI("Boot reset_reason=%d", (int)esp_reset_reason());
#if defined(ESP_IDF_VERSION_MAJOR) && ESP_IDF_VERSION_MAJOR >= 5
  esp_task_wdt_config_t wdtConfig = {};
  wdtConfig.timeout_ms = (uint32_t)cfg::TASK_WDT_TIMEOUT_SEC * 1000U;
  wdtConfig.idle_core_mask = 0;
  wdtConfig.trigger_panic = true;
  esp_err_t wdtErr = esp_task_wdt_reconfigure(&wdtConfig);
  if (wdtErr == ESP_ERR_INVALID_STATE) {
    wdtErr = esp_task_wdt_init(&wdtConfig);
  }
  if (wdtErr != ESP_OK) {
    LOGW("TWDT setup retornou err=%d", (int)wdtErr);
  }
#else
  esp_task_wdt_init(cfg::TASK_WDT_TIMEOUT_SEC, true);
#endif
  WiFi.onEvent(onWifiEvent);
  restoreDownlinkSeq();
  loadBindingConfig();

  Wire.begin(cfg::PIN_I2C_SDA, cfg::PIN_I2C_SCL);
  bool displayOk = true;
#if RT_MATRIX_OLED_ENABLED
  displayOk = display.begin(SSD1306_SWITCHCAPVCC, 0x3C);
  if (!displayOk) LOGW("OLED indisponivel");
#endif
  drawStatus("Boot", cfg::FW_VERSION);

  bool wifiOk = !cfg::FEATURE_WIFI_AP;
  if (cfg::FEATURE_WIFI_AP && wifiOtaEnabled) {
    wifiOk = setupWiFi();
    if (wifiOk) setupOta();
  }
  bool bleInitOk = !cfg::FEATURE_BLE;
  if (cfg::FEATURE_BLE) {
    const String nodeId = gatewayNodeId();
    bleInitOk = blePresence.begin(
        BleNodeKind::MATRIX,
        nodeId,
        gatewayAdvName(nodeId),
        cfg::BLE_COMPANY_ID,
        cfg::BLE_SERVICE_UUID);
    blePresence.setEnabled(shouldBlePresenceBeEnabled());
    blePresence.setFlags(wifiOtaEnabled, WiFi.status() == WL_CONNECTED);
  }
  if (cfg::FEATURE_HTTP || cfg::FEATURE_WS) {
    api.begin();
  }
  const bool rtcOk = rtc.begin();
  if (!rtcOk) LOGW("RTC indisponivel");
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");

  bool sdOk = !cfg::FEATURE_SD;
  if (cfg::FEATURE_SD) {
    sdOk = sdlog.begin(cfg::PIN_SD_CS);
    if (!sdOk) LOGW("SD indisponivel");
  }
  const bool loraOk = lora.begin();
  if (!loraOk) LOGE("LoRa indisponivel");
  const bool cloudConfigured = cloudTelemetryConfigured();
  setWatchdogEnabled(wifiOtaEnabled);
  printBootChecklist(
      displayOk,
      wifiOk,
      bleInitOk,
      rtcOk,
      sdOk,
      loraOk,
      cloudConfigured);
  if (bindingReady) publishMatrixRuntimeMirrors(true);

  LOGI("Gateway matriz pronto fw=%s", cfg::FW_VERSION);
}

void loop() {
  feedWatchdogIfEnabled();
  ensureWifiOtaServices();
  feedWatchdogIfEnabled();
  if (cfg::FEATURE_BACKHAUL) {
    ensureCloudBackhaulConnected();
  }
  if (cfg::FEATURE_CLOUD) {
    publishMatrixRuntimeMirrors(false);
  }
  feedWatchdogIfEnabled();
  const bool apClientConnected = wifiApClientConnected();
  if (wifiOtaEnabled && cfg::FEATURE_OTA && cfg::OTA_ENABLED) {
    ArduinoOTA.handle();
    feedWatchdogIfEnabled();
    if (otaUploadInProgress) {
      delay(2);
      return;
    }
  }
  if (apClientConnected) {
    static uint32_t lastApClientLoopLogAtMs = 0;
    const uint32_t now = millis();
    if (now - lastApClientLoopLogAtMs >= 10000UL) {
      lastApClientLoopLogAtMs = now;
      LOGI("Cliente no AP ativo; mantendo loop LoRa/cloud (n=%d)", WiFi.softAPgetStationNum());
    }
  }
  if (cfg::FEATURE_BLE) {
    const bool bleEnabled = shouldBlePresenceBeEnabled();
    blePresence.setEnabled(bleEnabled);
    blePresence.setFlags(wifiOtaEnabled, WiFi.status() == WL_CONNECTED);
    if (bleEnabled) blePresence.loop();
  }
  feedWatchdogIfEnabled();
  if ((cfg::FEATURE_HTTP || cfg::FEATURE_WS) &&
      (!cfg::FEATURE_WIFI_AP || (wifiOtaEnabled && WiFi.getMode() != WIFI_OFF))) {
    api.loop();
  }
  feedWatchdogIfEnabled();

  LoRaFrame rx;
  if (lora.receive(rx)) {
    if (!scopeMatchesBinding(rx.scopeId)) {
      LOGW(
          "scope_reject device=%lu msg=%u seq=%lu scope=%s ready=%d",
          (unsigned long)rx.deviceId,
          (unsigned)rx.msgType,
          (unsigned long)rx.seq,
          scopeIdToHex(rx.scopeId).c_str(),
          bindingReady ? 1 : 0);
    } else {
      if (rx.msgType == MsgType::SET_PARAMS) {
        StaticJsonDocument<256> params;
        if (deserializeJson(params, rx.payload, rx.payloadLen) == DeserializationError::Ok) {
          bool wifiEnabled = false;
          const JsonVariantConst payload = params.as<JsonVariantConst>();
          const bool hasWifiField = parseWifiOtaParam(payload, wifiEnabled);
          const JsonVariantConst requestedByAdmin = payload["requested_by_admin"];
          const rtcmd::ValidationCode setParamsCode = rtcmd::validateSetParamsPayload(
              hasWifiField,
              wifiEnabled,
              requestedByAdmin.is<bool>() && requestedByAdmin.as<bool>(),
              payload["requested_by_role"] | "",
              payload["actor_role"] | "");
          if (setParamsCode == rtcmd::ValidationCode::kOk && targetIncludesGateway(payload)) {
            applyWifiOtaMode(wifiEnabled, "LoRa");
          } else if (setParamsCode == rtcmd::ValidationCode::kAdminRequiredForLoraOnly) {
            LOGW("SET_PARAMS LoRa rejeitado: admin requerido para LoRa-only");
          }
        }
      }

      handleSimpleCommandFeedback(rx);
      handleHerdingOperationFeedback(rx);
      handleHerdingOperationEvent(rx);
      relayFrameToPeerGateways(rx);

      StaticJsonDocument<576> packet;
      packet["type"] = uplinkTypeLabel(rx.msgType);
      packet["device_id"] = rx.deviceId;
      packet["msg_type"] = (int)rx.msgType;
      packet["seq"] = rx.seq;
      packet["timestamp"] = rx.timestamp;
      packet["scope_id"] = scopeIdToHex(rx.scopeId);
      packet["gateway_id"] = gatewayNodeId();
      packet["gateway_role"] = "matrix";
      packet["gateway_wifi_ota_enabled"] = wifiOtaEnabled;
      packet["payload"] = String((char*)rx.payload).substring(0, rx.payloadLen);
      String out;
      serializeJson(packet, out);
      api.broadcastTelemetry(out);
      if (cfg::FEATURE_SD) sdlog.log(String("UL|") + out);
      drawStatus("RX LoRa", out.substring(0, 16).c_str());

      if (cfg::FEATURE_CLOUD) {
        publishTelemetryToCloud(rx);
        publishDailyHealthToCloud(rx);
        publishEventToCloud(rx);
      }
    }
  }
  feedWatchdogIfEnabled();

  if (api.hasPendingCommand()) {
    StaticJsonDocument<4096> cmd;
    if (api.popCommand(cmd)) {
      const String type = cmd["type"] | "send_command";
      if (type == "start_herding_operation") {
        const JsonVariantConst payload = cmd["payload"].as<JsonVariantConst>();
        const char* failReason = nullptr;
        const bool ok = startHerdingOperation(payload, &failReason);
        StaticJsonDocument<256> res;
        res["type"] = "herding_operation_update";
        res["operation_id"] = payload["operation_id"] | "";
        res["status"] = ok ? "dispatching" : "failed";
        res["ok"] = ok;
        if (!ok && failReason) res["reason"] = failReason;
        String out;
        serializeJson(res, out);
        api.broadcastTelemetry(out);
        if (cfg::FEATURE_SD) sdlog.log(String("HERD_CMD|") + out);
      } else {
        const String command = cmd["command"] | "PING";
        const JsonVariantConst payload = cmd["payload"].as<JsonVariantConst>();
        bool handledLocally = false;
        if (command == "SET_BINDING") {
          const char* failReason = nullptr;
          const bool ok = persistBindingConfig(payload, &failReason);
          StaticJsonDocument<256> res;
          res["type"] = "command_result";
          res["ok"] = ok;
          res["command"] = command;
          res["supports_scoped_lora"] = true;
          res["binding_ready"] = bindingReady;
          if (bindingPropertyId[0]) res["property_id"] = bindingPropertyId;
          if (bindingPropertyScopeId[0]) res["property_scope_id"] = bindingPropertyScopeId;
          if (bindingMatrixGatewayId[0]) res["matrix_gateway_id"] = bindingMatrixGatewayId;
          res["binding_version"] = bindingVersion;
          if (!ok && failReason) res["reason"] = failReason;
          String out;
          serializeJson(res, out);
          api.broadcastTelemetry(out);
          if (cfg::FEATURE_SD) sdlog.log(String("CFG|") + out);
          if (ok && cfg::FEATURE_CLOUD) publishMatrixRuntimeMirrors(true);
          publishHerdingOperationSnapshot(false, nullptr);
          handledLocally = true;
        }

        if (handledLocally) {
          dispatchActiveHerdingOperation();
          feedWatchdogIfEnabled();
          return;
        }

        bool localToggleRequested = false;
        bool localWifiEnabled = wifiOtaEnabled;
        bool requestedWifiEnabled = true;
        rtcmd::ValidationCode setParamsCode = rtcmd::ValidationCode::kOk;
        if (command == "SET_PARAMS") {
          const bool hasWifiField =
              parseWifiOtaParam(payload, requestedWifiEnabled);
          const JsonVariantConst requestedByAdmin = payload["requested_by_admin"];
          setParamsCode = rtcmd::validateSetParamsPayload(
              hasWifiField,
              requestedWifiEnabled,
              requestedByAdmin.is<bool>() && requestedByAdmin.as<bool>(),
              payload["requested_by_role"] | "",
              payload["actor_role"] | "");
          if (setParamsCode == rtcmd::ValidationCode::kOk &&
              targetIncludesGateway(payload)) {
            localToggleRequested = true;
            localWifiEnabled = requestedWifiEnabled;
          }
        }

        const uint32_t deviceId = cmd["device_id"] | 0;
        bool shouldRelayLoRa = !(command == "SET_PARAMS" && !targetIncludesCollars(payload));
        const bool setParamsRejected =
            command == "SET_PARAMS" && setParamsCode != rtcmd::ValidationCode::kOk;
        const uint64_t commandScopeId = parseScopeIdHex(payload["scope_id"]);
        if (!bindingReady) {
          shouldRelayLoRa = false;
        } else if (commandScopeId != 0 && !scopeMatchesBinding(commandScopeId)) {
          shouldRelayLoRa = false;
        }
        if (setParamsRejected) {
          shouldRelayLoRa = false;
          localToggleRequested = false;
        }

        const MsgType msgType = command == "SET_FENCE" ? MsgType::SET_FENCE :
                                command == "SET_HERDING_PLAN" ? MsgType::SET_HERDING_PLAN :
                                command == "SET_PARAMS" ? MsgType::SET_PARAMS : MsgType::PING;

        bool ok = true;
        const char* failReason = nullptr;
        if (setParamsRejected) {
          ok = false;
          failReason = rtcmd::validationCodeToReason(setParamsCode);
        } else if (!bindingReady) {
          ok = false;
          failReason = "property_binding_missing";
        } else if (commandScopeId != 0 && !scopeMatchesBinding(commandScopeId)) {
          ok = false;
          failReason = "property_scope_mismatch";
        } else if (shouldRelayLoRa) {
          if (command == "SET_FENCE") {
            ok = sendFenceCommandChunked(deviceId, payload, &failReason);
          } else if (command == "SET_HERDING_PLAN") {
            ok = sendHerdingPlanChunked(deviceId, payload, &failReason);
          } else {
            ok = sendLoRaJsonFrame(deviceId, msgType, payload, &failReason);
          }
        }

        StaticJsonDocument<256> res;
        res["type"] = "command_result";
        res["ok"] = ok;
        res["device_id"] = deviceId;
        res["command"] = command;
        if (!ok && failReason) res["reason"] = failReason;
        String out;
        serializeJson(res, out);
        api.broadcastTelemetry(out);
        if (cfg::FEATURE_SD) sdlog.log(String("DL|") + out);

        if (localToggleRequested) {
          applyWifiOtaMode(localWifiEnabled, "WiFi");
        } else {
          publishHerdingOperationSnapshot(false, nullptr);
        }
      }
    }
  }

  if (activeSimpleCommand.active) {
    const uint64_t nowMs = unixNowMs(unixNowSec());
    if (activeSimpleCommand.expiresAtMs != 0 && nowMs >= activeSimpleCommand.expiresAtMs) {
      publishSimpleCommandResult("failed", "command_timeout");
      clearActiveSimpleCommand();
    }
  }

  if (cfg::FEATURE_CLOUD) processNextQueuedCommand();
  dispatchActiveHerdingOperation();
  feedWatchdogIfEnabled();

  delay(5);
}
