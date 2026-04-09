/**
 * @file coleira.ino
 * @brief Firmware principal da coleira RuralTech (ESP32 + GPS + LoRa + sensores).
 * @version 1.0.0
 * @date 2026-02-18
 *
 * Risco e segurança: pulso elétrico só ocorre após escalonamento e com hard-limits locais,
 * mesmo sem gateway. Em perda de GPS, sistema degrada para modo seguro sem pulso.
 */
#if !defined(ARDUINO_PARTITION_min_spiffs)
#error "Selecione Partition Scheme: Minimal SPIFFS (1.9MB APP with OTA/128KB SPIFFS)."
#endif

#include <Arduino.h>
#include <ArduinoJson.h>
#include <WiFi.h>
#include <WebServer.h>
#include <ArduinoOTA.h>
#include <ESPmDNS.h>
#include <Preferences.h>
#include <math.h>
#include <esp_task_wdt.h>
#include <esp_heap_caps.h>
#include <esp_sleep.h>
#include <esp_system.h>
#include <esp_ota_ops.h>
#if __has_include(<esp_idf_version.h>)
#include <esp_idf_version.h>
#endif
#include "config.h"
#include "Logger.h"
#include "SensorsManager.h"
#include "SmartGps.h"
#include "Geofence.h"
#include "SafetyController.h"
#include "StorageQueue.h"
#include "LoRaManager.h"
#include "BlePresence.h"
#include "HerdingController.h"
#include "StateMachine.h"
#include "../firmware/shared/command_contract.h"

SensorsManager sensors;
SmartGps smartGps;
Geofence geofence;
SafetyController safety;
StorageQueue storage;
LoRaManager lora;
BlePresence blePresence;
HerdingController herding;
StateMachine stateMachine;
WebServer statusServer(80);
extern bool loopTaskWDTEnabled;

RTC_DATA_ATTR uint32_t seq = 1;
RTC_DATA_ATTR uint64_t healthFallbackAccumMs_ = 0;
uint32_t seqPersistedHi_ = 0;
bool seqPersistReady_ = false;
uint32_t lastCycle = 0;
uint32_t violationStart = 0;
bool wasInside = true;
bool otaModeActive = false;
bool wifiOtaEnabled = cfg::WIFI_OTA_DEFAULT_ENABLED;
bool watchdogTaskRegistered = false;
TaskHandle_t watchdogOwnerTask = nullptr;
bool otaUploadInProgress = false;
uint32_t wifiOtaEnabledAtMs = 0;
uint32_t otaApLastClientSeenMs = 0;
uint32_t otaRecoveryAttemptAtMs = 0;
uint8_t otaRecoveryAttemptCount = 0;
bool statusServerRoutesConfigured_ = false;
bool statusServerRunning_ = false;
Preferences prefs_;
bool prefsReady_ = false;
char bindingPropertyId_[48]{};
char bindingPropertyScopeId_[17]{};
char bindingMatrixGatewayId_[32]{};
uint32_t bindingVersion_ = 0;
bool bindingReady_ = false;
bool supportsScopedLora_ = true;
GpsData lastGpsForStatus_;
bool hasLastGpsForStatus_ = false;
uint32_t lastHealthReportDayKey_ = 0;
bool storageReady_ = false;
bool loraReady_ = false;
bool lastLoRaTxOk_ = false;
uint32_t lastGpsFailEventAtMs_ = 0;
uint32_t lastGpsInvalidFixEventAtMs_ = 0;
uint32_t lastGpsOutlierEventAtMs_ = 0;
bool gpsFailEventActive_ = false;
uint32_t bootStartedAtMs_ = 0;
uint32_t rebootCounter_ = 0;
uint32_t bootMinFreeHeap_ = 0xFFFFFFFFUL;
esp_reset_reason_t lastResetReason_ = ESP_RST_UNKNOWN;
bool maintenanceWindowActive_ = false;
char bootStage_[32] = "boot";
static void logEvent(EventType type, int32_t d1, int32_t d2);
static void logPolygonApplyResult(
    MsgType commandType,
    uint64_t scopeId,
    PolygonKind polygonKind,
    OriginDocType originDocType,
    const char* originDocId,
    const char* commandId,
    bool ok,
    const char* errorCode = nullptr,
    PolygonErrorStage errorStage = PolygonErrorStage::NONE,
    int32_t pointCount = 0,
    int32_t phaseCount = 0);
static void copyStringToBuffer(char* dst, size_t dstSize, const char* src);
static const char* eventTypeLabel(EventType type);
static const char* commandLabel(MsgType type);
static const char* polygonKindLabel(PolygonKind kind);
static const char* originDocTypeLabel(OriginDocType type);
static const char* polygonApplyStatusLabel(PolygonApplyStatus status);
static const char* polygonErrorStageLabel(PolygonErrorStage stage);
static PolygonKind polygonKindFromText(const char* raw);
static OriginDocType originDocTypeFromText(const char* raw);
static PolygonErrorStage polygonErrorStageFromReason(const char* reason);
static void extractCommandMetadataFromPayload(
    const LoRaFrame& frame,
    char* commandId,
    size_t commandIdSize);
static const char* activeHerdOperationId();
static void promoteCompletedHerdingFence();
static bool isValidPolygon(const Polygon& p);
static bool beginPrefs();
static void loadBindingConfig();
static bool persistBindingConfig(
    const JsonVariantConst payload,
    const char** reason = nullptr);
static bool gpsFixUsableForOnboarding(const GpsData& gps);
static void updateBlePositionForOnboarding(
    const GpsData* preferred,
    const GpsData* fallback = nullptr);
static void refreshBlePositionForOnboarding();
static void printBootChecklist(bool bleInitOk, bool storageOk, bool loraOk);
static void runSmartGpsSelfTest();
static uint32_t gpsDayKey(const GpsData& gps);
static void persistHealthReportDayKey(uint32_t dayKey);
static uint32_t loadPersistedHealthReportDayKey();
static bool sendDailyHealthReport(const Telemetry& t, uint32_t intervalMs);
static TaskHandle_t watchdogTargetTask();
static void recordBootStage(const char* stage);
static void incrementBootCounter();
static void waitMaintenanceWindow();
static void configureStatusServerRoutes();
static void ensureStatusServerRunning();
static void stopStatusServer();

struct PolygonAuditContext {
  uint64_t scopeId = 0;
  MsgType commandType = MsgType::SET_FENCE;
  PolygonKind polygonKind = PolygonKind::NONE;
  OriginDocType originDocType = OriginDocType::NONE;
  char originDocId[cfg::EVENT_ORIGIN_DOC_ID_MAX_LEN]{};
  char commandId[cfg::EVENT_COMMAND_ID_MAX_LEN]{};
};

struct FenceChunkRxState {
  bool active = false;
  uint8_t totalParts = 0;
  uint8_t expectedPart = 0;
  Polygon fence{};
  PolygonAuditContext audit{};
} fenceChunkRx_;

struct HerdChunkRxState {
  bool active = false;
  uint8_t phaseTotal = 0;
  uint8_t currentPhase = 0;
  uint8_t expectedPart = 0;
  uint8_t totalPartsCurrentPhase = 0;
  Polygon phaseAccum{};
  HerdingPlan plan{};
  PolygonAuditContext audit{};
} herdChunkRx_;

static void randomNonce(uint8_t* nonce12) {
  for (int i = 0; i < 12; ++i) nonce12[i] = (uint8_t)esp_random();
}

static String scopeIdToHex(uint64_t scopeId) {
  char out[17];
  snprintf(out, sizeof(out), "%016llX", (unsigned long long)scopeId);
  return String(out);
}

