/**
 * @file BlePresence.cpp
 * @brief BLE advertisement helper for device discovery in mobile app.
 */
#include "BlePresence.h"
#include "Logger.h"

#include <math.h>

#include <BLEAdvertising.h>
#include <BLECharacteristic.h>
#include <BLEDevice.h>
#include <BLE2902.h>
#include <BLEServer.h>
#include <BLEService.h>
#include <BLEUtils.h>

namespace {
constexpr uint32_t kMinRefreshMs = 900;
constexpr uint8_t kAdvMaxBytes = 31;
constexpr uint8_t kAdStructureOverhead = 2;  // length + type
constexpr uint8_t kMaxMfgDataBytes = kAdvMaxBytes - kAdStructureOverhead;
constexpr uint32_t kNotifyIntervalMs = 1000;
// companyId(2) + "RTB1"(4) + kind(1) + idLen(1) + flags(1) + latE6(4) + lonE6(4)
constexpr uint8_t kMfgFixedBytes = 17;
constexpr char kPositionCharacteristicUuid[] =
    "7f920002-0a26-4d09-a606-0cfef4f9a1f0";

void writeInt32LE(uint8_t* out, int32_t value) {
  out[0] = (uint8_t)(value & 0xFF);
  out[1] = (uint8_t)((value >> 8) & 0xFF);
  out[2] = (uint8_t)((value >> 16) & 0xFF);
  out[3] = (uint8_t)((value >> 24) & 0xFF);
}

class PresenceServerCallbacks final : public BLEServerCallbacks {
 public:
  explicit PresenceServerCallbacks(BlePresence* owner) : owner_(owner) {}

  void onConnect(BLEServer* pServer) override {
    (void)pServer;
    if (owner_ != nullptr) owner_->setClientConnected(true);
    Serial.println("[BLE] cliente conectado");
  }

  void onDisconnect(BLEServer* pServer) override {
    (void)pServer;
    if (owner_ != nullptr) owner_->setClientConnected(false);
    Serial.println("[BLE] cliente desconectado; retomando advertising");
    BLEAdvertising* adv = BLEDevice::getAdvertising();
    if (adv != nullptr) {
      adv->start();
    } else {
      Serial.println("[BLE] advertising indisponivel ao desconectar");
    }
  }

 private:
  BlePresence* owner_ = nullptr;
};

class PositionReadCallbacks final : public BLECharacteristicCallbacks {
 public:
  void onRead(BLECharacteristic* characteristic) override {
    (void)characteristic;
    Serial.println("[BLE] onRead posicao");
  }
};
}  // namespace

