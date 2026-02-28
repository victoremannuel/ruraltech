/**
 * @file SmartGps.cpp
 * @brief Pipeline de localizacao inteligente para reduzir erro e volatilidade.
 */
#include "SmartGps.h"

#include <EEPROM.h>
#include <math.h>
#include <stddef.h>

#include "Logger.h"
#include "config.h"

namespace {
constexpr uint32_t kPersistMagic = 0x53465831UL;  // "SFX1"

struct PersistedLastGoodFix {
  uint32_t magic;
  int32_t latE7;
  int32_t lonE7;
  float hdop;
  float speedKmph;
  uint8_t sats;
  uint8_t reserved0;
  uint16_t reserved1;
  uint32_t gpsTime;
  uint32_t sampleMs;
  uint16_t crc;
} __attribute__((packed));

constexpr size_t kPersistPayloadSize = offsetof(PersistedLastGoodFix, crc);
}  // namespace

void SmartGps::begin() {
  if (!ensureEepromReady()) return;
  if (loadLastGoodFixFromEeprom()) {
    LOGI("SmartGps: last_good_fix restaurado (lat=%.6f lon=%.6f)", lastGoodFix_.lat, lastGoodFix_.lon);
  } else {
    LOGI("SmartGps: sem last_good_fix persistido");
  }
}

SmartFixResult SmartGps::update(const GpsData& rawFix, bool moving, uint32_t nowMs) {
  SmartFixResult result;
  result.officialFix = hasLastGoodFix_ ? lastGoodFix_ : GpsData{};
  result.officialFix.locked = locked_;
  result.officialFix.outlierDropped = false;
  result.officialFix.sampleMs = nowMs;

  if (moving) {
    stopSinceMs_ = 0;
    if (locked_) {
      locked_ = false;
      result.flags.lockStateChanged = true;
    }
  } else if (stopSinceMs_ == 0) {
    stopSinceMs_ = nowMs;
  }

  bool candidateAccepted = false;
  GpsData candidate = rawFix;
  candidate.sampleMs = nowMs;
  candidate.filtered = false;
  candidate.locked = false;
  candidate.outlierDropped = false;

  if (!rawFixMeetsQuality(rawFix)) {
    result.flags.invalidFixRejected = true;
  } else {
    float outlierSpeed = 0.0f;
    if (isOutlier(rawFix, nowMs, &outlierSpeed)) {
      result.flags.outlierDropped = true;
      result.flags.outlierSpeedMps = outlierSpeed;
    } else {
      candidateAccepted = true;
    }
  }

  if (locked_) {
    if (candidateAccepted) {
      const double distanceFromLock =
          haversineMeters(lockedFix_.lat, lockedFix_.lon, candidate.lat, candidate.lon);
      if (distanceFromLock > cfg::LOCK_RADIUS_M) {
        locked_ = false;
        result.flags.lockStateChanged = true;
      } else {
        result.flags.usedLastGoodFix = true;
        result.officialFix = lockedFix_;
        result.officialFix.valid = true;
        result.officialFix.filtered = true;
        result.officialFix.locked = true;
        result.officialFix.outlierDropped = result.flags.outlierDropped;
        result.officialFix.sampleMs = nowMs;
        return result;
      }
    } else if (hasLastGoodFix_) {
      result.flags.usedLastGoodFix = true;
      result.officialFix = lockedFix_;
      result.officialFix.valid = true;
      result.officialFix.filtered = true;
      result.officialFix.locked = true;
      result.officialFix.outlierDropped = result.flags.outlierDropped;
      result.officialFix.sampleMs = nowMs;
      return result;
    }
  }

  if (!candidateAccepted) {
    if (hasLastGoodFix_) {
      result.flags.usedLastGoodFix = true;
      result.officialFix = lastGoodFix_;
      result.officialFix.valid = true;
      result.officialFix.filtered = true;
      result.officialFix.locked = false;
      result.officialFix.outlierDropped = result.flags.outlierDropped;
      result.officialFix.sampleMs = nowMs;
      return result;
    }
    GpsData noFix;
    noFix.valid = false;
    noFix.hdop = rawFix.hdop;
    noFix.sats = rawFix.sats;
    noFix.gpsTime = rawFix.gpsTime;
    noFix.outlierDropped = result.flags.outlierDropped;
    noFix.sampleMs = nowMs;
    result.officialFix = noFix;
    return result;
  }

  if (!moving && stopSinceMs_ != 0 &&
      (uint32_t)(nowMs - stopSinceMs_) >= cfg::STOP_DETECT_MS &&
      hasLastGoodFix_) {
    const double distToLastGood =
        haversineMeters(lastGoodFix_.lat, lastGoodFix_.lon, candidate.lat, candidate.lon);
    if (distToLastGood <= cfg::LOCK_RADIUS_M) {
      locked_ = true;
      lockedFix_ = lastGoodFix_;
      result.flags.lockStateChanged = true;
      result.flags.usedLastGoodFix = true;
      result.officialFix = lockedFix_;
      result.officialFix.valid = true;
      result.officialFix.filtered = true;
      result.officialFix.locked = true;
      result.officialFix.outlierDropped = false;
      result.officialFix.sampleMs = nowMs;
      return result;
    }
  }

  pushMedianSample(candidate.lat, candidate.lon);
  GpsData filtered = applyFilter(candidate, moving, nowMs);

  lastGoodFix_ = filtered;
  lastGoodFix_.locked = false;
  hasLastGoodFix_ = true;
  lastGoodMs_ = nowMs;
  persistLastGoodFix();

  result.flags.officialUpdated = true;
  result.officialFix = lastGoodFix_;
  result.officialFix.locked = false;
  return result;
}