static uint64_t parseScopeIdHex(const char* raw) {
  if (!raw || !raw[0]) return 0;
  return strtoull(raw, nullptr, 16);
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

static bool computeBindingReadyState() {
  return bindingPropertyId_[0] != '\0' &&
         bindingMatrixGatewayId_[0] != '\0' &&
         rtcmd::isValidScopeId(bindingPropertyScopeId_);
}

static uint64_t bindingScopeIdValue() {
  if (!computeBindingReadyState()) return 0;
  return strtoull(bindingPropertyScopeId_, nullptr, 16);
}

static void copyStringToBuffer(char* dst, size_t dstSize, const char* src) {
  if (dstSize == 0) return;
  if (!src) {
    dst[0] = '\0';
    return;
  }
  strncpy(dst, src, dstSize - 1);
  dst[dstSize - 1] = '\0';
}

static void recordBootStage(const char* stage) {
  copyStringToBuffer(bootStage_, sizeof(bootStage_), stage ? stage : "boot");
  const uint32_t freeHeap = ESP.getFreeHeap();
  const uint32_t minHeap = ESP.getMinFreeHeap();
  if (freeHeap < bootMinFreeHeap_) bootMinFreeHeap_ = freeHeap;
  if (minHeap < bootMinFreeHeap_) bootMinFreeHeap_ = minHeap;
  const bool heapOk = heap_caps_check_integrity_all(true);
  LOGI(
      "BOOT stage=%s free_heap=%lu min_heap=%lu heap_ok=%d",
      bootStage_,
      (unsigned long)freeHeap,
      (unsigned long)bootMinFreeHeap_,
      heapOk ? 1 : 0);
}

static void incrementBootCounter() {
  if (!beginPrefs()) return;
  rebootCounter_ = prefs_.getUInt(cfg::PREF_KEY_REBOOT_COUNT, 0) + 1U;
  prefs_.putUInt(cfg::PREF_KEY_REBOOT_COUNT, rebootCounter_);
}

static void waitMaintenanceWindow() {
  if (!wifiOtaEnabled || cfg::MAINTENANCE_BOOT_WINDOW_MS == 0) return;
  maintenanceWindowActive_ = true;
  recordBootStage("maintenance_window");
  const uint32_t startedAtMs = millis();
  LOGI(
      "Janela de manutencao segura por %lu ms antes do boot pesado",
      (unsigned long)cfg::MAINTENANCE_BOOT_WINDOW_MS);
  while ((uint32_t)(millis() - startedAtMs) < cfg::MAINTENANCE_BOOT_WINDOW_MS) {
    if (statusServerRunning_) {
      statusServer.handleClient();
      if (cfg::OTA_ENABLED) ArduinoOTA.handle();
    }
    delay(20);
  }
  maintenanceWindowActive_ = false;
}

static void loadBindingConfig() {
  bindingPropertyId_[0] = '\0';
  bindingPropertyScopeId_[0] = '\0';
  bindingMatrixGatewayId_[0] = '\0';
  bindingVersion_ = 0;
  bindingReady_ = false;
  if (beginPrefs()) {
    prefs_.getString("property_id", bindingPropertyId_, sizeof(bindingPropertyId_));
    prefs_.getString("scope_id", bindingPropertyScopeId_, sizeof(bindingPropertyScopeId_));
    prefs_.getString("matrix_gid", bindingMatrixGatewayId_, sizeof(bindingMatrixGatewayId_));
    bindingVersion_ = prefs_.getUInt("bind_ver", 0);
  }

  if (!computeBindingReadyState()) {
    copyStringToBuffer(
        bindingPropertyId_, sizeof(bindingPropertyId_), cfg_manual::DEFAULT_PROPERTY_ID);
    copyStringToBuffer(
        bindingPropertyScopeId_,
        sizeof(bindingPropertyScopeId_),
        cfg_manual::DEFAULT_PROPERTY_SCOPE_ID);
    copyStringToBuffer(
        bindingMatrixGatewayId_,
        sizeof(bindingMatrixGatewayId_),
        cfg_manual::DEFAULT_MATRIX_GATEWAY_ID);
    bindingVersion_ = cfg_manual::DEFAULT_BINDING_VERSION;
  }

  bindingReady_ = computeBindingReadyState();
  LOGI(
      "Binding coleira: ready=%d property=%s scope=%s matrix=%s ver=%lu",
      bindingReady_ ? 1 : 0,
      bindingPropertyId_[0] ? bindingPropertyId_ : "-",
      bindingPropertyScopeId_[0] ? bindingPropertyScopeId_ : "-",
      bindingMatrixGatewayId_[0] ? bindingMatrixGatewayId_ : "-",
      (unsigned long)bindingVersion_);
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
  if (!beginPrefs()) {
    if (reason) *reason = "binding_prefs_unavailable";
    return false;
  }

  copyStringToBuffer(bindingPropertyId_, sizeof(bindingPropertyId_), propertyId);
  copyStringToBuffer(
      bindingPropertyScopeId_, sizeof(bindingPropertyScopeId_), propertyScopeId);
  copyStringToBuffer(
      bindingMatrixGatewayId_, sizeof(bindingMatrixGatewayId_), matrixGatewayId);
  bindingVersion_ = nextBindingVersion;
  bindingReady_ = computeBindingReadyState();

  prefs_.putString("property_id", bindingPropertyId_);
  prefs_.putString("scope_id", bindingPropertyScopeId_);
  prefs_.putString("matrix_gid", bindingMatrixGatewayId_);
  prefs_.putUInt("bind_ver", bindingVersion_);
  return bindingReady_;
}

static const char* commandLabel(MsgType type) {
  switch (type) {
    case MsgType::SET_FENCE:
      return "SET_FENCE";
    case MsgType::SET_HERDING_PLAN:
      return "SET_HERDING_PLAN";
    case MsgType::SET_PARAMS:
      return "SET_PARAMS";
    case MsgType::PING:
      return "PING";
    default:
      return "UNKNOWN";
  }
}

static const char* eventTypeLabel(EventType type) {
  switch (type) {
    case EventType::APPROACH:
      return "approach";
    case EventType::VIOLATION:
      return "violation";
    case EventType::RETURNED:
      return "returned";
    case EventType::PULSE_APPLIED:
      return "pulse_applied";
    case EventType::GPS_FAIL:
      return "gps_fail";
    case EventType::NO_MOTION:
      return "no_motion";
    case EventType::HERD_START:
      return "herd_start";
    case EventType::HERD_PHASE_CHANGE:
      return "herd_phase_change";
    case EventType::HERD_DONE:
      return "herd_done";
    case EventType::GPS_INVALID_FIX:
      return "gps_invalid_fix";
    case EventType::GPS_OUTLIER:
      return "gps_outlier";
    case EventType::GPS_LOCKED:
      return "gps_locked";
    case EventType::GPS_UNLOCKED:
      return "gps_unlocked";
    case EventType::POLYGON_APPLY_RESULT:
      return "polygon_apply_result";
  }
  return "event";
}

static const char* polygonKindLabel(PolygonKind kind) {
  switch (kind) {
    case PolygonKind::PROPERTY:
      return "property";
    case PolygonKind::AREA:
      return "area";
    case PolygonKind::HERDING:
      return "herding";
    case PolygonKind::NONE:
      break;
  }
  return "";
}

static const char* originDocTypeLabel(OriginDocType type) {
  switch (type) {
    case OriginDocType::RURAL_PROPERTY:
      return "ruralProperty";
    case OriginDocType::AREA:
      return "area";
    case OriginDocType::HERDING_OPERATION:
      return "herdingOperation";
    case OriginDocType::NONE:
      break;
  }
  return "";
}

static const char* polygonApplyStatusLabel(PolygonApplyStatus status) {
  switch (status) {
    case PolygonApplyStatus::SUCCESS:
      return "success";
    case PolygonApplyStatus::FAILURE:
      return "failure";
    case PolygonApplyStatus::NONE:
      break;
  }
  return "";
}

static const char* polygonErrorStageLabel(PolygonErrorStage stage) {
  switch (stage) {
    case PolygonErrorStage::PARSE:
      return "parse";
    case PolygonErrorStage::ASSEMBLE:
      return "assemble";
    case PolygonErrorStage::PERSIST:
      return "persist";
    case PolygonErrorStage::ACTIVATE:
      return "activate";
    case PolygonErrorStage::SCOPE:
      return "scope";
    case PolygonErrorStage::BINDING:
      return "binding";
    case PolygonErrorStage::NONE:
      break;
  }
  return "";
}

static PolygonKind polygonKindFromText(const char* raw) {
  if (!raw || raw[0] == '\0') return PolygonKind::NONE;
  if (strcasecmp(raw, "property") == 0) return PolygonKind::PROPERTY;
  if (strcasecmp(raw, "area") == 0) return PolygonKind::AREA;
  if (strcasecmp(raw, "herding") == 0) return PolygonKind::HERDING;
  return PolygonKind::NONE;
}

static OriginDocType originDocTypeFromText(const char* raw) {
  if (!raw || raw[0] == '\0') return OriginDocType::NONE;
  if (strcasecmp(raw, "ruralProperty") == 0) {
    return OriginDocType::RURAL_PROPERTY;
  }
  if (strcasecmp(raw, "area") == 0) return OriginDocType::AREA;
  if (strcasecmp(raw, "herdingOperation") == 0) {
    return OriginDocType::HERDING_OPERATION;
  }
  return OriginDocType::NONE;
}

static PolygonErrorStage polygonErrorStageFromReason(const char* reason) {
  if (!reason || reason[0] == '\0') return PolygonErrorStage::NONE;
  if (strcmp(reason, "property_binding_missing") == 0 ||
      strcmp(reason, "binding_prefs_unavailable") == 0) {
    return PolygonErrorStage::BINDING;
  }
  if (strcmp(reason, "property_scope_mismatch") == 0) {
    return PolygonErrorStage::SCOPE;
  }
  if (strstr(reason, "chunk") != nullptr ||
      strstr(reason, "phase_out_of_order") != nullptr ||
      strstr(reason, "phase_total_mismatch") != nullptr ||
      strstr(reason, "operation_id_mismatch") != nullptr ||
      strstr(reason, "missing_chunk_start") != nullptr ||
      strstr(reason, "missing_phase_start") != nullptr ||
      strstr(reason, "too_many_points") != nullptr) {
    return PolygonErrorStage::ASSEMBLE;
  }
  if (strstr(reason, "persist") != nullptr ||
      strstr(reason, "prefs") != nullptr) {
    return PolygonErrorStage::PERSIST;
  }
  if (strstr(reason, "invalid_") != nullptr ||
      strstr(reason, "missing_") != nullptr) {
    return PolygonErrorStage::PARSE;
  }
  return PolygonErrorStage::ACTIVATE;
}

static const char* activeHerdOperationId() {
  return herding.plan().operationId;
}

static bool persistLoRaSeqHighWatermark(uint32_t hi) {
  if (!beginPrefs()) return false;
  if (prefs_.putULong(cfg::PREF_KEY_LORA_SEQ_HI, hi) != sizeof(uint32_t)) {
    LOGW("Falha ao persistir seq uplink hi=%lu", hi);
    return false;
  }
  return true;
}

static void restoreLoRaSeq() {
  constexpr uint32_t kSeqBootStride = 1000000UL;
  if (seq == 0) seq = 1;
  if (!beginPrefs()) {
    seqPersistReady_ = false;
    const uint32_t bootIndex = rebootCounter_ == 0 ? 1U : rebootCounter_;
    const uint64_t derivedNext = (uint64_t)bootIndex * (uint64_t)kSeqBootStride + 1ULL;
    if (derivedNext > seq) {
      seq = derivedNext > 0xFFFFFFFFULL ? 0xFFFFFFFFUL : (uint32_t)derivedNext;
    }
    seqPersistedHi_ = seq - 1;
    LOGW(
        "NVS indisponivel para seq uplink; fallback boot-stride next=%lu reboot=%lu",
        seq,
        (unsigned long)rebootCounter_);
    return;
  }

  const uint32_t persistedHi = prefs_.getULong(cfg::PREF_KEY_LORA_SEQ_HI, 0);
  seqPersistedHi_ = persistedHi;
  seqPersistReady_ = true;
  if (persistedHi >= seq) {
    seq = persistedHi + 1;
    if (seq == 0) seq = 1;
  }
  // Mitigacao de bancada: a escrita recorrente do high-watermark em Preferences
  // esta disparando panic de alinhamento nesta placa. Mantemos a restauracao do
  // ultimo valor salvo e seguimos com monotonicidade via RTC + stride por boot.
  seqPersistReady_ = false;
  const uint32_t bootIndex = rebootCounter_ == 0 ? 1U : rebootCounter_;
  const uint64_t derivedNext = (uint64_t)bootIndex * (uint64_t)kSeqBootStride + 1ULL;
  if (derivedNext > seq) {
    seq = derivedNext > 0xFFFFFFFFULL ? 0xFFFFFFFFUL : (uint32_t)derivedNext;
  }
  LOGW(
      "Seq uplink restaurado next=%lu hi=%lu reboot=%lu (persistencia write-through desabilitada)",
      seq,
      seqPersistedHi_,
      (unsigned long)rebootCounter_);
}

static void ensureLoRaSeqReservation(uint32_t nextSeq) {
  if (!seqPersistReady_) return;
  if (nextSeq <= seqPersistedHi_) return;

  uint32_t newHi = nextSeq + (uint32_t)cfg::LORA_SEQ_RESERVE_WINDOW - 1U;
  if (newHi < nextSeq) newHi = 0xFFFFFFFFUL;
  if (persistLoRaSeqHighWatermark(newHi)) {
    seqPersistedHi_ = newHi;
    return;
  }

  // Evita tentativa de escrita em toda telemetria quando NVS estiver indisponível.
  seqPersistReady_ = false;
}

static uint32_t nextLoRaSeq() {
  // Mantem monotonicidade entre deep sleep (RTC) e reboot/power-cycle (NVS).
  if (seq == 0) seq = 1;
  ensureLoRaSeqReservation(seq);
  const uint32_t out = seq++;
  if (seq == 0) seq = 1;
  return out;
}

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

static String collarNodeId() { return String((uint32_t)cfg::DEVICE_ID); }

static String collarAdvName() {
  return String(cfg::BLE_DEVICE_PREFIX) + "-" + collarNodeId();
}

static String collarApSsid() {
  char suffix[7] = {};
  snprintf(
      suffix,
      sizeof(suffix),
      "%06lX",
      (unsigned long)((uint32_t)cfg::DEVICE_ID & 0xFFFFFFUL));

  char ssid[32] = {};
  snprintf(ssid, sizeof(ssid), "%s-%s", cfg::OTA_AP_SSID, suffix);
  ssid[sizeof(ssid) - 1] = '\0';
  return String(ssid);
}

static void configureStatusServerRoutes() {
  if (statusServerRoutesConfigured_) return;
  statusServer.on("/status", HTTP_GET, []() {
    StaticJsonDocument<768> doc;
    doc["ok"] = true;
    doc["service"] = "collar";
    doc["fw"] = cfg::FW_VERSION;
    doc["deviceId"] = (uint32_t)cfg::DEVICE_ID;
    doc["device_id"] = String((uint32_t)cfg::DEVICE_ID);
    const String apSsid = WiFi.softAPSSID();
    doc["ap_ssid"] = apSsid.isEmpty() ? collarApSsid() : apSsid;
    doc["ap_ip"] = WiFi.softAPIP().toString();
    doc["ota"] = cfg::OTA_ENABLED;
    doc["wifi_ota_enabled"] = wifiOtaEnabled;
    doc["ota_mode_active"] = otaModeActive;
    doc["maintenanceWindowActive"] = maintenanceWindowActive_;
    doc["supportsScopedLora"] = supportsScopedLora_;
    doc["bindingReady"] = bindingReady_;
    doc["bindingVersion"] = bindingVersion_;
    doc["resetReason"] = (int)lastResetReason_;
    doc["bootStage"] = bootStage_;
    doc["bootStartedAtMs"] = bootStartedAtMs_;
    doc["rebootCounter"] = rebootCounter_;
    doc["freeHeap"] = ESP.getFreeHeap();
    doc["minFreeHeap"] = bootMinFreeHeap_;
    if (bindingPropertyId_[0]) doc["propertyId"] = bindingPropertyId_;
    if (bindingPropertyScopeId_[0]) doc["propertyScopeId"] = bindingPropertyScopeId_;
    if (bindingMatrixGatewayId_[0]) doc["matrixGatewayId"] = bindingMatrixGatewayId_;
    doc["gps_valid"] = hasLastGpsForStatus_;
    if (hasLastGpsForStatus_) {
      doc["lat"] = lastGpsForStatus_.lat;
      doc["lon"] = lastGpsForStatus_.lon;
      JsonObject gps = doc.createNestedObject("gps");
      gps["valid"] = true;
      gps["lat"] = lastGpsForStatus_.lat;
      gps["lon"] = lastGpsForStatus_.lon;
      gps["sats"] = lastGpsForStatus_.sats;
      gps["hdop"] = lastGpsForStatus_.hdop;
      gps["speed_kmph"] = lastGpsForStatus_.speedKmph;
      gps["gps_time"] = lastGpsForStatus_.gpsTime;
      gps["filtered"] = lastGpsForStatus_.filtered;
      gps["locked"] = lastGpsForStatus_.locked;
      gps["outlier_dropped"] = lastGpsForStatus_.outlierDropped;
    }
    String out;
    serializeJson(doc, out);
    statusServer.send(200, "application/json", out);
  });
  statusServer.on("/binding", HTTP_POST, []() {
    StaticJsonDocument<384> response;
    if (!wifiOtaEnabled || WiFi.getMode() == WIFI_OFF) {
      response["ok"] = false;
      response["reason"] = "wifi_ota_disabled";
      String out;
      serializeJson(response, out);
      statusServer.send(503, "application/json", out);
      return;
    }
    if (!statusServer.hasArg("plain")) {
      response["ok"] = false;
      response["reason"] = "missing_body";
      String out;
      serializeJson(response, out);
      statusServer.send(400, "application/json", out);
      return;
    }

    StaticJsonDocument<384> payload;
    DeserializationError err = deserializeJson(payload, statusServer.arg("plain"));
    if (err != DeserializationError::Ok) {
      response["ok"] = false;
      response["reason"] = "invalid_json";
      String out;
      serializeJson(response, out);
      statusServer.send(400, "application/json", out);
      return;
    }

    const char* failReason = nullptr;
    const bool ok = persistBindingConfig(payload.as<JsonVariantConst>(), &failReason);
    response["ok"] = ok;
    response["supportsScopedLora"] = supportsScopedLora_;
    response["bindingReady"] = bindingReady_;
    response["bindingVersion"] = bindingVersion_;
    if (bindingPropertyId_[0]) response["propertyId"] = bindingPropertyId_;
    if (bindingPropertyScopeId_[0]) response["propertyScopeId"] = bindingPropertyScopeId_;
    if (bindingMatrixGatewayId_[0]) response["matrixGatewayId"] = bindingMatrixGatewayId_;
    if (!ok && failReason) response["reason"] = failReason;
    String out;
    serializeJson(response, out);
    statusServer.send(ok ? 200 : 400, "application/json", out);
  });
  statusServerRoutesConfigured_ = true;
}

static void ensureStatusServerRunning() {
  if (!statusServerRoutesConfigured_) configureStatusServerRoutes();
  if (statusServerRunning_) return;
  if (WiFi.getMode() == WIFI_OFF) return;
  statusServer.begin();
  statusServerRunning_ = true;
  LOGI("Status HTTP iniciado na porta 80");
}

static void stopStatusServer() {
  if (!statusServerRunning_) return;
  statusServer.close();
  statusServerRunning_ = false;
  LOGI("Status HTTP parado");
}

static bool otaDisableGuardActive() {
  if (!wifiOtaEnabled) return false;
  const uint32_t now = millis();
  if (wifiOtaEnabledAtMs != 0 && (uint32_t)(now - wifiOtaEnabledAtMs) < cfg::OTA_DISABLE_GUARD_MS) {
    return true;
  }
  if (otaApLastClientSeenMs != 0 && (uint32_t)(now - otaApLastClientSeenMs) < cfg::OTA_DISABLE_GUARD_MS) {
    return true;
  }
  return false;
}

static bool beginPrefs() {
  if (prefsReady_) return true;
  prefsReady_ = prefs_.begin(cfg::PREF_NAMESPACE, false);
  if (!prefsReady_) LOGE("Falha ao abrir NVS namespace=%s", cfg::PREF_NAMESPACE);
  return prefsReady_;
}

static bool isValidGeoPoint(const GeoPoint& p) {
  return isfinite(p.lat) && isfinite(p.lon) &&
         p.lat >= -90.0 && p.lat <= 90.0 &&
         p.lon >= -180.0 && p.lon <= 180.0;
}

static bool isValidPolygon(const Polygon& p) {
  if (p.count < 3 || p.count > cfg::MAX_POLYGON_POINTS) return false;
  for (uint8_t i = 0; i < p.count; ++i) {
    if (!isValidGeoPoint(p.points[i])) return false;
  }
  return true;
}

static bool sanitizeHerdingPlan(HerdingPlan* plan) {
  if (!plan) return false;
  if (plan->phaseCount == 0 || plan->phaseCount > cfg::MAX_HERD_PHASES) {
    plan->active = false;
    plan->phaseCount = 0;
    plan->currentPhase = 0;
    plan->operationId[0] = '\0';
    return false;
  }
  for (uint8_t i = 0; i < plan->phaseCount; ++i) {
    if (!isValidPolygon(plan->phases[i])) {
      plan->active = false;
      plan->phaseCount = 0;
      plan->currentPhase = 0;
      plan->operationId[0] = '\0';
      return false;
    }
  }
  if (plan->currentPhase >= plan->phaseCount) plan->currentPhase = 0;
  return true;
}

static void persistWifiOtaEnabled(bool enabled) {
  if (!beginPrefs()) return;
  prefs_.putBool(cfg::PREF_KEY_WIFI_OTA, enabled);
}

static bool persistFence(const Polygon& fence) {
  if (!beginPrefs()) return false;
  return prefs_.putBytes(cfg::PREF_KEY_FENCE, &fence, sizeof(fence)) ==
      sizeof(fence);
}

static bool persistHerdingPlan(const HerdingPlan& plan) {
  if (!beginPrefs()) return false;
  return prefs_.putBytes(cfg::PREF_KEY_HERD, &plan, sizeof(plan)) ==
      sizeof(plan);
}

static void persistHealthReportDayKey(uint32_t dayKey) {
  if (!beginPrefs() || dayKey == 0) return;
  prefs_.putULong(cfg::PREF_KEY_HEALTH_DAY, dayKey);
}

static bool loadPersistedFence(Polygon* outFence) {
  if (!beginPrefs() || !outFence) return false;
  if (prefs_.getBytesLength(cfg::PREF_KEY_FENCE) != sizeof(Polygon)) return false;
  if (prefs_.getBytes(cfg::PREF_KEY_FENCE, outFence, sizeof(Polygon)) != sizeof(Polygon)) return false;
  if (!isValidPolygon(*outFence)) return false;
  return true;
}

static bool loadPersistedHerdingPlan(HerdingPlan* outPlan) {
  if (!beginPrefs() || !outPlan) return false;
  if (prefs_.getBytesLength(cfg::PREF_KEY_HERD) != sizeof(HerdingPlan)) return false;
  if (prefs_.getBytes(cfg::PREF_KEY_HERD, outPlan, sizeof(HerdingPlan)) != sizeof(HerdingPlan)) return false;
  return sanitizeHerdingPlan(outPlan);
}

static bool loadPersistedWifiOtaEnabled() {
  if (!beginPrefs()) return cfg::WIFI_OTA_DEFAULT_ENABLED;
  return prefs_.getBool(cfg::PREF_KEY_WIFI_OTA, cfg::WIFI_OTA_DEFAULT_ENABLED);
}

static uint32_t loadPersistedHealthReportDayKey() {
  if (!beginPrefs()) return 0;
  return prefs_.getULong(cfg::PREF_KEY_HEALTH_DAY, 0);
}

static void loadPersistedConfig() {
  wifiOtaEnabled = loadPersistedWifiOtaEnabled();
  if (wifiOtaEnabled) wifiOtaEnabledAtMs = millis();
  restoreLoRaSeq();
  loadBindingConfig();
  lastHealthReportDayKey_ = loadPersistedHealthReportDayKey();

  Polygon savedFence;
  if (loadPersistedFence(&savedFence)) {
    geofence.setFence(savedFence);
    LOGI("Fence restaurada da NVS (%u pontos)", savedFence.count);
  }

  HerdingPlan savedPlan;
  if (loadPersistedHerdingPlan(&savedPlan)) {
    herding.setPlan(savedPlan);
    if (savedPlan.active) stateMachine.setMode(CollarMode::CONDUCAO);
    LOGI("Plano de conducao restaurado: active=%d fase=%u/%u",
         savedPlan.active ? 1 : 0, savedPlan.currentPhase, savedPlan.phaseCount);
  }
}

static bool parsePointListJson(
    const JsonArray& points,
    GeoPoint* outPoints,
    uint8_t* outCount,
    uint8_t minCount,
    uint8_t maxCount,
    const char** err) {
  if (!outPoints || !outCount) {
    if (err) *err = "out_points_null";
    return false;
  }
  if (points.isNull()) {
    if (err) *err = "missing_points";
    return false;
  }
  const size_t count = points.size();
  if (count < minCount || count > maxCount) {
    if (err) *err = "invalid_points_count";
    return false;
  }

  for (uint8_t i = 0; i < (uint8_t)count; ++i) {
    JsonArray pair = points[i].as<JsonArray>();
    if (pair.isNull() || pair.size() < 2 || pair[0].isNull() || pair[1].isNull()) {
      if (err) *err = "invalid_point_format";
      return false;
    }
    outPoints[i].lat = pair[0].as<double>();
    outPoints[i].lon = pair[1].as<double>();
    if (!isValidGeoPoint(outPoints[i])) {
      if (err) *err = "invalid_point_value";
      return false;
    }
  }
  *outCount = (uint8_t)count;
  return true;
}

static bool parsePolygonJson(const JsonArray& points, Polygon* outPolygon, const char** err) {
  if (!outPolygon) {
    if (err) *err = "out_polygon_null";
    return false;
  }
  Polygon tmp;
  if (!parsePointListJson(points, tmp.points, &tmp.count, 3, cfg::MAX_POLYGON_POINTS, err)) return false;
  *outPolygon = tmp;
  return true;
}

static bool parseHerdingPlanJson(const JsonArray& phases, HerdingPlan* outPlan, const char** err) {
  if (!outPlan) {
    if (err) *err = "out_plan_null";
    return false;
  }
  if (phases.isNull()) {
    if (err) *err = "missing_phases";
    return false;
  }
  const size_t phaseCount = phases.size();
  if (phaseCount == 0 || phaseCount > cfg::MAX_HERD_PHASES) {
    if (err) *err = "invalid_phase_count";
    return false;
  }

  HerdingPlan tmp;
  tmp.active = true;
  tmp.phaseCount = (uint8_t)phaseCount;
  tmp.currentPhase = 0;
  tmp.operationId[0] = '\0';
  for (uint8_t i = 0; i < tmp.phaseCount; ++i) {
    JsonArray points = phases[i].as<JsonArray>();
    if (!parsePolygonJson(points, &tmp.phases[i], err)) return false;
  }

  *outPlan = tmp;
  return true;
}

static void resetFenceChunkRx() {
  fenceChunkRx_ = FenceChunkRxState{};
}

static void resetHerdChunkRx() {
  herdChunkRx_ = HerdChunkRxState{};
}

static bool applyFenceChunkJson(const JsonObject& doc, const char** err) {
  const int part = doc["part"] | -1;
  const int total = doc["total"] | -1;
  const JsonArray points = doc["points"].as<JsonArray>();
  if (part < 0 || total <= 0 || part >= total || total > cfg::MAX_POLYGON_POINTS) {
    if (err) *err = "invalid_chunk_header";
    return false;
  }

  GeoPoint parsed[cfg::MAX_POLYGON_POINTS]{};
  uint8_t parsedCount = 0;
  if (!parsePointListJson(points, parsed, &parsedCount, 1, cfg::MAX_POLYGON_POINTS, err)) return false;

  if (part == 0) {
    resetFenceChunkRx();
    fenceChunkRx_.active = true;
    fenceChunkRx_.totalParts = (uint8_t)total;
    fenceChunkRx_.expectedPart = 0;
    fillPolygonAuditContext(
        &fenceChunkRx_.audit,
        MsgType::SET_FENCE,
        parseScopeIdHex(pickFirstText(doc["scope_id"], doc["property_scope_id"])),
        doc);
  }

  if (!fenceChunkRx_.active) {
    if (err) *err = "missing_chunk_start";
    return false;
  }
  if (fenceChunkRx_.totalParts != (uint8_t)total) {
    if (err) *err = "chunk_total_mismatch";
    return false;
  }
  if (fenceChunkRx_.expectedPart != (uint8_t)part) {
    if (err) *err = "chunk_out_of_order";
    return false;
  }
  if ((uint16_t)fenceChunkRx_.fence.count + parsedCount > cfg::MAX_POLYGON_POINTS) {
    if (err) *err = "too_many_points";
    return false;
  }

  for (uint8_t i = 0; i < parsedCount; ++i) {
    fenceChunkRx_.fence.points[fenceChunkRx_.fence.count++] = parsed[i];
  }
  fenceChunkRx_.expectedPart++;

  if ((uint8_t)part == (uint8_t)(total - 1)) {
    if (!isValidPolygon(fenceChunkRx_.fence)) {
      resetFenceChunkRx();
      if (err) *err = "invalid_fence_final";
      return false;
    }
    geofence.setFence(fenceChunkRx_.fence);
    if (!persistFence(fenceChunkRx_.fence)) {
      resetFenceChunkRx();
      if (err) *err = "persist_fence_failed";
      return false;
    }
    logPolygonApplyResult(
        MsgType::SET_FENCE,
        fenceChunkRx_.audit.scopeId,
        fenceChunkRx_.audit.polygonKind,
        fenceChunkRx_.audit.originDocType,
        fenceChunkRx_.audit.originDocId,
        fenceChunkRx_.audit.commandId,
        true,
        nullptr,
        PolygonErrorStage::NONE,
        fenceChunkRx_.fence.count,
        0);
    resetFenceChunkRx();
  }
  return true;
}

static bool applyHerdChunkJson(const JsonObject& doc, const char** err) {
  const int phaseIdx = doc["phase_index"] | -1;
  const int phaseTotal = doc["phase_total"] | -1;
  const int part = doc["part"] | -1;
  const int total = doc["total"] | -1;
  const char* operationId = doc["operation_id"] | "";
  const JsonArray points = doc["points"].as<JsonArray>();

  if (phaseIdx < 0 || phaseTotal <= 0 || phaseIdx >= phaseTotal || phaseTotal > cfg::MAX_HERD_PHASES) {
    if (err) *err = "invalid_phase_header";
    return false;
  }
  if (part < 0 || total <= 0 || part >= total || total > cfg::MAX_POLYGON_POINTS) {
    if (err) *err = "invalid_chunk_header";
    return false;
  }

  GeoPoint parsed[cfg::MAX_POLYGON_POINTS]{};
  uint8_t parsedCount = 0;
  if (!parsePointListJson(points, parsed, &parsedCount, 1, cfg::MAX_POLYGON_POINTS, err)) return false;

  if (phaseIdx == 0 && part == 0) {
    resetHerdChunkRx();
    herdChunkRx_.active = true;
    herdChunkRx_.phaseTotal = (uint8_t)phaseTotal;
    herdChunkRx_.currentPhase = 0;
    herdChunkRx_.expectedPart = 0;
    herdChunkRx_.totalPartsCurrentPhase = (uint8_t)total;
    herdChunkRx_.plan.active = true;
    herdChunkRx_.plan.phaseCount = (uint8_t)phaseTotal;
    herdChunkRx_.plan.currentPhase = 0;
    copyStringToBuffer(
        herdChunkRx_.plan.operationId,
        sizeof(herdChunkRx_.plan.operationId),
        operationId);
    fillPolygonAuditContext(
        &herdChunkRx_.audit,
        MsgType::SET_HERDING_PLAN,
        parseScopeIdHex(pickFirstText(doc["scope_id"], doc["property_scope_id"])),
        doc);
    herdChunkRx_.phaseAccum.count = 0;
  }

  if (!herdChunkRx_.active) {
    if (err) *err = "missing_phase_start";
    return false;
  }
  if (herdChunkRx_.phaseTotal != (uint8_t)phaseTotal) {
    if (err) *err = "phase_total_mismatch";
    return false;
  }
  if (herdChunkRx_.currentPhase != (uint8_t)phaseIdx) {
    if (err) *err = "phase_out_of_order";
    return false;
  }

  if (part == 0) {
    herdChunkRx_.phaseAccum.count = 0;
    herdChunkRx_.expectedPart = 0;
    herdChunkRx_.totalPartsCurrentPhase = (uint8_t)total;
    if (operationId[0] != '\0' &&
        strcmp(herdChunkRx_.plan.operationId, operationId) != 0) {
      if (err) *err = "operation_id_mismatch";
      return false;
    }
  } else if (herdChunkRx_.totalPartsCurrentPhase != (uint8_t)total) {
    if (err) *err = "chunk_total_mismatch";
    return false;
  }

  if (herdChunkRx_.expectedPart != (uint8_t)part) {
    if (err) *err = "chunk_out_of_order";
    return false;
  }
  if ((uint16_t)herdChunkRx_.phaseAccum.count + parsedCount > cfg::MAX_POLYGON_POINTS) {
    if (err) *err = "too_many_points";
    return false;
  }

  for (uint8_t i = 0; i < parsedCount; ++i) {
    herdChunkRx_.phaseAccum.points[herdChunkRx_.phaseAccum.count++] = parsed[i];
  }
  herdChunkRx_.expectedPart++;

  if ((uint8_t)part == (uint8_t)(total - 1)) {
    if (!isValidPolygon(herdChunkRx_.phaseAccum)) {
      resetHerdChunkRx();
      if (err) *err = "invalid_phase_polygon";
      return false;
    }
    herdChunkRx_.plan.phases[phaseIdx] = herdChunkRx_.phaseAccum;

    if ((uint8_t)phaseIdx + 1 == (uint8_t)phaseTotal) {
      herding.setPlan(herdChunkRx_.plan);
      if (!persistHerdingPlan(herdChunkRx_.plan)) {
        resetHerdChunkRx();
        if (err) *err = "persist_herd_plan_failed";
        return false;
      }
      stateMachine.setMode(CollarMode::CONDUCAO);
      logEvent(EventType::HERD_START, herdChunkRx_.plan.phaseCount, 0);
      logPolygonApplyResult(
          MsgType::SET_HERDING_PLAN,
          herdChunkRx_.audit.scopeId,
          herdChunkRx_.audit.polygonKind,
          herdChunkRx_.audit.originDocType,
          herdChunkRx_.audit.originDocId[0] != '\0'
              ? herdChunkRx_.audit.originDocId
              : herdChunkRx_.plan.operationId,
          herdChunkRx_.audit.commandId,
          true,
          nullptr,
          PolygonErrorStage::NONE,
          herdChunkRx_.plan.phaseCount > 0
              ? herdChunkRx_.plan.phases[herdChunkRx_.plan.phaseCount - 1].count
              : 0,
          herdChunkRx_.plan.phaseCount);
      resetHerdChunkRx();
    } else {
      herdChunkRx_.currentPhase++;
      herdChunkRx_.expectedPart = 0;
      herdChunkRx_.totalPartsCurrentPhase = 0;
      herdChunkRx_.phaseAccum.count = 0;
    }
  }
  return true;
}

static void setWatchdogEnabled(bool enabled) {
  if (!cfg::TASK_WDT_ENABLED) {
    (void)enabled;
    watchdogTaskRegistered = false;
    return;
  }

  TaskHandle_t target = watchdogTargetTask();
  if (enabled && !watchdogTaskRegistered) {
    const esp_err_t err = esp_task_wdt_add(target);
    if (err == ESP_OK) {
      watchdogTaskRegistered = true;
    } else if (err != ESP_ERR_INVALID_STATE) {
      LOGW("TWDT add falhou err=%d", (int)err);
    }
  } else if (!enabled && watchdogTaskRegistered) {
    const esp_err_t err = esp_task_wdt_delete(target);
    if (err == ESP_OK || err == ESP_ERR_NOT_FOUND) {
      watchdogTaskRegistered = false;
    } else {
      LOGW("TWDT delete falhou err=%d", (int)err);
    }
  }
}

static TaskHandle_t watchdogTargetTask() {
  return watchdogOwnerTask != nullptr ? watchdogOwnerTask : xTaskGetCurrentTaskHandle();
}

static void feedWatchdogIfEnabled() {
  if (!cfg::TASK_WDT_ENABLED || !watchdogTaskRegistered) return;
  const esp_err_t err = esp_task_wdt_reset();
  if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
    LOGW("TWDT reset falhou err=%d", (int)err);
  }
}

