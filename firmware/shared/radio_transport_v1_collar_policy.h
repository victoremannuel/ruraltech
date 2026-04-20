#pragma once

#include <Arduino.h>

namespace rtrv1 {

static inline uint32_t discoveryWindowMs(
    bool benchExtendedEnabled,
    uint32_t normalMs,
    uint32_t benchMs) {
  return benchExtendedEnabled ? benchMs : normalMs;
}

static inline bool shouldOpenSecondaryRxWindow(
    bool firstWindowHandled,
    bool sessionModeActive) {
  return !firstWindowHandled && !sessionModeActive;
}

}  // namespace rtrv1
