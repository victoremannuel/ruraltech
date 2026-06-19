#pragma once

#include <Arduino.h>

namespace rpv2 {

struct EncodedPoint {
  int32_t latE7 = 0;
  int32_t lonE7 = 0;
};

static inline uint32_t crc32Update(uint32_t crc, uint8_t data) {
  crc ^= data;
  for (uint8_t i = 0; i < 8; ++i) {
    const uint32_t mask = -(crc & 1U);
    crc = (crc >> 1) ^ (0xEDB88320UL & mask);
  }
  return crc;
}

static inline uint32_t crc32Fence(const EncodedPoint* points, uint16_t count) {
  uint32_t crc = 0xFFFFFFFFUL;
  crc = crc32Update(crc, static_cast<uint8_t>(count & 0xFF));
  crc = crc32Update(crc, static_cast<uint8_t>((count >> 8) & 0xFF));
  for (uint16_t i = 0; i < count; ++i) {
    const uint8_t* lat = reinterpret_cast<const uint8_t*>(&points[i].latE7);
    const uint8_t* lon = reinterpret_cast<const uint8_t*>(&points[i].lonE7);
    for (uint8_t j = 0; j < 4; ++j) crc = crc32Update(crc, lat[j]);
    for (uint8_t j = 0; j < 4; ++j) crc = crc32Update(crc, lon[j]);
  }
  return crc ^ 0xFFFFFFFFUL;
}

}  // namespace rpv2
