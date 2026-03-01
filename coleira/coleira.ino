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

RTC_DATA_ATTR uint32_t seq = 1;
uint32_t seqPersistedHi_ = 0;
bool seqPersistReady_ = false;
uint32_t lastCycle = 0;
uint32_t violationStart = 0;
bool wasInside = true;
bool otaModeActive = false;
bool wifiOtaEnabled = cfg::WIFI_OTA_DEFAULT_ENABLED;
bool watchdogTaskRegistered = false;
bool otaUploadInProgress = false;
uint32_t wifiOtaEnabledAtMs = 0;
uint32_t otaApLastClientSeenMs = 0;
uint32_t otaRecoveryAttemptAtMs = 0;
uint8_t otaRecoveryAttemptCount = 0;
Preferences prefs_;
bool prefsReady_ = false;
GpsData lastGpsForStatus_;
bool hasLastGpsForStatus_ = false;
static void logEvent(EventType type, int32_t d1, int32_t d2);
static bool beginPrefs();
static void refreshBlePositionForOnboarding();
static void printBootChecklist(bool bleInitOk, bool storageOk, bool loraOk);
static void runSmartGpsSelfTest();

struct FenceChunkRxState {
  bool active = false;
  uint8_t totalParts = 0;
  uint8_t expectedPart = 0;
  Polygon fence{};
} fenceChunkRx_;

struct HerdChunkRxState {
  bool active = false;
  uint8_t phaseTotal = 0;
  uint8_t currentPhase = 0;
  uint8_t expectedPart = 0;
  uint8_t totalPartsCurrentPhase = 0;
  Polygon phaseAccum{};
  HerdingPlan plan{};
} herdChunkRx_;

static void randomNonce(uint8_t* nonce12) {
  for (int i = 0; i < 12; ++i) nonce12[i] = (uint8_t)esp_random();
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
  if (seq == 0) seq = 1;
  if (!beginPrefs()) {
    seqPersistReady_ = false;
    seqPersistedHi_ = seq - 1;
    LOGW("NVS indisponivel para seq uplink; fallback RTC only (next=%lu)", seq);
    return;
  }

  const uint32_t persistedHi = prefs_.getULong(cfg::PREF_KEY_LORA_SEQ_HI, 0);
  seqPersistedHi_ = persistedHi;
  seqPersistReady_ = true;
  if (persistedHi >= seq) {
    seq = persistedHi + 1;
    if (seq == 0) seq = 1;
  }
  LOGI("Seq uplink restaurado next=%lu hi=%lu", seq, seqPersistedHi_);
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
  String suffix = String((uint32_t)cfg::DEVICE_ID, HEX);
  suffix.toUpperCase();
  if (suffix.length() > 6) suffix = suffix.substring(suffix.length() - 6);
  String ssid = String(cfg::OTA_AP_SSID) + "-" + suffix;
  if (ssid.length() > 31) ssid = ssid.substring(0, 31);
  return ssid;
}

