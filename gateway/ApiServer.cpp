/** @file ApiServer.cpp */
#include "ApiServer.h"
#include "config.h"

static ApiServer* g_server = nullptr;

void ApiServer::begin() {
  g_server = this;
  http_.on("/status", HTTP_GET, [this]() {
    http_.send(200, "application/json", "{\"ok\":true,\"service\":\"gateway\"}");
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

void ApiServer::broadcastTelemetry(const String& json) { ws_.broadcastTXT(json); }

bool ApiServer::hasPendingCommand() const { return head_ != tail_; }

bool ApiServer::popCommand(StaticJsonDocument<512>& out) {
  if (!hasPendingCommand()) return false;
  String s = queue_[tail_];
  tail_ = (tail_ + 1) % 8;
  return deserializeJson(out, s) == DeserializationError::Ok;
}