static void stopWifiOtaMaintenance() {
  otaRecoveryAttemptCount = 0;
  otaRecoveryAttemptAtMs = 0;
  stopStatusServer();
  MDNS.end();
  if (WiFi.getMode() == WIFI_STA || WiFi.getMode() == WIFI_AP_STA) {
    WiFi.disconnect(true, true);
  }
  if (WiFi.getMode() == WIFI_AP || WiFi.getMode() == WIFI_AP_STA) {
    WiFi.softAPdisconnect(true);
  }
  delay(50);
  WiFi.mode(WIFI_OFF);
  otaModeActive = false;
  LOGI("OTA/WiFi desativado: modo LoRa-only");
}

static void onWifiEvent(WiFiEvent_t event) {
#if defined(ARDUINO_EVENT_WIFI_AP_START)
  if (event == ARDUINO_EVENT_WIFI_AP_START) {
    LOGI("WiFi AP iniciado");
  }
#endif
#if defined(ARDUINO_EVENT_WIFI_AP_STOP)
  if (event == ARDUINO_EVENT_WIFI_AP_STOP) {
    otaModeActive = false;
    otaRecoveryAttemptAtMs = 0;
    LOGW("WiFi AP parou");
  }
#endif
#if defined(ARDUINO_EVENT_WIFI_AP_STACONNECTED)
  if (event == ARDUINO_EVENT_WIFI_AP_STACONNECTED) {
    otaApLastClientSeenMs = millis();
    LOGI("Cliente conectado no AP (n=%d)", WiFi.softAPgetStationNum());
  }
#endif
#if defined(ARDUINO_EVENT_WIFI_AP_STADISCONNECTED)
  if (event == ARDUINO_EVENT_WIFI_AP_STADISCONNECTED) {
    LOGI("Cliente desconectado do AP (n=%d)", WiFi.softAPgetStationNum());
  }
#endif
}

