/** @file ApiServer.cpp */
#include "ApiServer.h"
#include "config.h"
#include <ctype.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
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

static void copyToBuffer(char* dst, size_t dstSize, const char* src) {
  if (dstSize == 0) return;
  if (!src) {
    dst[0] = '\0';
    return;
  }
  strncpy(dst, src, dstSize - 1);
  dst[dstSize - 1] = '\0';
}

static bool parseDeviceId(const JsonVariantConst& value, uint32_t& out) {
  if (value.is<uint32_t>() || value.is<int>() || value.is<long>()) {
    const uint32_t parsed = value.as<uint32_t>();
    if (parsed == 0) return false;
    out = parsed;
    return true;
  }
  if (!value.is<const char*>()) return false;
  const char* text = value.as<const char*>();
  if (!text || !text[0]) return false;
  char* end = nullptr;
  const unsigned long parsed = strtoul(text, &end, 10);
  if (end == text || parsed == 0) return false;
  out = (uint32_t)parsed;
  return true;
}

static bool parseCoordinate(const JsonVariantConst& value, double& out) {
  if (value.is<double>() || value.is<float>() || value.is<int>() ||
      value.is<long>()) {
    out = value.as<double>();
  } else if (value.is<const char*>()) {
    const char* text = value.as<const char*>();
    if (!text || !text[0]) return false;
    char* end = nullptr;
    out = strtod(text, &end);
    if (end == text) return false;
  } else {
    return false;
  }
  return isfinite(out);
}

void ApiServer::begin() {
  g_server = this;
  http_.on("/status", HTTP_GET, [this]() {
    StaticJsonDocument<256> doc;
    doc["ok"] = true;
    doc["service"] = "gateway";
    doc["fw"] = cfg::FW_VERSION;
    const String apSsid = WiFi.softAPSSID();
    doc["ap_ssid"] = apSsid.isEmpty() ? String(cfg::AP_SSID) : apSsid;
    doc["ap_ip"] = WiFi.softAPIP().toString();
    doc["gatewayId"] = compactIdentifier(WiFi.softAPmacAddress());
    doc["ota"] = cfg::OTA_ENABLED;
    doc["wifi_ota_enabled"] = WiFi.getMode() != WIFI_OFF;
    String out;
    serializeJson(doc, out);
    http_.send(200, "application/json", out);
  });
  http_.on("/devices", HTTP_GET, [this]() { handleDevicesRequest(); });
  http_.on("/logs", HTTP_GET, [this]() { handleLogsRequest(); });
  http_.begin();

  appendLogLine("HTTP_READY");
  ws_.begin();
  ws_.onEvent([](uint8_t num, WStype_t type, uint8_t* payload, size_t len) {
    if (g_server) g_server->onWsEvent(num, type, payload, len);
  });
}

void ApiServer::appendLogLine(const String& line) {
  String entry = line;
  entry.replace('\r', ' ');
  entry.replace('\n', ' ');
  if (entry.length() > 220) {
    entry = entry.substring(0, 220);
  }
  const String stamped = String(millis()) + "|" + entry;
  logs_[logsHead_] = stamped;
  logsHead_ = (uint8_t)((logsHead_ + 1U) % kLogRingSize);
  if (logsCount_ < kLogRingSize) logsCount_++;
}

int ApiServer::findDeviceSlot(uint32_t deviceId) const {
  for (int i = 0; i < kMaxTrackedDevices; ++i) {
    if (devices_[i].used && devices_[i].deviceId == deviceId) return i;
  }
  return -1;
}

int ApiServer::allocateDeviceSlot(uint32_t deviceId) {
  for (int i = 0; i < kMaxTrackedDevices; ++i) {
    if (!devices_[i].used) {
      devices_[i] = DeviceState{};
      devices_[i].used = true;
      devices_[i].deviceId = deviceId;
      return i;
    }
  }
  const int idx = nextDeviceReplace_ % kMaxTrackedDevices;
  nextDeviceReplace_ = (uint8_t)((nextDeviceReplace_ + 1U) % kMaxTrackedDevices);
  devices_[idx] = DeviceState{};
  devices_[idx].used = true;
  devices_[idx].deviceId = deviceId;
  return idx;
}

void ApiServer::updateDeviceFromPacket(const String& json) {
  StaticJsonDocument<768> packet;
  if (deserializeJson(packet, json) != DeserializationError::Ok) return;

  uint32_t deviceId = 0;
  if (!parseDeviceId(packet["device_id"], deviceId)) return;

  int idx = findDeviceSlot(deviceId);
  if (idx < 0) idx = allocateDeviceSlot(deviceId);
  DeviceState& device = devices_[idx];

  device.deviceId = deviceId;
  device.lastSeenMs = millis();

  if (packet["seq"].is<uint32_t>() || packet["seq"].is<int>()) {
    device.seq = packet["seq"].as<uint32_t>();
  }
  if (packet["timestamp"].is<uint32_t>() || packet["timestamp"].is<int>()) {
    device.timestamp = packet["timestamp"].as<uint32_t>();
  }
  if (packet["msg_type"].is<int>()) {
    device.msgType = packet["msg_type"].as<int>();
  }
  if (packet["ok"].is<bool>()) {
    device.hasCommandOk = true;
    device.commandOk = packet["ok"].as<bool>();
  }

  copyToBuffer(device.type, sizeof(device.type), packet["type"] | "");
  copyToBuffer(
      device.gatewayId, sizeof(device.gatewayId), packet["gateway_id"] | "");

  const char* payloadText = packet["payload"] | "";
  if (!payloadText || !payloadText[0]) return;

  StaticJsonDocument<384> payload;
  if (deserializeJson(payload, payloadText) != DeserializationError::Ok) return;

  double lat = 0.0;
  double lon = 0.0;
  bool hasLatLon = parseCoordinate(payload["lat"], lat) &&
                   parseCoordinate(payload["lon"], lon);

  if (!hasLatLon && payload["gps"].is<JsonObjectConst>()) {
    const JsonObjectConst gps = payload["gps"].as<JsonObjectConst>();
    hasLatLon =
        parseCoordinate(gps["lat"], lat) && parseCoordinate(gps["lon"], lon);
  }

  if (!hasLatLon) return;
  if (lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0) return;

  device.lat = (float)lat;
  device.lon = (float)lon;
  device.hasLocation = true;
}

