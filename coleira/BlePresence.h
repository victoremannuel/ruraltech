/**
 * @file BlePresence.h
 * @brief BLE advertisement helper for device discovery in mobile app.
 */
#pragma once

#include <Arduino.h>

class BLEServer;
class BLEService;
class BLECharacteristic;
class BLEServerCallbacks;
class BLECharacteristicCallbacks;

enum class BleNodeKind : uint8_t {
  COLLAR = 1,
  GATEWAY = 2,
  MATRIX = 3,
};

class BlePresence {
 public:
  bool begin(
      BleNodeKind kind,
      const String& id,
      const String& advName,
      uint16_t companyId,
      const char* serviceUuid);

  void setPosition(double lat, double lon, bool hasPosition);
  void setFlags(bool wifiEnabled, bool internetConnected);
  void setEnabled(bool enabled);
  void loop();
  void setClientConnected(bool connected);
  bool clientConnected() const { return clientConnected_; }

 private:
  void refreshAdvertising();
  void updatePositionCharacteristic();
  void maybeNotifyConnectedClient();

  bool started_ = false;
  bool enabled_ = true;
  bool dirty_ = false;
  uint32_t lastRefreshMs_ = 0;

  BleNodeKind kind_ = BleNodeKind::GATEWAY;
  uint16_t companyId_ = 0x1234;
  String id_;
  String advName_;
  String serviceUuid_;
  BLEServer* server_ = nullptr;
  BLEService* service_ = nullptr;
  BLECharacteristic* positionCharacteristic_ = nullptr;
  BLEServerCallbacks* serverCallbacks_ = nullptr;
  BLECharacteristicCallbacks* positionCallbacks_ = nullptr;

  bool hasPosition_ = false;
  int32_t latE6_ = 0;
  int32_t lonE6_ = 0;
  bool wifiEnabled_ = false;
  bool internetConnected_ = false;
  bool clientConnected_ = false;
  uint32_t lastNotifyMs_ = 0;
};
