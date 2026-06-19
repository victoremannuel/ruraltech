#pragma once

#include "rpv2_fence_crc.h"

namespace rpv2 {

using EncodedPoint = rpv2fencecrc::FencePointE7;

static inline uint32_t crc32Fence(const EncodedPoint* points, uint16_t count) {
  return rpv2fencecrc::computeCanonicalFenceCrc(points, count);
}

}  // namespace rpv2
