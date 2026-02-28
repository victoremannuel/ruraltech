/**
 * @file SmartGps.h
 * @brief Localizacao inteligente: validacao, anti-outlier, filtro e lock parado.
 */
#pragma once

#include <Arduino.h>
#include "Types.h"

struct SmartFixFlags {
  bool invalidFixRejected = false;
  bool outlierDropped = false;
  bool lockStateChanged = false;
  bool usedLastGoodFix = false;
  bool officialUpdated = false;
  float outlierSpeedMps = 0.0f;
};

struct SmartFixResult {
  GpsData officialFix{};
  SmartFixFlags flags{};
};

class SmartGps {
 public:
  void begin();
  SmartFixResult update(const GpsData& rawFix, bool moving, uint32_t nowMs);
  bool hasLastGoodFix() const { return hasLastGoodFix_; }
  const GpsData& lastGoodFix() const { return lastGoodFix_; }

 private:
  bool ensureEepromReady();
  bool loadLastGoodFixFromEeprom();
  void persistLastGoodFix();
  bool rawFixMeetsQuality(const GpsData& rawFix) const;
  bool isOutlier(const GpsData& candidate, uint32_t nowMs, float* outSpeedMps) const;
  void pushMedianSample(double lat, double lon);
  double medianValue(const double* window) const;
  GpsData applyFilter(const GpsData& candidate, bool moving, uint32_t nowMs) const;
  static double haversineMeters(double lat1, double lon1, double lat2, double lon2);
  static uint16_t crc16(const uint8_t* data, size_t len);

  GpsData lastGoodFix_{};
  bool hasLastGoodFix_ = false;
  uint32_t lastGoodMs_ = 0;

  bool locked_ = false;
  GpsData lockedFix_{};
  uint32_t stopSinceMs_ = 0;

  double latWindow_[cfg::MEDIAN_WINDOW]{};
  double lonWindow_[cfg::MEDIAN_WINDOW]{};
  uint8_t windowCount_ = 0;
  uint8_t windowHead_ = 0;

  bool eepromReady_ = false;
};