bool BlePresence::begin(
    BleNodeKind kind,
    const String& id,
    const String& advName,
    uint16_t companyId,
    const char* serviceUuid) {
  if (id.isEmpty()) return false;

  kind_ = kind;
  companyId_ = companyId;
  id_ = id;
  if (id_.length() > 18) id_ = id_.substring(0, 18);

  advName_ = advName;
  if (advName_.isEmpty()) advName_ = "RuralTech";
  if (advName_.length() > 20) advName_ = advName_.substring(0, 20);

  serviceUuid_ = serviceUuid ? String(serviceUuid) : String();

  BLEDevice::init(advName_.c_str());
  server_ = BLEDevice::createServer();
  if (server_ != nullptr) {
    if (serverCallbacks_ == nullptr) serverCallbacks_ = new PresenceServerCallbacks(this);
    if (serverCallbacks_ != nullptr) server_->setCallbacks(serverCallbacks_);
  }
  if (server_ != nullptr && !serviceUuid_.isEmpty()) {
    service_ = server_->createService(serviceUuid_.c_str());
    if (service_ != nullptr) {
      positionCharacteristic_ = service_->createCharacteristic(
          kPositionCharacteristicUuid,
          BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
      if (positionCharacteristic_ != nullptr) {
        positionCharacteristic_->addDescriptor(new BLE2902());
        if (positionCallbacks_ == nullptr) {
          positionCallbacks_ = new PositionReadCallbacks();
        }
        if (positionCallbacks_ != nullptr) {
          positionCharacteristic_->setCallbacks(positionCallbacks_);
        }
      }
      updatePositionCharacteristic();
      service_->start();
    }
  }
  BLEDevice::getAdvertising();

  started_ = true;
  enabled_ = true;
  dirty_ = true;
  refreshAdvertising();
  return true;
}

void BlePresence::setPosition(double lat, double lon, bool hasPosition) {
  bool changed = false;
  if (!hasPosition || !isfinite(lat) || !isfinite(lon) || lat < -90.0 ||
      lat > 90.0 || lon < -180.0 || lon > 180.0) {
    if (hasPosition_) {
      hasPosition_ = false;
      latE6_ = 0;
      lonE6_ = 0;
      changed = true;
    }
  } else {
    const int32_t latE6 = (int32_t)lround(lat * 1000000.0);
    const int32_t lonE6 = (int32_t)lround(lon * 1000000.0);
    if (!hasPosition_ || latE6 != latE6_ || lonE6 != lonE6_) {
      hasPosition_ = true;
      latE6_ = latE6;
      lonE6_ = lonE6;
      changed = true;
    }
  }
  if (!changed) return;

  updatePositionCharacteristic();
  dirty_ = true;
}

void BlePresence::setFlags(bool wifiEnabled, bool internetConnected) {
  if (wifiEnabled_ == wifiEnabled && internetConnected_ == internetConnected) {
    return;
  }
  wifiEnabled_ = wifiEnabled;
  internetConnected_ = internetConnected;
  dirty_ = true;
}

void BlePresence::setEnabled(bool enabled) {
  if (enabled_ == enabled) return;
  enabled_ = enabled;
  if (!started_) return;
  BLEAdvertising* adv = BLEDevice::getAdvertising();
  if (adv == nullptr) return;
  if (!enabled_) {
    adv->stop();
    return;
  }
  dirty_ = true;
  lastRefreshMs_ = 0;
}

void BlePresence::loop() {
  if (clientConnected_) {
    maybeNotifyConnectedClient();
    return;
  }
  if (!started_ || !enabled_ || !dirty_) return;
  const uint32_t now = millis();
  if (now - lastRefreshMs_ < kMinRefreshMs) return;
  refreshAdvertising();
}

void BlePresence::refreshAdvertising() {
  if (!started_ || !enabled_) return;

  uint8_t raw[kMaxMfgDataBytes] = {};
  size_t i = 0;

  // Manufacturer specific data = company id + custom payload.
  raw[i++] = (uint8_t)(companyId_ & 0xFF);
  raw[i++] = (uint8_t)((companyId_ >> 8) & 0xFF);
  raw[i++] = 'R';
  raw[i++] = 'T';
  raw[i++] = 'B';
  raw[i++] = '1';
  raw[i++] = (uint8_t)kind_;

  const uint8_t maxIdLen =
      kMaxMfgDataBytes > kMfgFixedBytes ? (kMaxMfgDataBytes - kMfgFixedBytes) : 0;
  const uint8_t idLen = (uint8_t)min((size_t)maxIdLen, id_.length());
  raw[i++] = idLen;
  for (uint8_t n = 0; n < idLen; ++n) {
    raw[i++] = (uint8_t)id_[n];
  }

  uint8_t flags = 0;
  if (hasPosition_) flags |= 0x01;
  if (wifiEnabled_) flags |= 0x02;
  if (internetConnected_) flags |= 0x04;
  raw[i++] = flags;

  writeInt32LE(raw + i, latE6_);
  i += 4;
  writeInt32LE(raw + i, lonE6_);
  i += 4;

  BLEAdvertisementData advData;
  String mfgData;
  mfgData.reserve(i);
  mfgData.concat((const char*)raw, i);
  advData.setManufacturerData(mfgData);

  BLEAdvertisementData scanData;
  scanData.setName(advName_);

  BLEAdvertising* adv = BLEDevice::getAdvertising();
  if (adv == nullptr) return;
  adv->stop();
  adv->setScanResponse(true);
  // Parametros que melhoram a compatibilidade de conexao BLE no iOS.
  adv->setMinPreferred(0x06);
  adv->setMaxPreferred(0x12);
  adv->setAdvertisementData(advData);
  adv->setScanResponseData(scanData);
  adv->start();

  dirty_ = false;
  lastRefreshMs_ = millis();
}

void BlePresence::setClientConnected(bool connected) {
  if (clientConnected_ == connected) return;
  clientConnected_ = connected;
  lastNotifyMs_ = 0;
  if (!connected) {
    // Reforca refresh apos desconexao para publicar estado atual.
    dirty_ = true;
    lastRefreshMs_ = 0;
  }
}

void BlePresence::updatePositionCharacteristic() {
  if (positionCharacteristic_ == nullptr) return;

  // ASCII evita ambiguidades com bytes zero em alguns stacks iOS/FBP.
  char payload[48] = {};
  snprintf(
      payload,
      sizeof(payload),
      "RTP1;%d;%ld;%ld",
      hasPosition_ ? 1 : 0,
      (long)latE6_,
      (long)lonE6_);
  positionCharacteristic_->setValue(payload);
  if (clientConnected_) {
    positionCharacteristic_->notify();
    lastNotifyMs_ = millis();
  }
}

void BlePresence::maybeNotifyConnectedClient() {
  if (positionCharacteristic_ == nullptr) return;
  const uint32_t now = millis();
  if (lastNotifyMs_ != 0 && (now - lastNotifyMs_) < kNotifyIntervalMs) return;
  positionCharacteristic_->notify();
  lastNotifyMs_ = now;
}
