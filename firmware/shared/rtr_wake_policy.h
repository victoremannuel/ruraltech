#pragma once

#include <stdint.h>
#include <limits.h>

namespace rtrwakepolicy {

inline uint32_t waitingUplinkTimeoutMs(
    uint32_t estimatedCycleMs,
    uint32_t floorMs,
    uint32_t marginMs) {
  if (estimatedCycleMs == 0) return floorMs;
  const uint64_t dynamic64 =
      static_cast<uint64_t>(estimatedCycleMs) * 2ULL + marginMs;
  const uint32_t dyn =
      dynamic64 > UINT32_MAX ? UINT32_MAX : static_cast<uint32_t>(dynamic64);
  return dyn > floorMs ? dyn : floorMs;
}

}  // namespace rtrwakepolicy