static void startOtaService() {
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

  if (MDNS.begin(cfg::OTA_HOSTNAME)) {
    LOGI("mDNS ativo: %s.local:3232", cfg::OTA_HOSTNAME);
  } else {
    LOGW("mDNS indisponivel; OTA pode nao aparecer automaticamente no IDE.");
  }

  otaModeActive = true;
}

static bool otaApClientConnected() {
  if (!wifiOtaEnabled || !otaModeActive) return false;
  const wifi_mode_t mode = WiFi.getMode();
  if (mode != WIFI_AP && mode != WIFI_AP_STA) return false;
  return WiFi.softAPgetStationNum() > 0;
}

static bool shouldBlePresenceBeEnabled() {
  if (!wifiOtaEnabled) return false;
  if (otaUploadInProgress) return false;
  return true;
}

static bool gpsFixUsableForOnboarding(const GpsData& gps) {
  return gps.valid && isfinite(gps.lat) && isfinite(gps.lon) &&
         gps.lat >= -90.0 && gps.lat <= 90.0 &&
         gps.lon >= -180.0 && gps.lon <= 180.0;
}

static void updateBlePositionForOnboarding(
    const GpsData* preferred,
    const GpsData* fallback) {
  if (!cfg::BLE_PRESENCE_ENABLED) return;
  if (preferred != nullptr && gpsFixUsableForOnboarding(*preferred)) {
    blePresence.setPosition(preferred->lat, preferred->lon, true);
    return;
  }
  if (fallback != nullptr && gpsFixUsableForOnboarding(*fallback)) {
    blePresence.setPosition(fallback->lat, fallback->lon, true);
    return;
  }
  blePresence.setPosition(0.0, 0.0, false);
}