bool SmartGps::ensureEepromReady() {
  if (eepromReady_) return true;
  eepromReady_ = EEPROM.begin(cfg::EEPROM_SIZE);
  if (!eepromReady_) LOGW("SmartGps: EEPROM indisponivel para last_good_fix");
  return eepromReady_;
}

bool SmartGps::loadLastGoodFixFromEeprom() {
  if (!ensureEepromReady()) return false;
  if ((size_t)cfg::EEPROM_LAST_GOOD_FIX_ADDR + sizeof(PersistedLastGoodFix) > cfg::EEPROM_SIZE) {
    LOGW("SmartGps: endereco EEPROM invalido para last_good_fix");
    return false;
  }

  PersistedLastGoodFix rec{};
  EEPROM.get(cfg::EEPROM_LAST_GOOD_FIX_ADDR, rec);
  if (rec.magic != kPersistMagic) return false;

  const uint16_t crc = crc16(reinterpret_cast<const uint8_t*>(&rec), kPersistPayloadSize);
  if (crc != rec.crc) {
    LOGW("SmartGps: CRC invalido para last_good_fix persistido");
    return false;
  }

  const double lat = rec.latE7 / 10000000.0;
  const double lon = rec.lonE7 / 10000000.0;
  if (!isfinite(lat) || !isfinite(lon) || lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0) {
    return false;
  }

  lastGoodFix_ = GpsData{};
  lastGoodFix_.valid = true;
  lastGoodFix_.lat = lat;
  lastGoodFix_.lon = lon;
  lastGoodFix_.speedKmph = rec.speedKmph;
  lastGoodFix_.hdop = rec.hdop;
  lastGoodFix_.sats = rec.sats;
  lastGoodFix_.gpsTime = rec.gpsTime;
  lastGoodFix_.filtered = true;
  lastGoodFix_.locked = false;
  lastGoodFix_.outlierDropped = false;
  lastGoodFix_.sampleMs = rec.sampleMs;

  hasLastGoodFix_ = true;
  lastGoodMs_ = rec.sampleMs;
  locked_ = false;
  stopSinceMs_ = 0;
  windowCount_ = 0;
  windowHead_ = 0;
  pushMedianSample(lastGoodFix_.lat, lastGoodFix_.lon);
  return true;
}

void SmartGps::persistLastGoodFix() {
  if (!hasLastGoodFix_) return;
  if (!ensureEepromReady()) return;

  PersistedLastGoodFix rec{};
  rec.magic = kPersistMagic;
  rec.latE7 = (int32_t)lround(lastGoodFix_.lat * 10000000.0);
  rec.lonE7 = (int32_t)lround(lastGoodFix_.lon * 10000000.0);
  rec.hdop = lastGoodFix_.hdop;
  rec.speedKmph = lastGoodFix_.speedKmph;
  rec.sats = lastGoodFix_.sats;
  rec.gpsTime = lastGoodFix_.gpsTime;
  rec.sampleMs = lastGoodMs_;
  rec.crc = crc16(reinterpret_cast<const uint8_t*>(&rec), kPersistPayloadSize);

  EEPROM.put(cfg::EEPROM_LAST_GOOD_FIX_ADDR, rec);
  if (!EEPROM.commit()) {
    LOGW("SmartGps: falha commit EEPROM para last_good_fix");
  }
}

