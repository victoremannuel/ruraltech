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
  bool popCommand(StaticJsonDocument<4096>& out);

 private:
  static constexpr uint8_t kCommandQueueSize = 8;
  static constexpr uint8_t kMaxTrackedDevices = 24;
  static constexpr uint8_t kLogRingSize = 48;

  struct DeviceState {
    uint32_t deviceId = 0;
    uint32_t seq = 0;
    uint32_t timestamp = 0;
    uint32_t lastSeenMs = 0;
    int16_t msgType = -1;
    float lat = 0.0f;
    float lon = 0.0f;
    bool hasLocation = false;
    bool hasCommandOk = false;
    bool commandOk = false;
    bool used = false;
    char type[20]{};
    char gatewayId[20]{};
  };

  WebServer http_{80};
  WebSocketsServer ws_{cfg::WS_PORT};
  String queue_[kCommandQueueSize];
  uint8_t head_ = 0;
  uint8_t tail_ = 0;
  DeviceState devices_[kMaxTrackedDevices]{};
  uint8_t nextDeviceReplace_ = 0;
  String logs_[kLogRingSize];
  uint8_t logsHead_ = 0;
  uint8_t logsCount_ = 0;

  void onWsEvent(uint8_t num, WStype_t type, uint8_t* payload, size_t length);
  void appendLogLine(const String& line);
  void updateDeviceFromPacket(const String& json);
  int findDeviceSlot(uint32_t deviceId) const;
  int allocateDeviceSlot(uint32_t deviceId);
  void handleDevicesRequest();
  void handleLogsRequest();
};