static void refreshBlePositionForOnboarding() {
  // Prioriza última posição oficial já validada (inclusive restaurada da EEPROM).
  if (smartGps.hasLastGoodFix()) {
    const GpsData& lastGood = smartGps.lastGoodFix();
    updateBlePositionForOnboarding(&lastGood);
    return;
  }

  // Sem last-good ainda: onboarding BLE aceita fix bruto valido para reduzir
  // bloqueio no cadastro inicial; a telemetria oficial continua com gate estrito.
  const GpsData live = sensors.readGpsSnapshot();
  updateBlePositionForOnboarding(&live);
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

static void printBootChecklist(bool bleInitOk, bool storageOk, bool loraOk) {
  Serial.println("==== HW CHECKLIST | COLEIRA ====");
  checklistLine(
      "NVS_CONFIG",
      prefsReady_,
      "Falha no namespace NVS collar_cfg; revisar flash/NVS.");
  checklistLine(
      "SEQ_UPLINK_NVS",
      seqPersistReady_,
      "Seq uplink sem persistencia; revisar NVS.");
  checklistLine(
      "WIFI_OTA_SERVICE",
      !wifiOtaEnabled || otaModeActive,
      "wifi_ota_enabled=true sem OTA ativo; revisar AP/SSID/senha.");
  Serial.printf(
      "[MODE ] %-24s : %s\n",
      "WIFI_OTA_ENABLED",
      wifiOtaEnabled ? "true" : "false");
  checklistLine(
      "STATUS_HTTP_80",
      true,
      nullptr,
      "/status habilitado");

  if (cfg::BLE_PRESENCE_ENABLED) {
    checklistLine(
        "BLE_PRESENCE",
        bleInitOk,
        "Falha ao iniciar BLE; revisar memoria BT e stack.");
  } else {
    checklistLine("BLE_PRESENCE", true, nullptr, "desabilitado em config");
  }

  checklistLine(
      "GPS_UART",
      sensors.gpsUartReady(),
      "UART GPS nao inicializou; revisar pinos RX/TX e baud.");
  char gpsBootDetail[160] = {};
  snprintf(
      gpsBootDetail,
      sizeof(gpsBootDetail),
      "baud=%lu bytes=%lu nmea=$%lu sample=%s",
      (unsigned long)sensors.gpsBaudUsed(),
      (unsigned long)sensors.gpsBootBytes(),
      (unsigned long)sensors.gpsBootDollarCount(),
      sensors.gpsBootSample().c_str());
  checklistLine(
      "GPS_BOOT_RX",
      sensors.gpsBootBytes() > 0,
      "Nenhum byte recebido no boot; verificar TX do GPS->D16, alimentacao e GND.",
      gpsBootDetail);
  const bool gpsHasRxBytes = sensors.gpsBootBytes() > 0;
  const char* gpsNmeaOffHint = gpsHasRxBytes
      ? "Recebe bytes sem '$'; verificar baud do GPS (9600/38400/57600/115200), TX->D16 e ruido na UART."
      : "Sem sentencas NMEA no boot; verificar TX do GPS->D16, alimentacao e visada do ceu.";
  char gpsNmeaDetail[128] = {};
  const char* gpsNmeaOkDetail = nullptr;
  if (sensors.gpsBootFixValid()) {
    const GpsData& bootFix = sensors.gpsBootFix();
    snprintf(
        gpsNmeaDetail,
        sizeof(gpsNmeaDetail),
        "lat=%.6f lon=%.6f sats=%u hdop=%.2f",
        bootFix.lat,
        bootFix.lon,
        bootFix.sats,
        bootFix.hdop);
    gpsNmeaOkDetail = gpsNmeaDetail;
  }
  checklistLine(
      "GPS_NMEA",
      sensors.gpsNmeaSeen(),
      gpsNmeaOffHint,
      gpsNmeaOkDetail);

  const bool i2cBusAlive = sensors.i2cDevicesFound() > 0;
  char i2cDetail[128] = {};
  snprintf(
      i2cDetail,
      sizeof(i2cDetail),
      "found=%u [%s]",
      sensors.i2cDevicesFound(),
      sensors.i2cScanSummary().c_str());
  checklistLine(
      "I2C_BUS_SCAN",
      i2cBusAlive,
      "Nenhum dispositivo I2C detectado; revisar SDA/SCL, 3v3 e GND.",
      i2cDetail);

  const bool mpuDetected = sensors.mpuDetected();
  char mpuOkDetail[24] = {};
  if (mpuDetected) {
    snprintf(mpuOkDetail, sizeof(mpuOkDetail), "addr=0x%02X", sensors.mpuAddress());
  }
  checklistLine(
      "MPU6050_I2C",
      mpuDetected,
      "MPU6050 nao responde no I2C; revisar SDA/SCL, 3v3 e GND.",
      mpuDetected ? mpuOkDetail : nullptr);
  checklistLine(
      "MPU6050_DRIVER",
      sensors.mpuReady(),
      "Driver MPU nao inicializou; revisar modulo/offset.");

  checklistLine(
      "MLX90614_I2C",
      sensors.mlxDetected(),
      "MLX90614 nao responde no I2C 0x5A; revisar SDA/SCL, 3v3 e GND.");
  checklistLine(
      "MLX90614_DRIVER",
      sensors.mlxReady(),
      "Driver MLX90614 nao inicializou; revisar modulo/endereco.");

  checklistLine(
      "EEPROM_QUEUE",
      storageOk,
      "EEPROM emulada indisponivel; revisar particao/flash.");
  checklistLine(
      "LORA_RFM95",
      loraOk,
      "Falha LoRa begin; revisar CS/RST/DIO0/DIO1, antena e modulo.");
  Serial.println("================================");
}

static void setupWifiOtaMaintenance() {
  if (!wifiOtaEnabled || !cfg::OTA_ENABLED || otaModeActive) return;
  wifiOtaEnabledAtMs = millis();
  const String apSsid = collarApSsid();

  if (cfg::OTA_FORCE_AP_ONLY) {
    WiFi.mode(WIFI_AP);
    WiFi.setSleep(false);
    const bool apOk = WiFi.softAP(
        apSsid.c_str(),
        cfg::OTA_AP_PASS,
        cfg::OTA_AP_CHANNEL,
        false,
        cfg::OTA_AP_MAX_CLIENTS);
    if (!apOk) {
      WiFi.mode(WIFI_OFF);
      LOGE("OTA: falha ao subir AP forcado.");
      return;
    }
    startOtaService();
    ensureStatusServerRunning();
    otaRecoveryAttemptCount = 0;
    LOGI("OTA pronto (AP FORCADO) SSID=%s IP=%s host=%s", apSsid.c_str(), WiFi.softAPIP().toString().c_str(), cfg::OTA_HOSTNAME);
    return;
  }

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.begin(cfg::WIFI_SSID, cfg::WIFI_PASS);
  LOGI("OTA: conectando Wi-Fi SSID=%s", cfg::WIFI_SSID);

  const uint32_t start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < cfg::OTA_CONNECT_TIMEOUT_MS) {
    delay(250);
  }

  if (WiFi.status() == WL_CONNECTED) {
    startOtaService();
    ensureStatusServerRunning();
    LOGI("OTA pronto (STA) IP=%s host=%s", WiFi.localIP().toString().c_str(), cfg::OTA_HOSTNAME);
    return;
  }

  LOGW("OTA: falha ao conectar no SSID=%s", cfg::WIFI_SSID);
  WiFi.disconnect(true, true);

  if (!cfg::OTA_AP_FALLBACK_ENABLED) {
    WiFi.mode(WIFI_OFF);
    LOGW("OTA: AP fallback desabilitado, seguindo modo normal.");
    return;
  }

  WiFi.mode(WIFI_AP);
  WiFi.setSleep(false);
  const bool apOk = WiFi.softAP(
      apSsid.c_str(),
      cfg::OTA_AP_PASS,
      cfg::OTA_AP_CHANNEL,
      false,
      cfg::OTA_AP_MAX_CLIENTS);
  if (!apOk) {
    WiFi.mode(WIFI_OFF);
    LOGE("OTA: falha ao subir AP fallback.");
    return;
  }

  startOtaService();
  ensureStatusServerRunning();
  otaRecoveryAttemptCount = 0;
  LOGI("OTA pronto (AP) SSID=%s IP=%s host=%s", apSsid.c_str(), WiFi.softAPIP().toString().c_str(), cfg::OTA_HOSTNAME);
}

static uint32_t otaRecoveryBackoffMs() {
  uint8_t step = otaRecoveryAttemptCount;
  if (step > 5) step = 5;
  return 1000UL << step;
}

static void ensureWifiOtaMaintenance() {
  if (!wifiOtaEnabled || otaModeActive) return;
  const uint32_t now = millis();
  const uint32_t backoffMs = otaRecoveryBackoffMs();
  if (otaRecoveryAttemptAtMs != 0 &&
      (uint32_t)(now - otaRecoveryAttemptAtMs) < backoffMs) {
    return;
  }
  otaRecoveryAttemptAtMs = now;
  LOGW("OTA/WiFi inativo, retomando servico (tentativa=%u)", (unsigned)(otaRecoveryAttemptCount + 1U));
  setupWifiOtaMaintenance();
  if (!otaModeActive && otaRecoveryAttemptCount < 10) otaRecoveryAttemptCount++;
}

static void applyWifiOtaMode(bool enabled, const char* source) {
  if (wifiOtaEnabled == enabled) {
    LOGI("SET_PARAMS: wifi_ota_enabled ja estava em %d (%s)", enabled ? 1 : 0, source);
    persistWifiOtaEnabled(enabled);
    return;
  }

  if (!enabled && otaApClientConnected()) {
    LOGW("SET_PARAMS: wifi_ota_enabled=0 ignorado (%s), cliente OTA conectado", source);
    persistWifiOtaEnabled(true);
    return;
  }
  if (!enabled && otaDisableGuardActive()) {
    LOGW("SET_PARAMS: wifi_ota_enabled=0 ignorado (%s), guard OTA ativo", source);
    persistWifiOtaEnabled(true);
    return;
  }

  wifiOtaEnabled = enabled;
  persistWifiOtaEnabled(enabled);
  setWatchdogEnabled(enabled);
  if (enabled) wifiOtaEnabledAtMs = millis();

  if (enabled) {
    setupWifiOtaMaintenance();
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
    stopWifiOtaMaintenance();
    LOGI("SET_PARAMS: wifi_ota_enabled=0 aplicado via %s", source);
  }
}

static bool hasAdminModePermission(const JsonVariantConst payload) {
  if (!payload.is<JsonObjectConst>()) return false;
  const char* requestedByRole = payload["requested_by_role"] | "";
  if (strcmp(requestedByRole, "adm") == 0 || strcmp(requestedByRole, "admin") == 0) {
    return true;
  }
  const char* actorRole = payload["actor_role"] | "";
  if (strcmp(actorRole, "adm") == 0 || strcmp(actorRole, "admin") == 0) {
    return true;
  }
  const JsonVariantConst requestedByAdmin = payload["requested_by_admin"];
  return requestedByAdmin.is<bool>() && requestedByAdmin.as<bool>();
}

static void logEvent(EventType type, int32_t d1 = 0, int32_t d2 = 0) {
  EventRecord ev;
  ev.ts = millis() / 1000;
  ev.type = type;
  ev.d1 = d1;
  ev.d2 = d2;
  ev.scopeId = bindingScopeIdValue();
  if (type == EventType::HERD_START ||
      type == EventType::HERD_PHASE_CHANGE ||
      type == EventType::HERD_DONE) {
    copyStringToBuffer(
        ev.payload.operationId,
        sizeof(ev.payload.operationId),
        activeHerdOperationId());
  }
  storage.pushEvent(ev);
}

static void promoteCompletedHerdingFence() {
  const HerdingPlan& plan = herding.plan();
  if (plan.phaseCount == 0) return;
  const Polygon& target = plan.phases[plan.phaseCount - 1];
  if (!isValidPolygon(target)) return;
  geofence.setFence(target);
  persistFence(target);
  LOGI(
      "Area final do arrebanhamento promovida para cerca ativa (%u pontos)",
      target.count);
}

namespace {
constexpr uint16_t kHealthFlagWifiOtaEnabled = 1U << 0;
constexpr uint16_t kHealthFlagOtaModeActive = 1U << 1;
constexpr uint16_t kHealthFlagGpsUartReady = 1U << 2;
constexpr uint16_t kHealthFlagGpsNmeaSeen = 1U << 3;
constexpr uint16_t kHealthFlagGpsFixValid = 1U << 4;
constexpr uint16_t kHealthFlagMpuReady = 1U << 5;
constexpr uint16_t kHealthFlagMlxReady = 1U << 6;
constexpr uint16_t kHealthFlagStorageReady = 1U << 7;
constexpr uint16_t kHealthFlagLoRaReady = 1U << 8;
constexpr uint16_t kHealthFlagLastLoRaTxOk = 1U << 9;
constexpr uint16_t kHealthFlagFallbackSchedule = 1U << 10;
}

static uint32_t gpsDayKey(const GpsData& gps) {
  if (!gps.valid) return 0;
  if (gps.year < 2023 || gps.month == 0 || gps.month > 12 || gps.day == 0 ||
      gps.day > 31) {
    return 0;
  }
  return (uint32_t)gps.year * 10000UL + (uint32_t)gps.month * 100UL +
         (uint32_t)gps.day;
}

static uint16_t buildHealthFlags(const Telemetry& t, bool fallbackScheduleUsed) {
  uint16_t flags = 0;
  if (wifiOtaEnabled) flags |= kHealthFlagWifiOtaEnabled;
  if (otaModeActive) flags |= kHealthFlagOtaModeActive;
  if (sensors.gpsUartReady()) flags |= kHealthFlagGpsUartReady;
  if (sensors.gpsNmeaSeen()) flags |= kHealthFlagGpsNmeaSeen;
  if (t.gps.valid) flags |= kHealthFlagGpsFixValid;
  if (sensors.mpuReady()) flags |= kHealthFlagMpuReady;
  if (sensors.mlxReady()) flags |= kHealthFlagMlxReady;
  if (storageReady_) flags |= kHealthFlagStorageReady;
  if (loraReady_) flags |= kHealthFlagLoRaReady;
  if (lastLoRaTxOk_) flags |= kHealthFlagLastLoRaTxOk;
  if (fallbackScheduleUsed) flags |= kHealthFlagFallbackSchedule;
  return flags;
}

