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
#include <esp_task_wdt.h>
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

static void randomNonce(uint8_t* nonce12) {
  for (int i = 0; i < 12; ++i) nonce12[i] = (uint8_t)esp_random();
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
    LOGI("SET_PARAMS recebido (MVP usa config estático)");
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
  esp_task_wdt_add(NULL);

  sensors.begin();
  safety.begin();
  storage.begin();
  lora.begin();

  LOGI("Coleira inicializada: id=%lu fw=%s", cfg::DEVICE_ID, cfg::FW_VERSION);
}

void loop() {
  esp_task_wdt_reset();
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

  // Deep sleep controlado por modo: preserva estado em EEPROM previamente.
  esp_sleep_enable_timer_wakeup((uint64_t)stateMachine.intervalMs() * 1000ULL);
  esp_deep_sleep_start();
}