void ApiServer::handleDevicesRequest() {
  int limit = kMaxTrackedDevices;
  if (http_.hasArg("limit")) {
    const int parsed = http_.arg("limit").toInt();
    if (parsed > 0 && parsed < limit) {
      limit = parsed;
    }
  }

  uint8_t order[kMaxTrackedDevices];
  uint8_t count = 0;
  for (uint8_t i = 0; i < kMaxTrackedDevices; ++i) {
    if (!devices_[i].used) continue;
    order[count++] = i;
  }

  for (uint8_t i = 0; i < count; ++i) {
    for (uint8_t j = i + 1; j < count; ++j) {
      if (devices_[order[j]].lastSeenMs > devices_[order[i]].lastSeenMs) {
        const uint8_t tmp = order[i];
        order[i] = order[j];
        order[j] = tmp;
      }
    }
  }

  const uint8_t take = (count < (uint8_t)limit) ? count : (uint8_t)limit;
  DynamicJsonDocument outDoc(4096);
  JsonArray arr = outDoc.to<JsonArray>();
  const uint32_t now = millis();

  for (uint8_t i = 0; i < take; ++i) {
    const DeviceState& device = devices_[order[i]];
    JsonObject item = arr.createNestedObject();
    item["device_id"] = device.deviceId;
    item["last_seen_ms"] = device.lastSeenMs;
    item["age_ms"] = now - device.lastSeenMs;
    item["online"] = (now - device.lastSeenMs) <= 120000UL;
    item["seq"] = device.seq;
    item["timestamp"] = device.timestamp;
    if (device.msgType >= 0) item["msg_type"] = device.msgType;
    if (device.type[0]) item["type"] = device.type;
    if (device.gatewayId[0]) item["gateway_id"] = device.gatewayId;
    if (device.hasLocation) {
      item["lat"] = device.lat;
      item["lon"] = device.lon;
    }
    if (device.hasCommandOk) {
      item["last_command_ok"] = device.commandOk;
    }
  }

  String out;
  serializeJson(outDoc, out);
  http_.send(200, "application/json", out);
}

void ApiServer::handleLogsRequest() {
  int limit = 30;
  if (http_.hasArg("limit")) {
    const int parsed = http_.arg("limit").toInt();
    if (parsed > 0) limit = parsed;
  }
  if (limit > kLogRingSize) limit = kLogRingSize;

  if (logsCount_ == 0) {
    http_.send(200, "text/plain", "Sem logs em memoria.\n");
    return;
  }

  const int start = (logsHead_ + kLogRingSize - logsCount_) % kLogRingSize;
  const int skip = (logsCount_ > limit) ? (logsCount_ - limit) : 0;
  String out;
  out.reserve((size_t)limit * 96U);

  for (int i = 0; i < logsCount_; ++i) {
    if (i < skip) continue;
    const int idx = (start + i) % kLogRingSize;
    out += logs_[idx];
    out += '\n';
  }

  http_.send(200, "text/plain", out);
}

void ApiServer::onWsEvent(
    uint8_t num, WStype_t type, uint8_t* payload, size_t length) {
  if (type == WStype_CONNECTED) {
    appendLogLine(String("WS_CONNECTED|client=") + String(num));
    ws_.sendTXT(num, "{\"type\":\"hello\",\"status\":\"connected\"}");
  } else if (type == WStype_TEXT) {
    const String incoming = String((char*)payload).substring(0, length);
    appendLogLine(String("WS_IN|") + incoming);
    queue_[head_] = incoming;
    head_ = (uint8_t)((head_ + 1U) % kCommandQueueSize);
    if (head_ == tail_) {
      tail_ = (uint8_t)((tail_ + 1U) % kCommandQueueSize);
    }
  }
}

void ApiServer::loop() {
  http_.handleClient();
  ws_.loop();
}

void ApiServer::broadcastTelemetry(const String& json) {
  appendLogLine(String("WS_OUT|") + json);
  updateDeviceFromPacket(json);
  String payload = json;
  ws_.broadcastTXT(payload);
}

bool ApiServer::hasPendingCommand() const { return head_ != tail_; }

bool ApiServer::popCommand(StaticJsonDocument<4096>& out) {
  if (!hasPendingCommand()) return false;
  String s = queue_[tail_];
  tail_ = (uint8_t)((tail_ + 1U) % kCommandQueueSize);
  return deserializeJson(out, s) == DeserializationError::Ok;
}
