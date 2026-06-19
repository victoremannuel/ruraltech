#pragma once

#include <stdint.h>

namespace rpv2fencecrc {

struct FencePointE7 {
  int32_t latE7 = 0;
  int32_t lonE7 = 0;
};

static inline uint32_t updateByte(uint32_t crc, uint8_t data) {
  crc ^= data;
  for (uint8_t i = 0; i < 8; ++i) {
    const uint32_t mask = 0U - (crc & 1U);
    crc = (crc >> 1) ^ (0xEDB88320UL & mask);
  }
  return crc;
}

static inline uint32_t updateU16Le(uint32_t crc, uint16_t value) {
  crc = updateByte(crc, static_cast<uint8_t>(value & 0xFFU));
  return updateByte(crc, static_cast<uint8_t>((value >> 8) & 0xFFU));
}

static inline uint32_t updateI32Le(uint32_t crc, int32_t value) {
  const uint32_t bits = static_cast<uint32_t>(value);
  for (uint8_t shift = 0; shift < 32; shift += 8) {
    crc = updateByte(crc, static_cast<uint8_t>((bits >> shift) & 0xFFU));
  }
  return crc;
}

static inline uint32_t computeCanonicalFenceCrc(
    const FencePointE7* points,
    uint16_t count) {
  if (!points && count != 0) return 0;
  uint32_t crc = updateU16Le(0xFFFFFFFFUL, count);
  for (uint16_t i = 0; i < count; ++i) {
    crc = updateI32Le(crc, points[i].latE7);
    crc = updateI32Le(crc, points[i].lonE7);
  }
  return crc ^ 0xFFFFFFFFUL;
}

}  // namespace rpv2fencecrc
