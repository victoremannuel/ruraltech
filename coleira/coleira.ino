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
#include "HerdingController.h"
#include "StateMachine.h"

SensorsManager sensors;
Geofence geofence;
SafetyController safety;
StorageQueue storage;
LoRaManager lora;
HerdingController herding;
StateMachine stateMachine;

uint32_t seq = 1;
uint32_t lastCycle = 0;
uint32_t violationStart = 0;
bool wasInside = true;
bool otaModeActive = false;
bool wifiOtaEnabled = cfg::OTA_ENABLED;
bool watchdogTaskRegistered = false;

static void randomNonce(uint8_t* nonce12) {
  for (int i = 0; i < 12; ++i) nonce12[i] = (uint8_t)esp_random();
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
  ArduinoOTA.setPassword(cfg::OTA_PASSWORD);
  ArduinoOTA.onStart([]() { LOGI("OTA iniciado"); });
  ArduinoOTA.onEnd([]() { LOGI("OTA concluido"); });
  ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
    LOGI("OTA progresso: %u%%", (progress * 100U) / total);
  });
  ArduinoOTA.onError([](ota_error_t error) {
    LOGE("OTA erro=%u", (unsigned int)error);
  });
  ArduinoOTA.begin();
  otaModeActive = true;
}

static void setupWifiOtaMaintenance() {
  if (!wifiOtaEnabled || !cfg::OTA_ENABLED) return;

  if (cfg::OTA_FORCE_AP_ONLY) {
    WiFi.mode(WIFI_AP);
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
    return;
  }

  wifiOtaEnabled = enabled;
  setWatchdogEnabled(enabled);

  if (enabled) {
    setupWifiOtaMaintenance();
    LOGI("SET_PARAMS: wifi_ota_enabled=1 aplicado via %s", source);
  } else {
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

static void applyDownlink(const LoRaFrame& frame) {
  const bool targetMatch = (frame.deviceId == cfg::DEVICE_ID) || (frame.deviceId == 0);
  if (!targetMatch) return;

  StaticJsonDocument<512> doc;
  if (deserializeJson(doc, frame.payload, frame.payloadLen) != DeserializationError::Ok) return;

  if (frame.msgType == MsgType::SET_FENCE) {
    Polygon p;
    JsonArray pts = doc["points"].as<JsonArray>();
    p.count = min((int)pts.size(), (int)cfg::MAX_POLYGON_POINTS);
    for (uint8_t i = 0; i < p.count; ++i) {
      p.points[i].lat = pts[i][0];
      p.points[i].lon = pts[i][1];
    }
    geofence.setFence(p);
    LOGI("SET_FENCE aplicado com %u pontos", p.count);
  } else if (frame.msgType == MsgType::SET_PARAMS) {
    if (doc["wifi_ota_enabled"].is<bool>()) {
      applyWifiOtaMode(doc["wifi_ota_enabled"].as<bool>(), "LoRa");
    } else {
      LOGW("SET_PARAMS sem campo wifi_ota_enabled");
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
  setWatchdogEnabled(wifiOtaEnabled);

  setupWifiOtaMaintenance();

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
  }

  if (watchdogTaskRegistered) esp_task_wdt_reset();
  sensors.tick();

  const uint32_t now = millis();
  if (now - lastCycle < stateMachine.intervalMs()) {
    delay(20);
    return;
  }
  lastCycle = now;

  const Telemetry t = sensors.readTelemetry(stateMachine.mode(), now / 1000, lora.lastRssi(), lora.lastSnr());
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
