/** @file ApiServer.cpp */
#include "ApiServer.h"
#include "config.h"
#include <ctype.h>
#include <WiFi.h>

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

void ApiServer::begin() {
  g_server = this;
  http_.on("/status", HTTP_GET, [this]() {
    StaticJsonDocument<256> doc;
    doc["ok"] = true;
    doc["service"] = "gateway_matrix";
    doc["fw"] = cfg::FW_VERSION;
    const String apSsid = WiFi.softAPSSID();
    doc["ap_ssid"] = apSsid.isEmpty() ? String(cfg::AP_SSID) : apSsid;
    doc["ap_ip"] = WiFi.softAPIP().toString();
    doc["gatewayId"] = compactIdentifier(WiFi.softAPmacAddress());
    doc["ota"] = cfg::OTA_ENABLED;
    doc["wifi_ota_enabled"] = WiFi.getMode() != WIFI_OFF;
    doc["role"] = "matrix";
    String out;
    serializeJson(doc, out);
    http_.send(200, "application/json", out);
  });
  http_.on("/devices", HTTP_GET, [this]() { http_.send(200, "application/json", "[]"); });
  http_.on("/logs", HTTP_GET, [this]() { http_.send(200, "text/plain", "Consulte SD local"); });
  http_.begin();

  ws_.begin();
  ws_.onEvent([](uint8_t num, WStype_t type, uint8_t* payload, size_t len) {
    if (g_server) g_server->onWsEvent(num, type, payload, len);
  });
}

void ApiServer::onWsEvent(uint8_t num, WStype_t type, uint8_t* payload, size_t length) {
  if (type == WStype_CONNECTED) {
    ws_.sendTXT(num, "{\"type\":\"hello\",\"status\":\"connected\"}");
  } else if (type == WStype_TEXT) {
    queue_[head_] = String((char*)payload).substring(0, length);
    head_ = (head_ + 1) % 8;
  }
}

void ApiServer::loop() {
  http_.handleClient();
  ws_.loop();
}

void ApiServer::broadcastTelemetry(const String& json) {
  String payload = json;
  ws_.broadcastTXT(payload);
}

bool ApiServer::hasPendingCommand() const { return head_ != tail_; }

bool ApiServer::popCommand(StaticJsonDocument<512>& out) {
  if (!hasPendingCommand()) return false;
  String s = queue_[tail_];
  tail_ = (tail_ + 1) % 8;
  return deserializeJson(out, s) == DeserializationError::Ok;
}
