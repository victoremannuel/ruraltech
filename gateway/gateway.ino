/**
 * @file gateway.ino
 * @brief Firmware gateway RuralTech: LoRa seguro + REST/WS + SD log + OLED.
 * @version 1.0.0
 * @date 2026-02-18
 */
#include <Arduino.h>
#include <WiFi.h>
#include <ArduinoOTA.h>
#include <Wire.h>
#include <SPI.h>
#include <ArduinoJson.h>
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

static void setupWiFi() {
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAP(cfg::AP_SSID, cfg::AP_PASS);
  LOGI("AP ativo: %s", cfg::AP_SSID);
}

static void setupOta() {
  if (!cfg::OTA_ENABLED) return;
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
  Wire.begin(cfg::PIN_I2C_SDA, cfg::PIN_I2C_SCL);
  display.begin(SSD1306_SWITCHCAPVCC, 0x3C);
  drawStatus("Boot", cfg::FW_VERSION);

  setupWiFi();
  setupOta(); //comando para ligar o OTA (wifi do gateway)
  api.begin();
  rtc.begin();
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");

  if (!sdlog.begin(cfg::PIN_SD_CS)) LOGW("SD indisponível");
  if (!lora.begin()) LOGE("LoRa indisponível");

  LOGI("Gateway pronto fw=%s", cfg::FW_VERSION);
}

void loop() {
  if (cfg::OTA_ENABLED) ArduinoOTA.handle();
  api.loop();

  LoRaFrame rx;
  if (lora.receive(rx)) {
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
      LoRaFrame tx;
      tx.deviceId = cmd["device_id"] | 0;
      const String command = cmd["command"] | "PING";
      tx.msgType = command == "SET_FENCE" ? MsgType::SET_FENCE :
                   command == "SET_HERDING_PLAN" ? MsgType::SET_HERDING_PLAN :
                   command == "SET_PARAMS" ? MsgType::SET_PARAMS : MsgType::PING;
      tx.seq = seqDown++;
      tx.timestamp = millis() / 1000;
      for (int i = 0; i < 12; ++i) tx.nonce[i] = (uint8_t)esp_random();
      tx.payloadLen = serializeJson(cmd["payload"], tx.payload, sizeof(tx.payload));
      bool ok = lora.send(tx);
      StaticJsonDocument<256> res;
      res["type"] = "command_result";
      res["ok"] = ok;
      res["device_id"] = tx.deviceId;
      res["command"] = command;
      String out;
      serializeJson(res, out);
      api.broadcastTelemetry(out);
      sdlog.log(String("DL|") + out);
    }
  }

  delay(5);
}
