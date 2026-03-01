/**
 * @file gateway.ino
 * @brief Firmware gateway RuralTech: LoRa seguro + REST/WS + SD log + OLED.
 * @version 1.0.0
 * @date 2026-02-18
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
#include <Wire.h>
#include <SPI.h>
#include <ArduinoJson.h>
#include <esp_task_wdt.h>
#include <esp_system.h>
#include <esp_ota_ops.h>
#if __has_include(<esp_idf_version.h>)
#include <esp_idf_version.h>
#endif
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <RTClib.h>
#include <Preferences.h>
#include "config.h"
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
Adafruit_SSD1306 display(128, 64, &Wire, -1);
uint32_t seqDown = 1;
Preferences seqPrefs;
bool seqPrefsReady = false;
bool wifiOtaEnabled = cfg::WIFI_OTA_DEFAULT_ENABLED;
bool watchdogTaskRegistered = false;
bool otaUploadInProgress = false;
bool wifiApRunning = false;
uint32_t wifiRecoveryAttemptAtMs = 0;
uint8_t wifiRecoveryAttemptCount = 0;
static void setWatchdogEnabled(bool enabled);
static void printBootChecklist(
    bool displayOk,
    bool wifiOk,
    bool bleInitOk,
    bool rtcOk,
    bool sdOk,
    bool loraOk);

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

static bool setupWiFi() {
  WiFi.mode(WIFI_AP_STA);
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
  if (!wifiOtaEnabled || !cfg::OTA_ENABLED) return;
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
  if (WiFi.getMode() == WIFI_STA || WiFi.getMode() == WIFI_AP_STA) {
    WiFi.disconnect(true, true);
  }
  if (WiFi.getMode() == WIFI_AP || WiFi.getMode() == WIFI_AP_STA) {
    WiFi.softAPdisconnect(true);
  }
  WiFi.mode(WIFI_OFF);
  LOGI("Gateway em modo LoRa-only");
}

static void onWifiEvent(WiFiEvent_t event) {
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
}

static bool wifiApClientConnected() {
  if (!wifiOtaEnabled || !wifiApRunning) return false;
  const wifi_mode_t mode = WiFi.getMode();
  if (mode != WIFI_AP && mode != WIFI_AP_STA) return false;
  return WiFi.softAPgetStationNum() > 0;
}

static bool shouldBlePresenceBeEnabled() {
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
    esp_task_wdt_add(NULL);
    watchdogTaskRegistered = true;
  } else if (!enabled && watchdogTaskRegistered) {
    esp_task_wdt_delete(NULL);
    watchdogTaskRegistered = false;
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
         frame.msgType == MsgType::NACK;
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

static void relayFrameToPeerGateways(const LoRaFrame& rx) {
  if (!cfg::GATEWAY_RELAY_ENABLED) return;
  if (!isRelayCandidate(rx)) return;

  LoRaFrame relay = rx;
  for (int i = 0; i < 12; ++i) relay.nonce[i] = (uint8_t)esp_random();
  if (!lora.send(relay)) {
    LOGW("Falha relay device=%lu seq=%lu", relay.deviceId, relay.seq);
  }
}

static void drawStatus(const char* line1, const char* line2) {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(WHITE);
  display.setCursor(0, 0);
  display.println("RuralTech Gateway");
  display.println(line1);
  display.println(line2);
  display.display();
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
    bool loraOk) {
  Serial.println("==== HW CHECKLIST | GATEWAY ====");
  checklistLine(
      "NVS_SEQ_DOWN",
      seqPrefsReady,
      "Falha ao abrir NVS lora_down; revisar flash/NVS.");
  checklistLine(
      "OLED_0x3C",
      displayOk,
      "OLED nao inicializou; revisar SDA/SCL, VCC, GND e endereco 0x3C.");
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
  Serial.println("================================");
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
  WiFi.onEvent(onWifiEvent);
  restoreDownlinkSeq();

  Wire.begin(cfg::PIN_I2C_SDA, cfg::PIN_I2C_SCL);
  const bool displayOk = display.begin(SSD1306_SWITCHCAPVCC, 0x3C);
  if (!displayOk) LOGW("OLED indisponivel");
  drawStatus("Boot", cfg::FW_VERSION);

  bool wifiOk = true;
  if (wifiOtaEnabled) {
    wifiOk = setupWiFi();
    if (wifiOk) setupOta();
  }
  bool bleInitOk = !cfg::BLE_PRESENCE_ENABLED;
  if (cfg::BLE_PRESENCE_ENABLED) {
    const String nodeId = gatewayNodeId();
    bleInitOk = blePresence.begin(
        BleNodeKind::GATEWAY,
        nodeId,
        gatewayAdvName(nodeId),
        cfg::BLE_COMPANY_ID,
        cfg::BLE_SERVICE_UUID);
    blePresence.setEnabled(shouldBlePresenceBeEnabled());
    blePresence.setFlags(wifiOtaEnabled, WiFi.status() == WL_CONNECTED);
  }
  api.begin();
  const bool rtcOk = rtc.begin();
  if (!rtcOk) LOGW("RTC indisponivel");
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");

  const bool sdOk = sdlog.begin(cfg::PIN_SD_CS);
  if (!sdOk) LOGW("SD indisponivel");
  const bool loraOk = lora.begin();
  if (!loraOk) LOGE("LoRa indisponivel");
  setWatchdogEnabled(wifiOtaEnabled);
  printBootChecklist(displayOk, wifiOk, bleInitOk, rtcOk, sdOk, loraOk);

  LOGI("Gateway pronto fw=%s", cfg::FW_VERSION);
}

void loop() {
  ensureWifiOtaServices();
  const bool apClientConnected = wifiApClientConnected();
  if (wifiOtaEnabled && cfg::OTA_ENABLED) {
    ArduinoOTA.handle();
    if (watchdogTaskRegistered) esp_task_wdt_reset();
    if (otaUploadInProgress || apClientConnected) {
      delay(2);
      return;
    }
  }
  if (cfg::BLE_PRESENCE_ENABLED) {
    const bool bleEnabled = shouldBlePresenceBeEnabled();
    blePresence.setEnabled(bleEnabled);
    blePresence.setFlags(wifiOtaEnabled, WiFi.status() == WL_CONNECTED);
    if (bleEnabled) blePresence.loop();
  }
  if (watchdogTaskRegistered) esp_task_wdt_reset();
  if (wifiOtaEnabled && WiFi.getMode() != WIFI_OFF) api.loop();

  LoRaFrame rx;
  if (lora.receive(rx)) {
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

    relayFrameToPeerGateways(rx);

    StaticJsonDocument<512> packet;
    packet["type"] = uplinkTypeLabel(rx.msgType);
    packet["device_id"] = rx.deviceId;
    packet["msg_type"] = (int)rx.msgType;
    packet["seq"] = rx.seq;
    packet["timestamp"] = rx.timestamp;
    packet["gateway_id"] = gatewayNodeId();
    packet["gateway_role"] = "gateway";
    packet["gateway_wifi_ota_enabled"] = wifiOtaEnabled;
    packet["payload"] = String((char*)rx.payload).substring(0, rx.payloadLen);
    String out;
    serializeJson(packet, out);
    api.broadcastTelemetry(out);
    sdlog.log(String("UL|") + out);
    drawStatus("RX LoRa", out.substring(0, 16).c_str());
  }

  if (api.hasPendingCommand()) {
    StaticJsonDocument<512> cmd;
    if (api.popCommand(cmd)) {
      const String command = cmd["command"] | "PING";
      const JsonVariantConst payload = cmd["payload"].as<JsonVariantConst>();

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
      sdlog.log(String("DL|") + out);

      if (localToggleRequested) {
        applyWifiOtaMode(localWifiEnabled, "WiFi");
      }
    }
  }

  delay(5);
}
