#pragma once

#include <Arduino.h>
#include "radio_transport_v1_constants.h"

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

static inline bool shouldHoldSleepForRetryGrace(
    uint32_t nowMs,
    uint32_t lastUplinkAtMs,
    bool anyDownlinkHandled,
    bool sessionModeActive,
    uint32_t graceWindowMs) {
  if (anyDownlinkHandled || sessionModeActive || lastUplinkAtMs == 0 || graceWindowMs == 0) {
    return false;
  }
  return (uint32_t)(nowMs - lastUplinkAtMs) < graceWindowMs;
}

static inline uint32_t remainingSleepGraceMs(
    uint32_t nowMs,
    uint32_t lastUplinkAtMs,
    uint32_t graceWindowMs) {
  if (lastUplinkAtMs == 0 || graceWindowMs == 0) return 0;
  const uint32_t elapsedMs = nowMs - lastUplinkAtMs;
  if (elapsedMs >= graceWindowMs) return 0;
  return graceWindowMs - elapsedMs;
}

}  // namespace rtrv1
