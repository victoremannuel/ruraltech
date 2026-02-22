/**
 * @file coleira.ino
 * @brief Firmware principal da coleira RuralTech (ESP32 + GPS + LoRa + sensores).
 * @version 1.0.0
 * @date 2026-02-18
 *
 * Risco e segurança: pulso elétrico só ocorre após escalonamento e com hard-limits locais,
 * mesmo sem gateway. Em perda de GPS, sistema degrada para modo seguro sem pulso.
 */
#include <Arduino.h>
#include <ArduinoJson.h>
#include <WiFi.h>
#include <ArduinoOTA.h>
#include <ESPmDNS.h>
#include <Preferences.h>
#include <math.h>
#include <esp_task_wdt.h>
#include <esp_sleep.h>
#if __has_include(<esp_idf_version.h>)
#include <esp_idf_version.h>
#endif
#include "config.h"
#include "Logger.h"
#include "SensorsManager.h"
#include "Geofence.h"
#include "SafetyController.h"
#include "StorageQueue.h"
#include "LoRaManager.h"
#include "BlePresence.h"
#include "HerdingController.h"
#include "StateMachine.h"

SensorsManager sensors;
Geofence geofence;
SafetyController safety;
StorageQueue storage;
LoRaManager lora;
BlePresence blePresence;
HerdingController herding;
StateMachine stateMachine;

uint32_t seq = 1;
uint32_t lastCycle = 0;
uint32_t violationStart = 0;
bool wasInside = true;
bool otaModeActive = false;
bool wifiOtaEnabled = cfg::OTA_ENABLED;
bool watchdogTaskRegistered = false;
bool otaUploadInProgress = false;
Preferences prefs_;
bool prefsReady_ = false;
static void logEvent(EventType type, int32_t d1, int32_t d2);

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

static String collarNodeId() { return String((uint32_t)cfg::DEVICE_ID); }

static String collarAdvName() {
  return String(cfg::BLE_DEVICE_PREFIX) + "-" + collarNodeId();
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
  if (!beginPrefs()) return cfg::OTA_ENABLED;
  return prefs_.getBool(cfg::PREF_KEY_WIFI_OTA, cfg::OTA_ENABLED);
}

static void loadPersistedConfig() {
  wifiOtaEnabled = loadPersistedWifiOtaEnabled();

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
  if (WiFi.getMode() == WIFI_STA || WiFi.getMode() == WIFI_AP_STA) {
    WiFi.disconnect(true, true);
  }
  if (WiFi.getMode() == WIFI_AP || WiFi.getMode() == WIFI_AP_STA) {
    WiFi.softAPdisconnect(true);
  }
  WiFi.mode(WIFI_OFF);
  LOGI("OTA/WiFi desativado: modo LoRa-only");
}

static void startOtaService() {
  ArduinoOTA.setHostname(cfg::OTA_HOSTNAME);
  ArduinoOTA.setPort(3232);
  ArduinoOTA.setTimeout(20000);
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
    LOGE("OTA erro=%u", (unsigned int)error);
  });
  ArduinoOTA.begin();

  if (MDNS.begin(cfg::OTA_HOSTNAME)) {
    MDNS.addService("arduino", "tcp", 3232);
    LOGI("mDNS ativo: %s.local:3232", cfg::OTA_HOSTNAME);
  } else {
    LOGW("mDNS indisponivel; OTA pode nao aparecer automaticamente no IDE.");
  }

  otaModeActive = true;
}