static bool sendDailyHealthReport(const Telemetry& t, uint32_t intervalMs) {
  if (!bindingReady_) return false;
  const uint32_t dayKey = gpsDayKey(t.gps);
  bool fallbackScheduleUsed = false;

  if (dayKey != 0) {
    if (dayKey == lastHealthReportDayKey_) {
      healthFallbackAccumMs_ = 0;
      return false;
    }
  } else {
    fallbackScheduleUsed = true;
    if (UINT64_MAX - healthFallbackAccumMs_ > intervalMs) {
      healthFallbackAccumMs_ += intervalMs;
    } else {
      healthFallbackAccumMs_ = UINT64_MAX;
    }
    if (healthFallbackAccumMs_ < cfg::DAILY_HEALTH_FALLBACK_MS) return false;
  }

  StaticJsonDocument<192> payload;
  payload["type"] = "health_daily";
  payload["up"] = t.uptime;
  payload["tp"] = (int32_t)lround(t.temperatureC * 10.0f);
  payload["sa"] = t.gps.sats;
  payload["hd"] = (int32_t)lround(t.gps.hdop * 100.0f);
  payload["i2"] = sensors.i2cDevicesFound();
  payload["hf"] = buildHealthFlags(t, fallbackScheduleUsed);
  if (dayKey != 0) payload["dk"] = dayKey;
  payload["scope_id"] = bindingPropertyScopeId_;

  LoRaFrame health;
  health.deviceId = cfg::DEVICE_ID;
  health.scopeId = bindingScopeIdValue();
  health.msgType = MsgType::EVENT;
  health.seq = nextLoRaSeq();
  health.timestamp = t.gps.gpsTime ? t.gps.gpsTime : millis() / 1000;
  randomNonce(health.nonce);
  health.payloadLen = serializeJson(payload, health.payload, sizeof(health.payload));
  if (health.payloadLen == 0) {
    LOGW("Health report diario vazio; envio ignorado");
    return false;
  }
  if (!lora.sendFrame(health)) {
    LOGW("Falha envio health_daily; tentara novamente no proximo ciclo.");
    return false;
  }

  if (dayKey != 0) {
    lastHealthReportDayKey_ = dayKey;
    persistHealthReportDayKey(dayKey);
  }
  healthFallbackAccumMs_ = 0;
  LOGI("Health report diario enviado (day=%lu fallback=%d)",
       (unsigned long)dayKey, fallbackScheduleUsed ? 1 : 0);
  return true;
}

static uint8_t buildTelemetryPayload(const Telemetry& t, uint8_t* out, size_t max) {
  if (!bindingReady_) return 0;
  // Mantem a telemetria em um envelope compacto para reduzir a chance de
  // corrupcao/decrypt failure sob o perfil operacional completo da matriz.
  StaticJsonDocument<160> doc;
  doc["s"] = bindingPropertyScopeId_;
  doc["lat"] = t.gps.lat;
  doc["lon"] = t.gps.lon;
  doc["m"] = (int)t.mode;
  if (isfinite(t.gps.speedKmph)) doc["sp"] = t.gps.speedKmph;
  if (isfinite(t.gps.hdop)) doc["hd"] = t.gps.hdop;
  if (t.gps.sats > 0) doc["sa"] = t.gps.sats;
  return serializeJson(doc, out, max);
}

static void extractCommandMetadataFromPayload(
    const LoRaFrame& frame,
    char* commandId,
    size_t commandIdSize) {
  if (commandId && commandIdSize > 0) {
    commandId[0] = '\0';
  }
  if (!commandId || commandIdSize == 0 || frame.payloadLen == 0) return;

  StaticJsonDocument<192> payload;
  if (deserializeJson(payload, frame.payload, frame.payloadLen) != DeserializationError::Ok) {
    return;
  }
  copyStringToBuffer(
      commandId,
      commandIdSize,
      payload["cmd_id"] | payload["command_id"] | "");
}

static void fillPolygonAuditContext(
    PolygonAuditContext* out,
    MsgType commandType,
    uint64_t scopeId,
    const JsonVariantConst payload) {
  if (!out) return;
  *out = PolygonAuditContext{};
  out->scopeId = scopeId;
  out->commandType = commandType;
  copyStringToBuffer(
      out->commandId,
      sizeof(out->commandId),
      pickFirstText(payload["cmd_id"], payload["command_id"]));
  out->polygonKind = polygonKindFromText(
      pickFirstText(payload["polygon_kind"], payload["polygonKind"]));
  out->originDocType = originDocTypeFromText(
      pickFirstText(payload["origin_doc_type"], payload["originDocType"]));
  copyStringToBuffer(
      out->originDocId,
      sizeof(out->originDocId),
      pickFirstText(
          payload["origin_doc_id"],
          payload["originDocId"],
          payload["operation_id"]));
  if (out->polygonKind == PolygonKind::NONE &&
      commandType == MsgType::SET_HERDING_PLAN) {
    out->polygonKind = PolygonKind::HERDING;
  }
  if (out->originDocType == OriginDocType::NONE &&
      commandType == MsgType::SET_HERDING_PLAN) {
    out->originDocType = OriginDocType::HERDING_OPERATION;
  }
}

static void logPolygonApplySerial(
    const PolygonAuditContext& ctx,
    bool ok,
    const char* errorCode,
    PolygonErrorStage stage,
    int32_t pointCount,
    int32_t phaseCount) {
  if (ok) {
    LOGI(
        "POLYGON_APPLY success cmd=%s command=%s kind=%s origin=%s/%s points=%ld phases=%ld",
        ctx.commandId,
        commandLabel(ctx.commandType),
        polygonKindLabel(ctx.polygonKind),
        originDocTypeLabel(ctx.originDocType),
        ctx.originDocId,
        (long)pointCount,
        (long)phaseCount);
    return;
  }

  LOGW(
      "POLYGON_APPLY failure cmd=%s command=%s kind=%s origin=%s/%s stage=%s error=%s",
      ctx.commandId,
      commandLabel(ctx.commandType),
      polygonKindLabel(ctx.polygonKind),
      originDocTypeLabel(ctx.originDocType),
      ctx.originDocId,
      polygonErrorStageLabel(stage),
      errorCode ? errorCode : "");
}

static void logPolygonApplyResult(
    MsgType commandType,
    uint64_t scopeId,
    PolygonKind polygonKind,
    OriginDocType originDocType,
    const char* originDocId,
    const char* commandId,
    bool ok,
    const char* errorCode,
    PolygonErrorStage errorStage,
    int32_t pointCount,
    int32_t phaseCount) {
  EventRecord ev;
  ev.ts = millis() / 1000;
  ev.type = EventType::POLYGON_APPLY_RESULT;
  ev.d1 = pointCount;
  ev.d2 = phaseCount;
  ev.scopeId = scopeId;
  ev.auditStatus =
      ok ? PolygonApplyStatus::SUCCESS : PolygonApplyStatus::FAILURE;
  ev.polygonKind = polygonKind;
  ev.originDocType = originDocType;
  ev.errorStage = ok ? PolygonErrorStage::NONE : errorStage;
  copyStringToBuffer(
      ev.payload.audit.commandId,
      sizeof(ev.payload.audit.commandId),
      commandId);
  copyStringToBuffer(
      ev.payload.audit.originDocId,
      sizeof(ev.payload.audit.originDocId),
      originDocId);
  copyStringToBuffer(
      ev.payload.audit.errorCode,
      sizeof(ev.payload.audit.errorCode),
      ok ? "" : errorCode);
  storage.pushEvent(ev);

  PolygonAuditContext ctx;
  ctx.scopeId = scopeId;
  ctx.commandType = commandType;
  ctx.polygonKind = polygonKind;
  ctx.originDocType = originDocType;
  copyStringToBuffer(ctx.originDocId, sizeof(ctx.originDocId), originDocId);
  copyStringToBuffer(ctx.commandId, sizeof(ctx.commandId), commandId);
  logPolygonApplySerial(ctx, ok, errorCode, errorStage, pointCount, phaseCount);
}

static void sendCommandFeedback(
    const LoRaFrame& cmd,
    bool ok,
    const char* reason = nullptr,
    const char* status = nullptr,
    const char* operationId = nullptr,
    const char* commandId = nullptr) {
  LoRaFrame reply;
  reply.deviceId = cfg::DEVICE_ID;
  reply.scopeId = cmd.scopeId;
  reply.msgType = ok ? MsgType::ACK : MsgType::NACK;
  reply.seq = nextLoRaSeq();
  reply.timestamp = millis() / 1000;
  randomNonce(reply.nonce);

  StaticJsonDocument<192> payload;
  if (commandId && commandId[0]) {
    payload["cmd_id"] = commandId;
  }
  if (!ok) {
    payload["ok"] = false;
  }
  if (status && status[0]) {
    payload["status"] = status;
  }
  if (reason && reason[0] && strcmp(reason, "pong") != 0) {
    payload["reason"] = reason;
  }
  if (operationId && operationId[0]) {
    payload["operation_id"] = operationId;
  }
  if (payload.isNull() || payload.size() == 0) {
    payload["ok"] = ok;
  }
  reply.payloadLen = serializeJson(payload, reply.payload, sizeof(reply.payload));

  if (cfg::LORA_COMMAND_FEEDBACK_DELAY_MS > 0) {
    delay(cfg::LORA_COMMAND_FEEDBACK_DELAY_MS);
  }
  if (!lora.sendFrame(reply)) {
    LOGW("Falha ao enviar %s para cmd=%u seq=%lu",
         ok ? "ACK" : "NACK", (unsigned)cmd.msgType, cmd.seq);
  }
}

