#pragma once

#include <stdint.h>

namespace rpv2transport {

constexpr uint8_t MAX_POINTS_FRAGMENT_ATTEMPTS = 3;

inline bool isImmediatelyPreviousFragment(
    uint16_t receivedFragment,
    uint16_t expectedFragment) {
  return static_cast<uint16_t>(receivedFragment + 1U) == expectedFragment;
}

inline bool acceptedRangeEndsAt(
    uint16_t startPointIndex,
    uint16_t pointCount,
    uint16_t nextPointIndex) {
  return static_cast<uint16_t>(startPointIndex + pointCount) == nextPointIndex;
}

inline bool shouldRetryFragment(uint8_t attempt) {
  return attempt < MAX_POINTS_FRAGMENT_ATTEMPTS;
}

inline bool deadlineReached(uint32_t nowMs, uint32_t deadlineMs) {
  return static_cast<int32_t>(nowMs - deadlineMs) >= 0;
}

}  // namespace rpv2transport
