/**
 * @file SensorsManager.h
 * @brief Leitura de GPS, MLX90614 e MPU6050 com validação de qualidade.
 */
#pragma once
#include <Arduino.h>
#include <TinyGPSPlus.h>
#include <Adafruit_MLX90614.h>
#include <MPU6050_tockn.h>
#include <Wire.h>
#include "Types.h"

class SensorsManager {
 public:
  void begin();
  void tick();
  GpsData readGpsSnapshot();
  Telemetry readTelemetry(CollarMode mode, uint32_t uptimeSec, int16_t rssi, float snr);
  bool gpsHealthy(const GpsData& gps) const;
  bool gpsUartReady() const { return gpsUartReady_; }
  bool gpsNmeaSeen() const { return gpsNmeaSeen_; }
  bool mpuDetected() const { return mpuDetected_; }
  bool mpuReady() const { return mpuReady_; }
  bool mlxDetected() const { return mlxDetected_; }
  bool mlxReady() const { return mlxReady_; }
  uint8_t mpuAddress() const { return mpuAddress_; }
  uint16_t i2cDevicesFound() const { return i2cDevicesFound_; }
  const String& i2cScanSummary() const { return i2cScanSummary_; }
  uint32_t gpsBootBytes() const { return gpsBootBytes_; }
  uint16_t gpsBootDollarCount() const { return gpsBootDollarCount_; }
  const String& gpsBootSample() const { return gpsBootSample_; }
  uint32_t gpsBaudUsed() const { return gpsBaudUsed_; }

 private:
  bool probeI2cAddress(uint8_t address) const;
  void runI2cScan();
  void captureGpsBootSampleChar(char c);
  HardwareSerial gpsSerial_{1};
  TinyGPSPlus gps_;
  Adafruit_MLX90614 mlx_;
  MPU6050 mpu_{Wire};
  uint32_t lastMotionMs_ = 0;
  bool moving_ = true;
  bool gpsUartReady_ = false;
  bool gpsNmeaSeen_ = false;
  bool mpuDetected_ = false;
  bool mpuReady_ = false;
  bool mlxDetected_ = false;
  bool mlxReady_ = false;
  uint8_t mpuAddress_ = 0;
  uint16_t i2cDevicesFound_ = 0;
  String i2cScanSummary_;
  uint32_t gpsBootBytes_ = 0;
  uint16_t gpsBootDollarCount_ = 0;
  String gpsBootSample_;
  uint32_t gpsBaudUsed_ = 9600;
};
