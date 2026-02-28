#line 1 "/Users/victor/Downloads/code/ruraltech/coleira/SensorsManager.cpp"
/**
 * @file SensorsManager.cpp
 * @brief Implementação dos sensores com fallback seguro.
 */
#include "SensorsManager.h"
#include "Logger.h"
#include "config.h"

void SensorsManager::begin() {
  Wire.begin(cfg::PIN_I2C_SDA, cfg::PIN_I2C_SCL);
  gpsSerial_.begin(9600, SERIAL_8N1, cfg::PIN_GPS_RX, cfg::PIN_GPS_TX);

  if (!mlx_.begin()) LOGW("MLX90614 indisponível; telemetria de temperatura será 0");
  mpu_.begin();
  mpu_.calcGyroOffsets(true);
  lastMotionMs_ = millis();
}

void SensorsManager::tick() {
  while (gpsSerial_.available()) gps_.encode(gpsSerial_.read());
  mpu_.update();
  const float acc = fabs(mpu_.getAccX()) + fabs(mpu_.getAccY()) + fabs(mpu_.getAccZ() - 1.0f);
  if (acc > cfg::MOTION_THRESHOLD_G) {
    moving_ = true;
    lastMotionMs_ = millis();
  } else if (millis() - lastMotionMs_ > cfg::NO_MOTION_MS) {
    moving_ = false;
  }
}

Telemetry SensorsManager::readTelemetry(CollarMode mode, uint32_t uptimeSec, int16_t rssi, float snr) {
  Telemetry t;
  t.temperatureC = mlx_.readObjectTempC();
  t.moving = moving_;
  t.uptime = uptimeSec;
  t.rssi = rssi;
  t.snr = snr;
  t.mode = mode;

  t.gps.valid = gps_.location.isValid();
  if (t.gps.valid) {
    t.gps.lat = gps_.location.lat();
    t.gps.lon = gps_.location.lng();
    t.gps.speedKmph = gps_.speed.kmph();
    t.gps.hdop = gps_.hdop.isValid() ? gps_.hdop.hdop() : 99.9f;
    t.gps.sats = gps_.satellites.isValid() ? gps_.satellites.value() : 0;
    t.gps.gpsTime = gps_.time.isValid() ? gps_.time.value() : 0;
  }
  return t;
}

bool SensorsManager::gpsHealthy(const GpsData& gps) const {
  return gps.valid && gps.hdop <= cfg::MAX_HDOP_FOR_PULSE && gps.sats >= cfg::MIN_SATS;
}
