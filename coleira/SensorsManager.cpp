/**
 * @file SensorsManager.cpp
 * @brief Implementação dos sensores com fallback seguro.
 */
#include "SensorsManager.h"
#include "Logger.h"
#include "config.h"

namespace {
constexpr uint8_t kMlxAddress = 0x5A;
constexpr uint8_t kMpuAddr0 = 0x68;
constexpr uint8_t kMpuAddr1 = 0x69;
constexpr uint32_t kGpsProbeWindowMsPerBaud = 1200;
constexpr size_t kGpsBootSampleMaxLen = 24;
constexpr uint8_t kI2cScanDetailLimit = 10;
constexpr uint32_t kGpsProbeBauds[] = {9600, 38400, 57600, 115200};
}

bool SensorsManager::probeI2cAddress(uint8_t address) const {
  Wire.beginTransmission(address);
  const uint8_t err = Wire.endTransmission();
  return err == 0;
}

void SensorsManager::runI2cScan() {
  i2cDevicesFound_ = 0;
  i2cScanSummary_ = "";
  for (uint8_t addr = 1; addr < 127; ++addr) {
    if (!probeI2cAddress(addr)) continue;
    ++i2cDevicesFound_;
    if (i2cDevicesFound_ <= kI2cScanDetailLimit) {
      char part[8] = {};
      snprintf(part, sizeof(part), "0x%02X", addr);
      if (!i2cScanSummary_.isEmpty()) i2cScanSummary_ += ",";
      i2cScanSummary_ += part;
    }
  }
  if (i2cDevicesFound_ == 0) {
    i2cScanSummary_ = "none";
    return;
  }
  if (i2cDevicesFound_ > kI2cScanDetailLimit) {
    i2cScanSummary_ += ",...";
  }
}

void SensorsManager::captureGpsBootSampleChar(char c) {
  if (gpsBootSample_.length() >= kGpsBootSampleMaxLen) return;
  if (c >= 32 && c <= 126) {
    gpsBootSample_ += c;
  } else {
    gpsBootSample_ += '.';
  }
}

void SensorsManager::begin() {
  Wire.begin(cfg::PIN_I2C_SDA, cfg::PIN_I2C_SCL);
  runI2cScan();
  mlxDetected_ = probeI2cAddress(kMlxAddress);
  if (probeI2cAddress(kMpuAddr0)) {
    mpuAddress_ = kMpuAddr0;
  } else if (probeI2cAddress(kMpuAddr1)) {
    mpuAddress_ = kMpuAddr1;
  }
  mpuDetected_ = mpuAddress_ != 0;

  gpsUartReady_ = false;
  gpsNmeaSeen_ = false;
  gpsBaudUsed_ = kGpsProbeBauds[0];
  gpsBootBytes_ = 0;
  gpsBootDollarCount_ = 0;
  gpsBootSample_ = "";
  for (size_t i = 0; i < (sizeof(kGpsProbeBauds) / sizeof(kGpsProbeBauds[0])); ++i) {
    const uint32_t baud = kGpsProbeBauds[i];
    gpsSerial_.end();
    gpsSerial_.begin(baud, SERIAL_8N1, cfg::PIN_GPS_RX, cfg::PIN_GPS_TX);
    gpsUartReady_ = true;

    const uint32_t gpsProbeStart = millis();
    while ((uint32_t)(millis() - gpsProbeStart) < kGpsProbeWindowMsPerBaud) {
      while (gpsSerial_.available()) {
        const int c = gpsSerial_.read();
        if (c < 0) continue;
        ++gpsBootBytes_;
        captureGpsBootSampleChar((char)c);
        gps_.encode((char)c);
        if (c == '$') {
          gpsNmeaSeen_ = true;
          ++gpsBootDollarCount_;
          gpsBaudUsed_ = baud;
        }
      }
      if (gpsNmeaSeen_) break;
      delay(10);
    }
    if (gpsNmeaSeen_) break;
  }

  if (mlxDetected_) {
    mlxReady_ = mlx_.begin();
  } else {
    mlxReady_ = false;
  }
  if (!mlxReady_) LOGW("MLX90614 indisponível; telemetria de temperatura será 0");

  if (mpuDetected_) {
    mpu_.begin();
    mpu_.calcGyroOffsets(true);
    mpuReady_ = true;
  } else {
    mpuReady_ = false;
  }
  lastMotionMs_ = millis();
}

void SensorsManager::tick() {
  while (gpsSerial_.available()) gps_.encode(gpsSerial_.read());
  if (!mpuReady_) return;
  mpu_.update();
  const float acc = fabs(mpu_.getAccX()) + fabs(mpu_.getAccY()) + fabs(mpu_.getAccZ() - 1.0f);
  if (acc > cfg::MOTION_THRESHOLD_G) {
    moving_ = true;
    lastMotionMs_ = millis();
  } else if (millis() - lastMotionMs_ > cfg::NO_MOTION_MS) {
    moving_ = false;
  }
}

GpsData SensorsManager::readGpsSnapshot() {
  GpsData gps;
  gps.valid = gps_.location.isValid();
  if (!gps.valid) return gps;

  gps.lat = gps_.location.lat();
  gps.lon = gps_.location.lng();
  gps.speedKmph = gps_.speed.kmph();
  gps.hdop = gps_.hdop.isValid() ? gps_.hdop.hdop() : 99.9f;
  gps.sats = gps_.satellites.isValid() ? gps_.satellites.value() : 0;
  gps.gpsTime = gps_.time.isValid() ? gps_.time.value() : 0;
  return gps;
}

Telemetry SensorsManager::readTelemetry(CollarMode mode, uint32_t uptimeSec, int16_t rssi, float snr) {
  Telemetry t;
  t.temperatureC = mlxReady_ ? mlx_.readObjectTempC() : 0.0f;
  t.moving = moving_;
  t.uptime = uptimeSec;
  t.rssi = rssi;
  t.snr = snr;
  t.mode = mode;

  t.gps = readGpsSnapshot();
  return t;
}

bool SensorsManager::gpsHealthy(const GpsData& gps) const {
  return gps.valid && gps.hdop <= cfg::MAX_HDOP_FOR_PULSE && gps.sats >= cfg::MIN_SATS;
}