static void applyDownlink(const LoRaFrame& frame) {
  const bool targetMatch = (frame.deviceId == cfg::DEVICE_ID) || (frame.deviceId == 0);
  if (!targetMatch) return;

  char commandId[cfg::EVENT_COMMAND_ID_MAX_LEN]{};
  extractCommandMetadataFromPayload(frame, commandId, sizeof(commandId));
  const bool polygonAuditCommand =
      frame.msgType == MsgType::SET_FENCE ||
      frame.msgType == MsgType::SET_HERDING_PLAN;

  StaticJsonDocument<512> doc;
  const bool docReady =
      deserializeJson(doc, frame.payload, frame.payloadLen) ==
      DeserializationError::Ok;
  if (docReady) {
    const char* parsedCommandId = pickFirstText(doc["cmd_id"], doc["command_id"]);
    if (parsedCommandId[0] != '\0') {
      copyStringToBuffer(commandId, sizeof(commandId), parsedCommandId);
    }
  }

  PolygonAuditContext auditCtx;
  if (polygonAuditCommand) {
    auditCtx.scopeId = frame.scopeId;
    auditCtx.commandType = frame.msgType;
    copyStringToBuffer(auditCtx.commandId, sizeof(auditCtx.commandId), commandId);
    if (docReady) {
      fillPolygonAuditContext(
          &auditCtx, frame.msgType, frame.scopeId, doc.as<JsonVariantConst>());
    } else if (frame.msgType == MsgType::SET_HERDING_PLAN) {
      auditCtx.polygonKind = PolygonKind::HERDING;
      auditCtx.originDocType = OriginDocType::HERDING_OPERATION;
    }
  }

  if (!bindingReady_) {
    if (polygonAuditCommand && frame.scopeId != 0) {
      logPolygonApplyResult(
          frame.msgType,
          frame.scopeId,
          auditCtx.polygonKind,
          auditCtx.originDocType,
          auditCtx.originDocId,
          auditCtx.commandId,
          false,
          "property_binding_missing",
          PolygonErrorStage::BINDING);
    }
    sendCommandFeedback(
        frame, false, "property_binding_missing", nullptr, nullptr, commandId);
    return;
  }
  if (frame.scopeId == 0 || frame.scopeId != bindingScopeIdValue()) {
    if (polygonAuditCommand && frame.scopeId != 0) {
      logPolygonApplyResult(
          frame.msgType,
          frame.scopeId,
          auditCtx.polygonKind,
          auditCtx.originDocType,
          auditCtx.originDocId,
          auditCtx.commandId,
          false,
          "property_scope_mismatch",
          PolygonErrorStage::SCOPE);
    }
    sendCommandFeedback(
        frame, false, "property_scope_mismatch", nullptr, nullptr, commandId);
    return;
  }

  if (frame.msgType == MsgType::PING) {
    sendCommandFeedback(frame, true, "pong", nullptr, nullptr, commandId);
    return;
  }

  if (frame.msgType != MsgType::SET_FENCE &&
      frame.msgType != MsgType::SET_HERDING_PLAN &&
      frame.msgType != MsgType::SET_PARAMS) {
    return;
  }

  if (!docReady) {
    if (polygonAuditCommand) {
      logPolygonApplyResult(
          frame.msgType,
          frame.scopeId,
          auditCtx.polygonKind,
          auditCtx.originDocType,
          auditCtx.originDocId,
          auditCtx.commandId,
          false,
          "invalid_json",
          PolygonErrorStage::PARSE);
    }
    sendCommandFeedback(frame, false, "invalid_json", nullptr, nullptr, commandId);
    return;
  }

  if (frame.msgType == MsgType::SET_FENCE) {
    const char* err = nullptr;
    const bool chunked = doc["chunked"].is<bool>() && doc["chunked"].as<bool>();
    if (chunked) {
      if (!applyFenceChunkJson(doc.as<JsonObject>(), &err)) {
        const PolygonAuditContext& failureAudit =
            fenceChunkRx_.audit.commandId[0] != '\0' ? fenceChunkRx_.audit : auditCtx;
        logPolygonApplyResult(
            MsgType::SET_FENCE,
            failureAudit.scopeId != 0 ? failureAudit.scopeId : frame.scopeId,
            failureAudit.polygonKind,
            failureAudit.originDocType,
            failureAudit.originDocId,
            failureAudit.commandId[0] != '\0' ? failureAudit.commandId : commandId,
            false,
            err ? err : "invalid_fence_chunk",
            polygonErrorStageFromReason(err ? err : "invalid_fence_chunk"));
        sendCommandFeedback(frame, false, err ? err : "invalid_fence_chunk", nullptr, nullptr, commandId);
        return;
      }
      sendCommandFeedback(frame, true, nullptr, nullptr, nullptr, commandId);
    } else {
      resetFenceChunkRx();
      Polygon p;
      if (!parsePolygonJson(doc["points"].as<JsonArray>(), &p, &err)) {
        logPolygonApplyResult(
            MsgType::SET_FENCE,
            auditCtx.scopeId != 0 ? auditCtx.scopeId : frame.scopeId,
            auditCtx.polygonKind,
            auditCtx.originDocType,
            auditCtx.originDocId,
            auditCtx.commandId,
            false,
            err ? err : "invalid_fence",
            polygonErrorStageFromReason(err ? err : "invalid_fence"));
        sendCommandFeedback(frame, false, err ? err : "invalid_fence", nullptr, nullptr, commandId);
        return;
      }
      geofence.setFence(p);
      if (!persistFence(p)) {
        logPolygonApplyResult(
            MsgType::SET_FENCE,
            auditCtx.scopeId != 0 ? auditCtx.scopeId : frame.scopeId,
            auditCtx.polygonKind,
            auditCtx.originDocType,
            auditCtx.originDocId,
            auditCtx.commandId,
            false,
            "persist_fence_failed",
            PolygonErrorStage::PERSIST);
        sendCommandFeedback(
            frame,
            false,
            "persist_fence_failed",
            nullptr,
            nullptr,
            commandId);
        return;
      }
      logPolygonApplyResult(
          MsgType::SET_FENCE,
          auditCtx.scopeId != 0 ? auditCtx.scopeId : frame.scopeId,
          auditCtx.polygonKind,
          auditCtx.originDocType,
          auditCtx.originDocId,
          auditCtx.commandId,
          true,
          nullptr,
          PolygonErrorStage::NONE,
          p.count,
          0);
      sendCommandFeedback(frame, true, nullptr, nullptr, nullptr, commandId);
    }
  } else if (frame.msgType == MsgType::SET_HERDING_PLAN) {
    const char* err = nullptr;
    const bool chunked = doc["chunked"].is<bool>() && doc["chunked"].as<bool>();
    if (chunked) {
      if (!applyHerdChunkJson(doc.as<JsonObject>(), &err)) {
        const PolygonAuditContext& failureAudit =
            herdChunkRx_.audit.commandId[0] != '\0' ? herdChunkRx_.audit : auditCtx;
        logPolygonApplyResult(
            MsgType::SET_HERDING_PLAN,
            failureAudit.scopeId != 0 ? failureAudit.scopeId : frame.scopeId,
            failureAudit.polygonKind,
            failureAudit.originDocType,
            failureAudit.originDocId[0] != '\0'
                ? failureAudit.originDocId
                : herding.plan().operationId,
            failureAudit.commandId[0] != '\0' ? failureAudit.commandId : commandId,
            false,
            err ? err : "invalid_herd_chunk",
            polygonErrorStageFromReason(err ? err : "invalid_herd_chunk"));
        sendCommandFeedback(frame, false, err ? err : "invalid_herd_chunk", nullptr, nullptr, commandId);
        return;
      }
      const bool herdCompletedAssembly =
          !herdChunkRx_.active && herding.plan().operationId[0] != '\0';
      if (herdCompletedAssembly) {
        sendCommandFeedback(
            frame,
            true,
            "assembled",
            "assembled",
            herding.plan().operationId,
            commandId);
      }
    } else {
      resetHerdChunkRx();
      HerdingPlan plan;
      if (!parseHerdingPlanJson(doc["phases"].as<JsonArray>(), &plan, &err)) {
        logPolygonApplyResult(
            MsgType::SET_HERDING_PLAN,
            auditCtx.scopeId != 0 ? auditCtx.scopeId : frame.scopeId,
            auditCtx.polygonKind,
            auditCtx.originDocType,
            auditCtx.originDocId,
            auditCtx.commandId,
            false,
            err ? err : "invalid_herd_plan",
            polygonErrorStageFromReason(err ? err : "invalid_herd_plan"));
        sendCommandFeedback(frame, false, err ? err : "invalid_herd_plan", nullptr, nullptr, commandId);
        return;
      }
      copyStringToBuffer(
          plan.operationId,
          sizeof(plan.operationId),
          doc["operation_id"] | "");
      herding.setPlan(plan);
      if (!persistHerdingPlan(plan)) {
        logPolygonApplyResult(
            MsgType::SET_HERDING_PLAN,
            auditCtx.scopeId != 0 ? auditCtx.scopeId : frame.scopeId,
            auditCtx.polygonKind,
            auditCtx.originDocType,
            auditCtx.originDocId[0] != '\0' ? auditCtx.originDocId : plan.operationId,
            auditCtx.commandId,
            false,
            "persist_herd_plan_failed",
            PolygonErrorStage::PERSIST);
        sendCommandFeedback(
            frame,
            false,
            "persist_herd_plan_failed",
            nullptr,
            nullptr,
            commandId);
        return;
      }
      stateMachine.setMode(CollarMode::CONDUCAO);
      logEvent(EventType::HERD_START, plan.phaseCount, 0);
      logPolygonApplyResult(
          MsgType::SET_HERDING_PLAN,
          auditCtx.scopeId != 0 ? auditCtx.scopeId : frame.scopeId,
          auditCtx.polygonKind,
          auditCtx.originDocType,
          auditCtx.originDocId[0] != '\0' ? auditCtx.originDocId : plan.operationId,
          auditCtx.commandId,
          true,
          nullptr,
          PolygonErrorStage::NONE,
          plan.phaseCount > 0 ? plan.phases[plan.phaseCount - 1].count : 0,
          plan.phaseCount);
      sendCommandFeedback(
          frame,
          true,
          "assembled",
          "assembled",
          plan.operationId,
          commandId);
    }
  } else if (frame.msgType == MsgType::SET_PARAMS) {
    if (doc["wifi_ota_enabled"].is<bool>()) {
      const bool enableWifi = doc["wifi_ota_enabled"].as<bool>();
      if (!enableWifi && !hasAdminModePermission(doc.as<JsonVariantConst>())) {
        LOGW("SET_PARAMS rejeitado: admin requerido para LoRa-only");
        sendCommandFeedback(frame, false, "admin_required_for_lora_only", nullptr, nullptr, commandId);
        return;
      }
      applyWifiOtaMode(enableWifi, "LoRa");
      sendCommandFeedback(frame, true, nullptr, nullptr, nullptr, commandId);
    } else {
      LOGW("SET_PARAMS sem campo wifi_ota_enabled");
      sendCommandFeedback(frame, false, "missing_wifi_ota_enabled", nullptr, nullptr, commandId);
    }
  }
}

static void runSmartGpsSelfTest() {
  LOGI("SMART_GPS_TEST_MODE ativo: simulando raw vs official");
  const double baseLat = -20.123456;
  const double baseLon = -43.987654;
  const float jitter[] = {0.0f, 0.000002f, -0.000003f, 0.000001f, -0.000002f, 0.000003f, -0.000001f, 0.000002f};
  uint32_t nowMs = 0;

  for (uint8_t i = 0; i < (sizeof(jitter) / sizeof(jitter[0])); ++i) {
    GpsData raw;
    raw.valid = true;
    raw.lat = baseLat + (double)jitter[i];
    raw.lon = baseLon - (double)jitter[i];
    raw.speedKmph = 0.4f;
    raw.hdop = 0.9f;
    raw.sats = 10;
    raw.gpsTime = 120000 + i;
    nowMs += 5000;

    const SmartFixResult smart = smartGps.update(raw, false, nowMs);
    Serial.printf(
        "[SMART_TEST] jitter i=%u raw=(%.6f,%.6f hdop=%.2f sat=%u) off=(%.6f,%.6f) valid=%d flt=%d lck=%d out=%d invalid=%d\n",
        i,
        raw.lat,
        raw.lon,
        raw.hdop,
        raw.sats,
        smart.officialFix.lat,
        smart.officialFix.lon,
        smart.officialFix.valid ? 1 : 0,
        smart.officialFix.filtered ? 1 : 0,
        smart.officialFix.locked ? 1 : 0,
        smart.flags.outlierDropped ? 1 : 0,
        smart.flags.invalidFixRejected ? 1 : 0);
  }

  {
    GpsData raw;
    raw.valid = true;
    raw.lat = baseLat + 0.0200;
    raw.lon = baseLon + 0.0200;
    raw.speedKmph = 0.3f;
    raw.hdop = 0.9f;
    raw.sats = 10;
    raw.gpsTime = 130000;
    nowMs += 5000;

    const SmartFixResult smart = smartGps.update(raw, false, nowMs);
    Serial.printf(
        "[SMART_TEST] outlier raw=(%.6f,%.6f) off=(%.6f,%.6f) lck=%d out=%d speed=%.2f\n",
        raw.lat,
        raw.lon,
        smart.officialFix.lat,
        smart.officialFix.lon,
        smart.officialFix.locked ? 1 : 0,
        smart.flags.outlierDropped ? 1 : 0,
        smart.flags.outlierSpeedMps);
  }

  {
    GpsData raw;
    raw.valid = true;
    raw.lat = baseLat + 0.000001;
    raw.lon = baseLon - 0.000001;
    raw.speedKmph = 0.2f;
    raw.hdop = 4.5f;
    raw.sats = 9;
    raw.gpsTime = 131000;
    nowMs += 5000;

    const SmartFixResult smart = smartGps.update(raw, false, nowMs);
    Serial.printf(
        "[SMART_TEST] bad-hdop raw_hdop=%.2f off=(%.6f,%.6f) valid=%d invalid=%d\n",
        raw.hdop,
        smart.officialFix.lat,
        smart.officialFix.lon,
        smart.officialFix.valid ? 1 : 0,
        smart.flags.invalidFixRejected ? 1 : 0);
  }

  {
    GpsData raw;
    raw.valid = true;
    raw.lat = baseLat + 0.000150;
    raw.lon = baseLon + 0.000120;
    raw.speedKmph = 4.0f;
    raw.hdop = 0.8f;
    raw.sats = 12;
    raw.gpsTime = 132000;
    nowMs += 5000;

    const SmartFixResult smart = smartGps.update(raw, true, nowMs);
    Serial.printf(
        "[SMART_TEST] moving raw=(%.6f,%.6f) off=(%.6f,%.6f) lck=%d changed=%d\n",
        raw.lat,
        raw.lon,
        smart.officialFix.lat,
        smart.officialFix.lon,
        smart.officialFix.locked ? 1 : 0,
        smart.flags.lockStateChanged ? 1 : 0);
  }
}