static void setupStatusServer() {
  statusServer.on("/status", HTTP_GET, []() {
    StaticJsonDocument<512> doc;
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
  statusServer.begin();
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
    return false;
  }
  for (uint8_t i = 0; i < plan->phaseCount; ++i) {
    if (!isValidPolygon(plan->phases[i])) {
      plan->active = false;
      plan->phaseCount = 0;
      plan->currentPhase = 0;
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

static void persistFence(const Polygon& fence) {
  if (!beginPrefs()) return;
  prefs_.putBytes(cfg::PREF_KEY_FENCE, &fence, sizeof(fence));
}

static void persistHerdingPlan(const HerdingPlan& plan) {
  if (!beginPrefs()) return;
  prefs_.putBytes(cfg::PREF_KEY_HERD, &plan, sizeof(plan));
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

static void loadPersistedConfig() {
  wifiOtaEnabled = loadPersistedWifiOtaEnabled();
  if (wifiOtaEnabled) wifiOtaEnabledAtMs = millis();
  restoreLoRaSeq();

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
    persistFence(fenceChunkRx_.fence);
    LOGI("SET_FENCE chunked aplicado com %u pontos", fenceChunkRx_.fence.count);
    resetFenceChunkRx();
  }
  return true;
}

static bool applyHerdChunkJson(const JsonObject& doc, const char** err) {
  const int phaseIdx = doc["phase_index"] | -1;
  const int phaseTotal = doc["phase_total"] | -1;
  const int part = doc["part"] | -1;
  const int total = doc["total"] | -1;
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
      persistHerdingPlan(herdChunkRx_.plan);
      stateMachine.setMode(CollarMode::CONDUCAO);
      logEvent(EventType::HERD_START, herdChunkRx_.plan.phaseCount, 0);
      LOGI("SET_HERDING_PLAN chunked aplicado: fases=%u", herdChunkRx_.plan.phaseCount);
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
  if (enabled && !watchdogTaskRegistered) {
    esp_task_wdt_add(NULL);
    watchdogTaskRegistered = true;
  } else if (!enabled && watchdogTaskRegistered) {
    esp_task_wdt_delete(NULL);
    watchdogTaskRegistered = false;
  }
}

static void stopWifiOtaMaintenance() {
  otaModeActive = false;
  otaRecoveryAttemptCount = 0;
  otaRecoveryAttemptAtMs = 0;
  if (WiFi.getMode() == WIFI_STA || WiFi.getMode() == WIFI_AP_STA) {
    WiFi.disconnect(true, true);
  }
  if (WiFi.getMode() == WIFI_AP || WiFi.getMode() == WIFI_AP_STA) {
    WiFi.softAPdisconnect(true);
  }
  WiFi.mode(WIFI_OFF);
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
    MDNS.addService("arduino", "tcp", 3232);
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

static void refreshBlePositionForOnboarding() {
  if (!cfg::BLE_PRESENCE_ENABLED) return;

  // Prioriza última posição oficial já validada (inclusive restaurada da EEPROM).
  if (smartGps.hasLastGoodFix()) {
    const GpsData& lastGood = smartGps.lastGoodFix();
    blePresence.setPosition(lastGood.lat, lastGood.lon, lastGood.valid);
    return;
  }

  // Sem last-good ainda: onboarding BLE aceita fix bruto valido para reduzir
  // bloqueio no cadastro inicial; a telemetria oficial continua com gate estrito.
  const GpsData live = sensors.readGpsSnapshot();
  const bool hasUsableFix = live.valid;
  blePresence.setPosition(live.lat, live.lon, hasUsableFix);
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
  String gpsBootDetail = String("baud=") + sensors.gpsBaudUsed() +
      " bytes=" + sensors.gpsBootBytes() +
      " nmea=$" + sensors.gpsBootDollarCount() +
      " sample=" + sensors.gpsBootSample();
  checklistLine(
      "GPS_BOOT_RX",
      sensors.gpsBootBytes() > 0,
      "Nenhum byte recebido no boot; verificar TX do GPS->D16, alimentacao e GND.",
      gpsBootDetail.c_str());
  const bool gpsHasRxBytes = sensors.gpsBootBytes() > 0;
  const char* gpsNmeaOffHint = gpsHasRxBytes
      ? "Recebe bytes sem '$'; verificar baud do GPS (9600/38400/57600/115200), TX->D16 e ruido na UART."
      : "Sem sentencas NMEA no boot; verificar TX do GPS->D16, alimentacao e visada do ceu.";
  checklistLine(
      "GPS_NMEA",
      sensors.gpsNmeaSeen(),
      gpsNmeaOffHint);

  const bool i2cBusAlive = sensors.i2cDevicesFound() > 0;
  const String i2cDetail = String("found=") + sensors.i2cDevicesFound() +
      " [" + sensors.i2cScanSummary() + "]";
  checklistLine(
      "I2C_BUS_SCAN",
      i2cBusAlive,
      "Nenhum dispositivo I2C detectado; revisar SDA/SCL, 3v3 e GND.",
      i2cDetail.c_str());

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
  storage.pushEvent(ev);
}

static uint8_t buildTelemetryPayload(const Telemetry& t, uint8_t* out, size_t max) {
  StaticJsonDocument<256> doc;
  doc["fw"] = cfg::FW_VERSION;
  doc["uptime"] = t.uptime;
  doc["mode"] = (int)t.mode;
  doc["tmp"] = t.temperatureC;
  doc["mov"] = t.moving;
  doc["rssi"] = t.rssi;
  doc["snr"] = t.snr;
  doc["lat"] = t.gps.lat;
  doc["lon"] = t.gps.lon;
  doc["spd"] = t.gps.speedKmph;
  doc["hdop"] = t.gps.hdop;
  doc["sat"] = t.gps.sats;
  doc["gok"] = t.gps.valid;
  doc["flt"] = t.gps.filtered;
  doc["lck"] = t.gps.locked;
  doc["od"] = t.gps.outlierDropped;
  return serializeJson(doc, out, max);
}

static void sendCommandFeedback(const LoRaFrame& cmd, bool ok, const char* reason = nullptr) {
  LoRaFrame reply;
  reply.deviceId = cfg::DEVICE_ID;
  reply.msgType = ok ? MsgType::ACK : MsgType::NACK;
  reply.seq = nextLoRaSeq();
  reply.timestamp = millis() / 1000;
  randomNonce(reply.nonce);

  StaticJsonDocument<128> payload;
  payload["cmd"] = (int)cmd.msgType;
  payload["cmd_seq"] = cmd.seq;
  payload["ok"] = ok;
  if (reason && reason[0]) payload["reason"] = reason;
  reply.payloadLen = serializeJson(payload, reply.payload, sizeof(reply.payload));

  if (!lora.sendFrame(reply)) {
    LOGW("Falha ao enviar %s para cmd=%u seq=%lu",
         ok ? "ACK" : "NACK", (unsigned)cmd.msgType, cmd.seq);
  }
}

static void applyDownlink(const LoRaFrame& frame) {
  const bool targetMatch = (frame.deviceId == cfg::DEVICE_ID) || (frame.deviceId == 0);
  if (!targetMatch) return;

  if (frame.msgType == MsgType::PING) {
    sendCommandFeedback(frame, true, "pong");
    return;
  }

  if (frame.msgType != MsgType::SET_FENCE &&
      frame.msgType != MsgType::SET_HERDING_PLAN &&
      frame.msgType != MsgType::SET_PARAMS) {
    return;
  }

  StaticJsonDocument<512> doc;
  if (deserializeJson(doc, frame.payload, frame.payloadLen) != DeserializationError::Ok) {
    sendCommandFeedback(frame, false, "invalid_json");
    return;
  }

  if (frame.msgType == MsgType::SET_FENCE) {
    const char* err = nullptr;
    const bool chunked = doc["chunked"].is<bool>() && doc["chunked"].as<bool>();
    if (chunked) {
      if (!applyFenceChunkJson(doc.as<JsonObject>(), &err)) {
        sendCommandFeedback(frame, false, err ? err : "invalid_fence_chunk");
        return;
      }
      sendCommandFeedback(frame, true);
    } else {
      resetFenceChunkRx();
      Polygon p;
      if (!parsePolygonJson(doc["points"].as<JsonArray>(), &p, &err)) {
        sendCommandFeedback(frame, false, err ? err : "invalid_fence");
        return;
      }
      geofence.setFence(p);
      persistFence(p);
      LOGI("SET_FENCE aplicado com %u pontos", p.count);
      sendCommandFeedback(frame, true);
    }
  } else if (frame.msgType == MsgType::SET_HERDING_PLAN) {
    const char* err = nullptr;
    const bool chunked = doc["chunked"].is<bool>() && doc["chunked"].as<bool>();
    if (chunked) {
      if (!applyHerdChunkJson(doc.as<JsonObject>(), &err)) {
        sendCommandFeedback(frame, false, err ? err : "invalid_herd_chunk");
        return;
      }
      sendCommandFeedback(frame, true);
    } else {
      resetHerdChunkRx();
      HerdingPlan plan;
      if (!parseHerdingPlanJson(doc["phases"].as<JsonArray>(), &plan, &err)) {
        sendCommandFeedback(frame, false, err ? err : "invalid_herd_plan");
        return;
      }
      herding.setPlan(plan);
      persistHerdingPlan(plan);
      stateMachine.setMode(CollarMode::CONDUCAO);
      logEvent(EventType::HERD_START, plan.phaseCount, 0);
      LOGI("SET_HERDING_PLAN aplicado: fases=%u", plan.phaseCount);
      sendCommandFeedback(frame, true);
    }
  } else if (frame.msgType == MsgType::SET_PARAMS) {
    if (doc["wifi_ota_enabled"].is<bool>()) {
      const bool enableWifi = doc["wifi_ota_enabled"].as<bool>();
      if (!enableWifi && !hasAdminModePermission(doc.as<JsonVariantConst>())) {
        LOGW("SET_PARAMS rejeitado: admin requerido para LoRa-only");
        sendCommandFeedback(frame, false, "admin_required_for_lora_only");
        return;
      }
      applyWifiOtaMode(enableWifi, "LoRa");
      sendCommandFeedback(frame, true);
    } else {
      LOGW("SET_PARAMS sem campo wifi_ota_enabled");
      sendCommandFeedback(frame, false, "missing_wifi_ota_enabled");
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
  Serial.begin(cfg::SERIAL_BAUD);
  LOGI("Boot reset_reason=%d", (int)esp_reset_reason());
#if defined(ESP_IDF_VERSION_MAJOR) && ESP_IDF_VERSION_MAJOR >= 5
  esp_task_wdt_config_t wdtConfig = {};
  wdtConfig.timeout_ms = (uint32_t)cfg::TASK_WDT_TIMEOUT_SEC * 1000U;
  wdtConfig.idle_core_mask = 0;
  wdtConfig.trigger_panic = true;
  esp_task_wdt_init(&wdtConfig);
#else
  esp_task_wdt_init(cfg::TASK_WDT_TIMEOUT_SEC, true);
#endif
  loadPersistedConfig();

  if (cfg::SMART_GPS_TEST_MODE) {
    smartGps.begin();
    runSmartGpsSelfTest();
    return;
  }

  WiFi.onEvent(onWifiEvent);

  setupWifiOtaMaintenance();
  setupStatusServer();
  bool bleInitOk = !cfg::BLE_PRESENCE_ENABLED;
  if (cfg::BLE_PRESENCE_ENABLED) {
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

  sensors.begin();
  safety.begin();
  const bool storageOk = storage.begin();
  if (!storageOk) LOGW("StorageQueue indisponivel");
  smartGps.begin();
  refreshBlePositionForOnboarding();
  const bool loraOk = lora.begin();
  if (!loraOk) LOGE("LoRa indisponivel");
  setWatchdogEnabled(wifiOtaEnabled);
  printBootChecklist(bleInitOk, storageOk, loraOk);

  LOGI("Coleira inicializada: id=%lu fw=%s", cfg::DEVICE_ID, cfg::FW_VERSION);
}

void loop() {
  if (cfg::SMART_GPS_TEST_MODE) {
    delay(2000);
    return;
  }

  ensureWifiOtaMaintenance();
  if (wifiOtaEnabled && WiFi.getMode() != WIFI_OFF) {
    statusServer.handleClient();
  }

  const bool apClientConnected = otaApClientConnected();
  if (wifiOtaEnabled && otaModeActive) {
    ArduinoOTA.handle();
    if (watchdogTaskRegistered) {
      esp_task_wdt_reset();
    }
    if (otaUploadInProgress) {
      delay(2);
      return;
    }
  }
  const bool otaSessionLikelyActive = otaUploadInProgress || apClientConnected;

  if (watchdogTaskRegistered) esp_task_wdt_reset();
  if (cfg::BLE_PRESENCE_ENABLED) {
    const bool bleEnabled = shouldBlePresenceBeEnabled();
    blePresence.setEnabled(bleEnabled);
    blePresence.setFlags(wifiOtaEnabled, WiFi.status() == WL_CONNECTED);
    if (bleEnabled) blePresence.loop();
    if (bleEnabled && blePresence.clientConnected()) {
      // Durante leitura BLE no onboarding, evita janela longa de LoRa/JSON que
      // pode causar timeout no readCharacteristic do app iOS.
      if (watchdogTaskRegistered) esp_task_wdt_reset();
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
    blePresence.setPosition(t.gps.lat, t.gps.lon, t.gps.valid);
  }

  if (smartFix.flags.invalidFixRejected) {
    logEvent(EventType::GPS_INVALID_FIX, (int32_t)lround(rawTelemetry.gps.hdop * 100.0f), rawTelemetry.gps.sats);
  }
  if (smartFix.flags.outlierDropped) {
    logEvent(EventType::GPS_OUTLIER, (int32_t)lround(smartFix.flags.outlierSpeedMps * 100.0f), 0);
  }
  if (smartFix.flags.lockStateChanged) {
    logEvent(t.gps.locked ? EventType::GPS_LOCKED : EventType::GPS_UNLOCKED);
  }
  if (!t.gps.valid) logEvent(EventType::GPS_FAIL);

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
    logEvent(herdEvent.type, herdEvent.d1, herdEvent.d2);
    persistHerdingPlan(herding.plan());
    if (!herding.active() && stateMachine.mode() == CollarMode::CONDUCAO) {
      stateMachine.setMode(CollarMode::NORMAL);
    }
  }

  LoRaFrame uplink;
  uplink.deviceId = cfg::DEVICE_ID;
  uplink.msgType = MsgType::TELEMETRY;
  uplink.seq = nextLoRaSeq();
  uplink.timestamp = t.gps.gpsTime ? t.gps.gpsTime : now / 1000;
  randomNonce(uplink.nonce);
  uplink.payloadLen = buildTelemetryPayload(t, uplink.payload, sizeof(uplink.payload));

  if (!lora.sendFrame(uplink)) {
    LOGW("Falha envio telemetria; permanece em fila local.");
  }

  LoRaFrame down;
  const uint32_t rxWindowMs = otaSessionLikelyActive
                                  ? cfg::OTA_UPLOAD_RX_WINDOW_MS
                                  : cfg::RX_WINDOW_MS;
  if (lora.receiveFrame(down, rxWindowMs)) applyDownlink(down);

  EventRecord pending;
  uint8_t eventBudget = otaSessionLikelyActive ? cfg::OTA_UPLOAD_EVENT_BURST : 0xFF;
  while (storage.popEvent(pending)) {
    LoRaFrame ev;
    ev.deviceId = cfg::DEVICE_ID;
    ev.msgType = MsgType::EVENT;
    ev.seq = nextLoRaSeq();
    ev.timestamp = pending.ts;
    randomNonce(ev.nonce);
    StaticJsonDocument<128> d;
    d["type"] = (int)pending.type;
    d["d1"] = pending.d1;
    d["d2"] = pending.d2;
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
