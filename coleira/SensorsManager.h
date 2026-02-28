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

 private:
  HardwareSerial gpsSerial_{1};
  TinyGPSPlus gps_;
  Adafruit_MLX90614 mlx_;
  MPU6050 mpu_{Wire};
  uint32_t lastMotionMs_ = 0;
  bool moving_ = true;
};
