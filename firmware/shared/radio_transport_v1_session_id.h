#pragma once

#include <Arduino.h>

namespace rtrv1 {

static inline uint64_t mix64(uint64_t value) {
  value ^= value >> 30;
  value *= 0xBF58476D1CE4E5B9ULL;
  value ^= value >> 27;
  value *= 0x94D049BB133111EBULL;
  value ^= value >> 31;
  return value;
}

static inline uint64_t makeSessionId(
    uint64_t logicalMessageId,
    uint32_t finalDestId,
    uint32_t entropy) {
  const uint64_t combined =
      logicalMessageId ^
      (static_cast<uint64_t>(finalDestId) << 32) ^
      static_cast<uint64_t>(entropy) ^
      0xA55A39F00D71A11DULL;
  return mix64(combined);
}

}  // namespace rtrv1
