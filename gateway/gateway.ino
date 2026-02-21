/**
 * @file gateway.ino
 * @brief Firmware gateway RuralTech: LoRa seguro + REST/WS + SD log + OLED.
 * @version 1.0.0
 * @date 2026-02-18
 */
#include <Arduino.h>
#include <cstring>
#include <WiFi.h>
#include <ArduinoOTA.h>
#include <Wire.h>
#include <SPI.h>
#include <ArduinoJson.h>
#include <esp_task_wdt.h>
#if __has_include(<esp_idf_version.h>)
#include <esp_idf_version.h>
#endif
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <RTClib.h>
#include "config.h"
#include "Logger.h"
#include "LoRaGateway.h"
#include "SdLogger.h"
#include "ApiServer.h"

LoRaGateway lora;
SdLogger sdlog;
ApiServer api;
RTC_DS3231 rtc;
Adafruit_SSD1306 display(128, 64, &Wire, -1);
uint32_t seqDown = 1;
bool wifiOtaEnabled = cfg::OTA_ENABLED;
bool watchdogTaskRegistered = false;

static void setupWiFi() {
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAP(cfg::AP_SSID, cfg::AP_PASS);
  LOGI("AP ativo: %s", cfg::AP_SSID);
}

static void setupOta() {
  if (!wifiOtaEnabled || !cfg::OTA_ENABLED) return;
  ArduinoOTA.setHostname(cfg::OTA_HOSTNAME);
  ArduinoOTA.setPassword(cfg::OTA_PASSWORD);
  ArduinoOTA.onStart([]() { LOGI("OTA iniciado"); });
  ArduinoOTA.onEnd([]() { LOGI("OTA concluído"); });
  ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
    LOGI("OTA progresso: %u%%", (progress * 100U) / total);
  });
  ArduinoOTA.onError([](ota_error_t error) {
    LOGE("OTA erro=%u", (unsigned int)error);
  });
  ArduinoOTA.begin();
  LOGI("OTA ativo hostname=%s", cfg::OTA_HOSTNAME);
}

static void stopWifiAndOta() {
  if (WiFi.getMode() == WIFI_STA || WiFi.getMode() == WIFI_AP_STA) {
    WiFi.disconnect(true, true);
  }
  if (WiFi.getMode() == WIFI_AP || WiFi.getMode() == WIFI_AP_STA) {
    WiFi.softAPdisconnect(true);
  }
  WiFi.mode(WIFI_OFF);
  LOGI("Gateway em modo LoRa-only");
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

static bool targetIncludesGateway(const JsonVariantConst payload) {
  if (!payload.is<JsonObjectConst>()) return true;
  const char* target = payload["target"] | "all";
  return strcmp(target, "all") == 0 || strcmp(target, "gateway") == 0;
}

static bool targetIncludesCollars(const JsonVariantConst payload) {
  if (!payload.is<JsonObjectConst>()) return true;
  const char* target = payload["target"] | "all";
  return strcmp(target, "all") == 0 || strcmp(target, "collars") == 0 || strcmp(target, "collar") == 0;
}

static void applyWifiOtaMode(bool enabled, const char* source) {
  if (wifiOtaEnabled == enabled) {
    LOGI("SET_PARAMS: wifi_ota_enabled ja estava em %d (%s)", enabled ? 1 : 0, source);
    return;
  }

  wifiOtaEnabled = enabled;
  setWatchdogEnabled(enabled);

  if (enabled) {
    setupWiFi();
    setupOta();
    LOGI("SET_PARAMS: wifi_ota_enabled=1 aplicado via %s", source);
  } else {
    stopWifiAndOta();
    LOGI("SET_PARAMS: wifi_ota_enabled=0 aplicado via %s", source);
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

  Wire.begin(cfg::PIN_I2C_SDA, cfg::PIN_I2C_SCL);
  display.begin(SSD1306_SWITCHCAPVCC, 0x3C);
  drawStatus("Boot", cfg::FW_VERSION);

  if (wifiOtaEnabled) {
    setupWiFi();
    setupOta();
  }
  api.begin();
  rtc.begin();
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");

  if (!sdlog.begin(cfg::PIN_SD_CS)) LOGW("SD indisponível");
  if (!lora.begin()) LOGE("LoRa indisponível");

  LOGI("Gateway pronto fw=%s", cfg::FW_VERSION);
}

void loop() {
  if (wifiOtaEnabled && cfg::OTA_ENABLED) {
    ArduinoOTA.handle();
    api.loop();
  }
  if (watchdogTaskRegistered) esp_task_wdt_reset();

  LoRaFrame rx;
  if (lora.receive(rx)) {
    if (rx.msgType == MsgType::SET_PARAMS) {
      StaticJsonDocument<256> params;
      if (deserializeJson(params, rx.payload, rx.payloadLen) == DeserializationError::Ok) {
        bool wifiEnabled = false;
        if (parseWifiOtaParam(params.as<JsonVariantConst>(), wifiEnabled) && targetIncludesGateway(params.as<JsonVariantConst>())) {
          applyWifiOtaMode(wifiEnabled, "LoRa");
        }
      }
    }

    StaticJsonDocument<256> packet;
    packet["type"] = (rx.msgType == MsgType::TELEMETRY) ? "telemetry" : "event";
    packet["device_id"] = rx.deviceId;
    packet["seq"] = rx.seq;
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
      const JsonVariant payload = cmd["payload"];

      bool localToggleRequested = false;
      bool localWifiEnabled = wifiOtaEnabled;
      if (command == "SET_PARAMS" && parseWifiOtaParam(payload.as<JsonVariantConst>(), localWifiEnabled) &&
          targetIncludesGateway(payload.as<JsonVariantConst>())) {
        localToggleRequested = true;
      }

      LoRaFrame tx;
      tx.deviceId = cmd["device_id"] | 0;
      tx.msgType = command == "SET_FENCE" ? MsgType::SET_FENCE :
                   command == "SET_HERDING_PLAN" ? MsgType::SET_HERDING_PLAN :
                   command == "SET_PARAMS" ? MsgType::SET_PARAMS : MsgType::PING;
      tx.seq = seqDown++;
      tx.timestamp = millis() / 1000;
      for (int i = 0; i < 12; ++i) tx.nonce[i] = (uint8_t)esp_random();
      tx.payloadLen = serializeJson(payload, tx.payload, sizeof(tx.payload));
      const bool shouldRelayLoRa = !(command == "SET_PARAMS" && !targetIncludesCollars(payload.as<JsonVariantConst>()));
      bool ok = true;
      if (shouldRelayLoRa) ok = lora.send(tx);
      StaticJsonDocument<256> res;
      res["type"] = "command_result";
      res["ok"] = ok;
      res["device_id"] = tx.deviceId;
      res["command"] = command;
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
