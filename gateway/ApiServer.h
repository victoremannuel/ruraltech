/**
 * @file ApiServer.h
 * @brief REST + WebSocket para integração app móvel.
 */
#pragma once
#include <WebServer.h>
#include <WebSocketsServer.h>
#include <ArduinoJson.h>
#include "config.h"

class ApiServer {
 public:
  void begin();
  void loop();
  void broadcastTelemetry(const String& json);
  bool hasPendingCommand() const;
  bool popCommand(StaticJsonDocument<512>& out);

 private:
  WebServer http_{80};
  WebSocketsServer ws_{cfg::WS_PORT};
  String queue_[8];
  uint8_t head_ = 0;
  uint8_t tail_ = 0;
  void onWsEvent(uint8_t num, WStype_t type, uint8_t* payload, size_t length);
};