static void setupWifiOtaMaintenance() {
  if (!wifiOtaEnabled || !cfg::OTA_ENABLED) return;

  if (cfg::OTA_FORCE_AP_ONLY) {
    WiFi.mode(WIFI_AP);
    WiFi.setSleep(false);
    const bool apOk = WiFi.softAP(cfg::OTA_AP_SSID, cfg::OTA_AP_PASS);
    if (!apOk) {
      WiFi.mode(WIFI_OFF);
      LOGE("OTA: falha ao subir AP forcado.");
      return;
    }
    startOtaService();
    LOGI("OTA pronto (AP FORCADO) SSID=%s IP=%s host=%s", cfg::OTA_AP_SSID, WiFi.softAPIP().toString().c_str(), cfg::OTA_HOSTNAME);
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
  const bool apOk = WiFi.softAP(cfg::OTA_AP_SSID, cfg::OTA_AP_PASS);
  if (!apOk) {
    WiFi.mode(WIFI_OFF);
    LOGE("OTA: falha ao subir AP fallback.");
    return;
  }

  startOtaService();
  LOGI("OTA pronto (AP) SSID=%s IP=%s host=%s", cfg::OTA_AP_SSID, WiFi.softAPIP().toString().c_str(), cfg::OTA_HOSTNAME);
}

static void applyWifiOtaMode(bool enabled, const char* source) {
  if (wifiOtaEnabled == enabled) {
    LOGI("SET_PARAMS: wifi_ota_enabled ja estava em %d (%s)", enabled ? 1 : 0, source);
    persistWifiOtaEnabled(enabled);
    return;
  }

  wifiOtaEnabled = enabled;
  persistWifiOtaEnabled(enabled);
  setWatchdogEnabled(enabled);

  if (enabled) {
    setupWifiOtaMaintenance();
    if (cfg::BLE_PRESENCE_ENABLED) {
      blePresence.setEnabled(true);
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
  return serializeJson(doc, out, max);
}

static void sendCommandFeedback(const LoRaFrame& cmd, bool ok, const char* reason = nullptr) {
  LoRaFrame reply;
  reply.deviceId = cfg::DEVICE_ID;
  reply.msgType = ok ? MsgType::ACK : MsgType::NACK;
  reply.seq = seq++;
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
      applyWifiOtaMode(doc["wifi_ota_enabled"].as<bool>(), "LoRa");
      sendCommandFeedback(frame, true);
    } else {
      LOGW("SET_PARAMS sem campo wifi_ota_enabled");
      sendCommandFeedback(frame, false, "missing_wifi_ota_enabled");
    }
  }
}

void setup() {
  Serial.begin(cfg::SERIAL_BAUD);
#if defined(ESP_IDF_VERSION_MAJOR) && ESP_IDF_VERSION_MAJOR >= 5
  esp_task_wdt_config_t wdtConfig = {};
  wdtConfig.timeout_ms = 12000;
  wdtConfig.idle_core_mask = 0;
  wdtConfig.trigger_panic = true;
  esp_task_wdt_init(&wdtConfig);
#else
  esp_task_wdt_init(12, true);
#endif
  loadPersistedConfig();
  setWatchdogEnabled(wifiOtaEnabled);

  setupWifiOtaMaintenance();
  if (cfg::BLE_PRESENCE_ENABLED) {
    const String nodeId = collarNodeId();
    blePresence.begin(
        BleNodeKind::COLLAR,
        nodeId,
        collarAdvName(),
        cfg::BLE_COMPANY_ID,
        cfg::BLE_SERVICE_UUID);
    blePresence.setEnabled(wifiOtaEnabled);
    blePresence.setFlags(wifiOtaEnabled, WiFi.status() == WL_CONNECTED);
  }

  sensors.begin();
  safety.begin();
  storage.begin();
  lora.begin();

  LOGI("Coleira inicializada: id=%lu fw=%s", cfg::DEVICE_ID, cfg::FW_VERSION);
}

void loop() {
  if (wifiOtaEnabled && !otaModeActive) setupWifiOtaMaintenance();

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

  if (watchdogTaskRegistered) esp_task_wdt_reset();
  if (cfg::BLE_PRESENCE_ENABLED) {
    blePresence.setEnabled(wifiOtaEnabled);
    blePresence.setFlags(wifiOtaEnabled, WiFi.status() == WL_CONNECTED);
    blePresence.loop();
  }
  sensors.tick();

  const uint32_t now = millis();
  if (now - lastCycle < stateMachine.intervalMs()) {
    delay(20);
    return;
  }
  lastCycle = now;

  const Telemetry t = sensors.readTelemetry(stateMachine.mode(), now / 1000, lora.lastRssi(), lora.lastSnr());
  if (cfg::BLE_PRESENCE_ENABLED) {
    blePresence.setPosition(t.gps.lat, t.gps.lon, t.gps.valid);
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
  uplink.seq = seq++;
  uplink.timestamp = t.gps.gpsTime ? t.gps.gpsTime : now / 1000;
  randomNonce(uplink.nonce);
  uplink.payloadLen = buildTelemetryPayload(t, uplink.payload, sizeof(uplink.payload));

  if (!lora.sendFrame(uplink)) {
    LOGW("Falha envio telemetria; permanece em fila local.");
  }

  LoRaFrame down;
  if (lora.receiveFrame(down, cfg::RX_WINDOW_MS)) applyDownlink(down);

  EventRecord pending;
  while (storage.popEvent(pending)) {
    LoRaFrame ev;
    ev.deviceId = cfg::DEVICE_ID;
    ev.msgType = MsgType::EVENT;
    ev.seq = seq++;
    ev.timestamp = pending.ts;
    randomNonce(ev.nonce);
    StaticJsonDocument<128> d;
    d["type"] = (int)pending.type;
    d["d1"] = pending.d1;
    d["d2"] = pending.d2;
    ev.payloadLen = serializeJson(d, ev.payload, sizeof(ev.payload));
    if (!lora.sendFrame(ev)) break;
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