bool SmartGps::rawFixMeetsQuality(const GpsData& rawFix) const {
  // TinyGPS++ nao expoe fix type 3D padrao; usamos criterio equivalente de qualidade.
  if (!rawFix.valid) return false;
  if (!isfinite(rawFix.lat) || !isfinite(rawFix.lon)) return false;
  if (rawFix.lat < -90.0 || rawFix.lat > 90.0 || rawFix.lon < -180.0 || rawFix.lon > 180.0) return false;
  if (!isfinite(rawFix.hdop) || rawFix.hdop > cfg::MAX_HDOP) return false;
  if (rawFix.sats < cfg::MIN_SATS) return false;
  return true;
}

bool SmartGps::isOutlier(const GpsData& candidate, uint32_t nowMs, float* outSpeedMps) const {
  if (!hasLastGoodFix_ || !lastGoodFix_.valid || lastGoodMs_ == 0 || nowMs <= lastGoodMs_) return false;

  const uint32_t dtMs = nowMs - lastGoodMs_;
  if (dtMs < 1000U) return false;

  const double distanceM =
      haversineMeters(lastGoodFix_.lat, lastGoodFix_.lon, candidate.lat, candidate.lon);
  const float speedMps = (float)(distanceM / ((double)dtMs / 1000.0));
  if (outSpeedMps) *outSpeedMps = speedMps;
  return speedMps > cfg::OUTLIER_MAX_SPEED;
}

void SmartGps::pushMedianSample(double lat, double lon) {
  latWindow_[windowHead_] = lat;
  lonWindow_[windowHead_] = lon;
  if (windowCount_ < cfg::MEDIAN_WINDOW) windowCount_++;
  windowHead_ = (uint8_t)((windowHead_ + 1U) % cfg::MEDIAN_WINDOW);
}

double SmartGps::medianValue(const double* window) const {
  if (windowCount_ == 0) return 0.0;

  double sorted[cfg::MEDIAN_WINDOW]{};
  for (uint8_t i = 0; i < windowCount_; ++i) sorted[i] = window[i];

  for (uint8_t i = 1; i < windowCount_; ++i) {
    const double key = sorted[i];
    int8_t j = (int8_t)i - 1;
    while (j >= 0 && sorted[(uint8_t)j] > key) {
      sorted[(uint8_t)j + 1] = sorted[(uint8_t)j];
      --j;
    }
    sorted[(uint8_t)j + 1] = key;
  }

  if ((windowCount_ & 1U) == 1U) {
    return sorted[windowCount_ / 2U];
  }
  return (sorted[(windowCount_ / 2U) - 1U] + sorted[windowCount_ / 2U]) * 0.5;
}

GpsData SmartGps::applyFilter(const GpsData& candidate, bool moving, uint32_t nowMs) const {
  GpsData filtered = candidate;
  const double medianLat = medianValue(latWindow_);
  const double medianLon = medianValue(lonWindow_);

  if (!hasLastGoodFix_) {
    filtered.lat = medianLat;
    filtered.lon = medianLon;
  } else {
    const float alpha = moving ? cfg::EMA_ALPHA_MOVE : cfg::EMA_ALPHA_STOP;
    filtered.lat = lastGoodFix_.lat + (medianLat - lastGoodFix_.lat) * alpha;
    filtered.lon = lastGoodFix_.lon + (medianLon - lastGoodFix_.lon) * alpha;
  }

  filtered.valid = true;
  filtered.filtered = true;
  filtered.locked = false;
  filtered.outlierDropped = false;
  filtered.sampleMs = nowMs;
  return filtered;
}

double SmartGps::haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  constexpr double kEarthRadiusM = 6371000.0;
  const double dLat = (lat2 - lat1) * DEG_TO_RAD;
  const double dLon = (lon2 - lon1) * DEG_TO_RAD;
  const double a =
      sin(dLat * 0.5) * sin(dLat * 0.5) +
      cos(lat1 * DEG_TO_RAD) * cos(lat2 * DEG_TO_RAD) *
          sin(dLon * 0.5) * sin(dLon * 0.5);
  return 2.0 * kEarthRadiusM * atan2(sqrt(a), sqrt(1.0 - a));
}

uint16_t SmartGps::crc16(const uint8_t* data, size_t len) {
  uint16_t crc = 0xFFFF;
  for (size_t i = 0; i < len; ++i) {
    crc ^= (uint16_t)data[i] << 8;
    for (uint8_t b = 0; b < 8; ++b) {
      if (crc & 0x8000) {
        crc = (uint16_t)((crc << 1) ^ 0x1021);
      } else {
        crc <<= 1;
      }
    }
  }
  return crc;
}
