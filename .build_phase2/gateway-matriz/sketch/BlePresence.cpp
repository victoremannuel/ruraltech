#line 1 "/Users/victor/Downloads/code/ruraltech/gateway-matriz/BlePresence.cpp"
/**
 * @file BlePresence.cpp
 * @brief BLE advertisement helper for device discovery in mobile app.
 */
#include "BlePresence.h"
#include "config.h"

#include <math.h>

#if RT_MATRIX_BLE_ENABLED
#include <BLEAdvertising.h>
#include <BLEDevice.h>
#include <BLEUtils.h>

namespace {
constexpr uint32_t kMinRefreshMs = 900;

void writeInt32LE(uint8_t* out, int32_t value) {
  out[0] = (uint8_t)(value & 0xFF);
  out[1] = (uint8_t)((value >> 8) & 0xFF);
  out[2] = (uint8_t)((value >> 16) & 0xFF);
  out[3] = (uint8_t)((value >> 24) & 0xFF);
}
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
  BLEAdvertising* adv = BLEDevice::getAdvertising();
  if (!serviceUuid_.isEmpty()) {
    adv->addServiceUUID(serviceUuid_.c_str());
  }

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
  if (changed) dirty_ = true;
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
  if (!enabled_) {
    adv->stop();
    return;
  }
  dirty_ = true;
  lastRefreshMs_ = 0;
}

void BlePresence::loop() {
  if (!started_ || !enabled_ || !dirty_) return;
  const uint32_t now = millis();
  if (now - lastRefreshMs_ < kMinRefreshMs) return;
  refreshAdvertising();
}

void BlePresence::refreshAdvertising() {
  if (!started_ || !enabled_) return;

  uint8_t raw[36] = {};
  size_t i = 0;

  // Manufacturer specific data = company id + custom payload.
  raw[i++] = (uint8_t)(companyId_ & 0xFF);
  raw[i++] = (uint8_t)((companyId_ >> 8) & 0xFF);
  raw[i++] = 'R';
  raw[i++] = 'T';
  raw[i++] = 'B';
  raw[i++] = '1';
  raw[i++] = (uint8_t)kind_;

  const uint8_t idLen = (uint8_t)min((size_t)18, id_.length());
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
  advData.setFlags(0x06);
  String mfgData;
  mfgData.reserve(i);
  mfgData.concat((const char*)raw, i);
  advData.setManufacturerData(mfgData);

  BLEAdvertisementData scanData;
  scanData.setName(advName_);

  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->stop();
  adv->setAdvertisementData(advData);
  adv->setScanResponseData(scanData);
  adv->start();

  dirty_ = false;
  lastRefreshMs_ = millis();
}
#else
bool BlePresence::begin(
    BleNodeKind kind,
    const String& id,
    const String& advName,
    uint16_t companyId,
    const char* serviceUuid) {
  (void)kind;
  (void)id;
  (void)advName;
  (void)companyId;
  (void)serviceUuid;
  started_ = false;
  return false;
}

void BlePresence::setPosition(double lat, double lon, bool hasPosition) {
  (void)lat;
  (void)lon;
  (void)hasPosition;
}

void BlePresence::setFlags(bool wifiEnabled, bool internetConnected) {
  (void)wifiEnabled;
  (void)internetConnected;
}

void BlePresence::setEnabled(bool enabled) { (void)enabled; }

void BlePresence::loop() {}

void BlePresence::refreshAdvertising() {}
#endif
