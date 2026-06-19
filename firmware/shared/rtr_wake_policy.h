#pragma once

#include <stdint.h>

namespace rtrwakepolicy {

inline uint32_t waitingUplinkTimeoutMs(
    uint32_t estimatedCycleMs,
    uint32_t floorMs,
    uint32_t marginMs) {
  const uint32_t dyn = estimatedCycleMs ? (estimatedCycleMs * 2u + marginMs) : 0u;
  return dyn > floorMs ? dyn : floorMs;
}

}  // namespace rtrwakepolicy