void setup() {
  bootStartedAtMs_ = millis();
  lastResetReason_ = esp_reset_reason();
  Serial.begin(cfg::SERIAL_BAUD);
  LOGI("Boot reset_reason=%d", (int)lastResetReason_);
  recordBootStage("serial");
  watchdogOwnerTask = xTaskGetCurrentTaskHandle();
  if (cfg::TASK_WDT_ENABLED) {
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
  } else {
    LOGW("TWDT desabilitado na coleira para validacao de bancada");
    loopTaskWDTEnabled = false;
    disableLoopWDT();
    const esp_err_t deinitErr = esp_task_wdt_deinit();
    if (deinitErr != ESP_OK && deinitErr != ESP_ERR_INVALID_STATE) {
      LOGW("TWDT deinit falhou err=%d; removendo tarefas IDLE", (int)deinitErr);
      disableCore0WDT();
#ifndef CONFIG_FREERTOS_UNICORE
      disableCore1WDT();
#endif
    }
  }
  recordBootStage("wdt");
  incrementBootCounter();
  recordBootStage("prefs_counter");
  loadPersistedConfig();
  recordBootStage("load_config");

  if (cfg::SMART_GPS_TEST_MODE) {
    recordBootStage("smart_gps_test");
    smartGps.begin();
    runSmartGpsSelfTest();
    return;
  }

  WiFi.persistent(false);
  WiFi.onEvent(onWifiEvent);
  recordBootStage("wifi_event");

  configureStatusServerRoutes();
  recordBootStage("status_routes");
  setupWifiOtaMaintenance();
  recordBootStage("wifi_ota");
  recordBootStage("status_server");
  waitMaintenanceWindow();
  bool bleInitOk = !cfg::BLE_PRESENCE_ENABLED;
  if (cfg::BLE_PRESENCE_ENABLED) {
    recordBootStage("ble_begin");
    const String nodeId = collarNodeId();
    bleInitOk = blePresence.begin(
        BleNodeKind::COLLAR,
        nodeId,
        collarAdvName(),
        cfg::BLE_COMPANY_ID,
        cfg::BLE_SERVICE_UUID);
    blePresence.setEnabled(shouldBlePresenceBeEnabled());
    blePresence.setFlags(wifiOtaEnabled, WiFi.status() == WL_CONNECTED);
  }

  recordBootStage("sensors_begin");
  sensors.begin();
  recordBootStage("safety_begin");
  safety.begin();
  recordBootStage("storage_begin");
  storageReady_ = storage.begin();
  if (!storageReady_) LOGW("StorageQueue indisponivel");
  recordBootStage("smart_gps_begin");
  smartGps.begin();
  refreshBlePositionForOnboarding();
  recordBootStage("lora_begin");
  loraReady_ = lora.begin();
  if (!loraReady_) LOGE("LoRa indisponivel");
  if (loraReady_ && cfg::LORA_POST_BEGIN_SETTLE_MS > 0) {
    delay(cfg::LORA_POST_BEGIN_SETTLE_MS);
  }
  setWatchdogEnabled(wifiOtaEnabled);
  recordBootStage("checklist");
  printBootChecklist(bleInitOk, storageReady_, loraReady_);
  recordBootStage("ready");

  LOGI("Coleira inicializada: id=%lu fw=%s", cfg::DEVICE_ID, cfg::FW_VERSION);
}

void loop() {
  if (cfg::SMART_GPS_TEST_MODE) {
    delay(2000);
    return;
  }

  ensureWifiOtaMaintenance();
  if (statusServerRunning_) {
    statusServer.handleClient();
  }

  const bool apClientConnected = otaApClientConnected();
  if (wifiOtaEnabled && otaModeActive) {
    ArduinoOTA.handle();
    feedWatchdogIfEnabled();
    if (otaUploadInProgress) {
      delay(2);
      return;
    }
  }
  const bool otaSessionLikelyActive = otaUploadInProgress || apClientConnected;

  feedWatchdogIfEnabled();
  if (cfg::BLE_PRESENCE_ENABLED) {
    const bool bleEnabled = shouldBlePresenceBeEnabled();
    blePresence.setEnabled(bleEnabled);
    blePresence.setFlags(wifiOtaEnabled, WiFi.status() == WL_CONNECTED);
    if (bleEnabled) blePresence.loop();
    if (bleEnabled && blePresence.clientConnected()) {
      // Durante leitura BLE no onboarding, evita janela longa de LoRa/JSON que
      // pode causar timeout no readCharacteristic do app iOS.
      feedWatchdogIfEnabled();
      delay(2);
      return;
    }
  }

  // Prioriza OTA quando cliente esta conectado no AP.
  // Evita timeouts "No response from device" por janelas LoRa/sensores.
  if (wifiOtaEnabled && otaModeActive && apClientConnected && !otaUploadInProgress) {
    delay(2);
    return;
  }

  sensors.tick();
  refreshBlePositionForOnboarding();

  const uint32_t now = millis();
  if (now - lastCycle < stateMachine.intervalMs()) {
    delay(20);
    return;
  }
  lastCycle = now;

  const Telemetry rawTelemetry = sensors.readTelemetry(stateMachine.mode(), now / 1000, lora.lastRssi(), lora.lastSnr());
  const bool movingByGpsSpeed =
      rawTelemetry.gps.valid &&
      rawTelemetry.gps.sats >= cfg::MIN_SATS &&
      rawTelemetry.gps.hdop <= cfg::MAX_HDOP &&
      rawTelemetry.gps.speedKmph >= cfg::GPS_SPEED_MOVE_THRESHOLD_KMPH;
  const bool movingForSmartFix = rawTelemetry.moving || movingByGpsSpeed;
  const SmartFixResult smartFix = smartGps.update(rawTelemetry.gps, movingForSmartFix, now);

  Telemetry t = rawTelemetry;
  t.gps = smartFix.officialFix;
  t.moving = movingForSmartFix;

  lastGpsForStatus_ = t.gps;
  hasLastGpsForStatus_ = t.gps.valid;
  if (cfg::BLE_PRESENCE_ENABLED) {
    updateBlePositionForOnboarding(&t.gps, &rawTelemetry.gps);
  }

  if (smartFix.flags.invalidFixRejected &&
      (lastGpsInvalidFixEventAtMs_ == 0 ||
       (uint32_t)(now - lastGpsInvalidFixEventAtMs_) >= 15000UL)) {
    logEvent(EventType::GPS_INVALID_FIX, (int32_t)lround(rawTelemetry.gps.hdop * 100.0f), rawTelemetry.gps.sats);
    lastGpsInvalidFixEventAtMs_ = now;
  }
  if (smartFix.flags.outlierDropped &&
      (lastGpsOutlierEventAtMs_ == 0 ||
       (uint32_t)(now - lastGpsOutlierEventAtMs_) >= 15000UL)) {
    logEvent(EventType::GPS_OUTLIER, (int32_t)lround(smartFix.flags.outlierSpeedMps * 100.0f), 0);
    lastGpsOutlierEventAtMs_ = now;
  }
  if (smartFix.flags.lockStateChanged) {
    logEvent(t.gps.locked ? EventType::GPS_LOCKED : EventType::GPS_UNLOCKED);
  }
  if (!t.gps.valid) {
    if (!gpsFailEventActive_ ||
        lastGpsFailEventAtMs_ == 0 ||
        (uint32_t)(now - lastGpsFailEventAtMs_) >= 60000UL) {
      logEvent(EventType::GPS_FAIL);
      lastGpsFailEventAtMs_ = now;
      gpsFailEventActive_ = true;
    }
  } else {
    gpsFailEventActive_ = false;
  }

  const bool inside = geofence.isInside(t.gps);
  const bool nearBoundary = geofence.isNearBoundary(t.gps, cfg::FENCE_WARNING_METERS);

  if (nearBoundary && inside) {
    safety.beep(1);
    logEvent(EventType::APPROACH);
  }

  if (!inside && t.gps.valid) {
    if (violationStart == 0) {
      violationStart = now;
      logEvent(EventType::VIOLATION);
      safety.beep(2);
      stateMachine.setMode(CollarMode::ALERTA);
    } else if (now - violationStart > cfg::VIOLATION_PERSIST_MS && sensors.gpsHealthy(t.gps) && safety.canPulse(t.gps)) {
      safety.pulseLight();
      logEvent(EventType::PULSE_APPLIED);
    }
  } else {
    if (!wasInside && inside) logEvent(EventType::RETURNED);
    violationStart = 0;
    if (stateMachine.mode() != CollarMode::CONDUCAO) stateMachine.setMode(CollarMode::NORMAL);
  }
  wasInside = inside;

  EventRecord herdEvent;
  if (herding.updateWithGps(t.gps, &herdEvent)) {
    if (herdEvent.type == EventType::HERD_DONE) {
      promoteCompletedHerdingFence();
    }
    logEvent(herdEvent.type, herdEvent.d1, herdEvent.d2);
    persistHerdingPlan(herding.plan());
    if (!herding.active() && stateMachine.mode() == CollarMode::CONDUCAO) {
      stateMachine.setMode(CollarMode::NORMAL);
    }
  }

  if (bindingReady_) {
    LoRaFrame uplink;
    uplink.deviceId = cfg::DEVICE_ID;
    uplink.scopeId = bindingScopeIdValue();
    uplink.msgType = MsgType::TELEMETRY;
    uplink.seq = nextLoRaSeq();
    uplink.timestamp = t.gps.gpsTime ? t.gps.gpsTime : now / 1000;
    randomNonce(uplink.nonce);
    uplink.payloadLen = buildTelemetryPayload(t, uplink.payload, sizeof(uplink.payload));

    lastLoRaTxOk_ = uplink.payloadLen > 0 && lora.sendFrame(uplink);
    if (!lastLoRaTxOk_) {
      LOGW("Falha envio telemetria; permanece em fila local.");
    }
  } else {
    lastLoRaTxOk_ = false;
  }
  sendDailyHealthReport(t, stateMachine.intervalMs());

  LoRaFrame down;
  const uint32_t rxWindowMs = otaSessionLikelyActive
                                  ? cfg::OTA_UPLOAD_RX_WINDOW_MS
                                  : cfg::RX_WINDOW_MS;
  bool handledDownlink = false;
  if (lora.receiveFrame(down, rxWindowMs)) {
    applyDownlink(down);
    handledDownlink = true;
  }

  if (handledDownlink && cfg::LORA_POST_COMMAND_EVENT_HOLDOFF_MS > 0) {
    delay(cfg::LORA_POST_COMMAND_EVENT_HOLDOFF_MS);
  }

  EventRecord pending;
  uint8_t eventBudget = otaSessionLikelyActive ? cfg::OTA_UPLOAD_EVENT_BURST : 0xFF;
  while (!handledDownlink && bindingReady_ && storage.popEvent(pending)) {
    LoRaFrame ev;
    ev.deviceId = cfg::DEVICE_ID;
    ev.scopeId = pending.scopeId != 0 ? pending.scopeId : bindingScopeIdValue();
    ev.msgType = MsgType::EVENT;
    ev.seq = nextLoRaSeq();
    ev.timestamp = pending.ts;
    randomNonce(ev.nonce);
    StaticJsonDocument<384> d;
    d["type"] = eventTypeLabel(pending.type);
    d["event_type"] = eventTypeLabel(pending.type);
    d["event_code"] = (int)pending.type;
    d["d1"] = pending.d1;
    d["d2"] = pending.d2;
    d["scope_id"] = scopeIdToHex(ev.scopeId);
    if (pending.type != EventType::POLYGON_APPLY_RESULT &&
        pending.payload.operationId[0] != '\0') {
      d["operation_id"] = pending.payload.operationId;
    }
    if (pending.type == EventType::HERD_PHASE_CHANGE) {
      d["phase_index"] = pending.d1;
    } else if (pending.type == EventType::POLYGON_APPLY_RESULT) {
      d["status"] = polygonApplyStatusLabel(pending.auditStatus);
      d["command"] = commandLabel(
          pending.polygonKind == PolygonKind::HERDING
              ? MsgType::SET_HERDING_PLAN
              : MsgType::SET_FENCE);
      d["polygon_kind"] = polygonKindLabel(pending.polygonKind);
      d["origin_doc_type"] = originDocTypeLabel(pending.originDocType);
      if (pending.payload.audit.originDocId[0] != '\0') {
        d["origin_doc_id"] = pending.payload.audit.originDocId;
      }
      if (pending.payload.audit.commandId[0] != '\0') {
        d["cmd_id"] = pending.payload.audit.commandId;
      }
      if (pending.d1 > 0) d["point_count"] = pending.d1;
      if (pending.d2 > 0) d["phase_count"] = pending.d2;
      if (pending.auditStatus == PolygonApplyStatus::FAILURE &&
          pending.payload.audit.errorCode[0] != '\0') {
        d["error_code"] = pending.payload.audit.errorCode;
      }
      const char* errorStage = polygonErrorStageLabel(pending.errorStage);
      if (errorStage[0] != '\0') {
        d["error_stage"] = errorStage;
      }
      if (pending.originDocType == OriginDocType::HERDING_OPERATION &&
          pending.payload.audit.originDocId[0] != '\0') {
        d["operation_id"] = pending.payload.audit.originDocId;
      }
    }
    ev.payloadLen = serializeJson(d, ev.payload, sizeof(ev.payload));
    if (!lora.sendFrame(ev)) break;
    if (otaSessionLikelyActive) {
      if (--eventBudget == 0) break;
      ArduinoOTA.handle();
      delay(2);
    }
  }

  // Com Wi-Fi/OTA ativo, permanece online continuamente para manutenção remota.
  if (wifiOtaEnabled) {
    delay(20);
    return;
  }

  // Em LoRa-only, usa deep sleep para economia de energia.
  esp_sleep_enable_timer_wakeup((uint64_t)stateMachine.intervalMs() * 1000ULL);
  esp_deep_sleep_start();
}
