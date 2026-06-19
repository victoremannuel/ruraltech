#pragma once

#include <Arduino.h>

namespace rtrv1 {

static inline uint32_t crc32(const uint8_t* data, size_t len) {
  uint32_t crc = 0xFFFFFFFFUL;
  if (!data && len != 0) return 0;
  for (size_t i = 0; i < len; ++i) {
    crc ^= static_cast<uint32_t>(data[i]);
    for (uint8_t bit = 0; bit < 8; ++bit) {
      const uint32_t lsb = crc & 1U;
      crc >>= 1U;
      if (lsb) crc ^= 0xEDB88320UL;
    }
  }
  return crc ^ 0xFFFFFFFFUL;
}

}  // namespace rtrv1
