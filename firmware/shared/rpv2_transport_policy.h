#pragma once

#include <stdint.h>

namespace rpv2transport {

constexpr uint8_t MAX_POINTS_FRAGMENT_ATTEMPTS = 3;
constexpr uint32_t STATUS_FLUSH_MAX_BACKOFF_MS = 30000UL;

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

inline uint32_t statusFlushBackoffMs(uint8_t attempts) {
  if (attempts <= 1) return 1000UL;
  if (attempts == 2) return 3000UL;
  if (attempts == 3) return 10000UL;
  return STATUS_FLUSH_MAX_BACKOFF_MS;
}

inline bool statusFlushDue(uint32_t nowMs, uint32_t nextAttemptAtMs) {
  return nextAttemptAtMs == 0 || deadlineReached(nowMs, nextAttemptAtMs);
}

inline bool statusFlushAllowed(
    bool radioCriticalActive,
    bool cloudEnabled,
    bool activeCommandAvailable,
    bool backhaulOpen,
    uint8_t queuedCount) {
  return !radioCriticalActive && cloudEnabled && activeCommandAvailable &&
         backhaulOpen && queuedCount > 0;
}

inline uint32_t scheduleStatusFlushRetry(
    uint8_t& attempts,
    uint32_t& nextAttemptAtMs,
    uint32_t nowMs) {
  if (attempts < UINT8_MAX) attempts++;
  const uint32_t backoffMs = statusFlushBackoffMs(attempts);
  nextAttemptAtMs = nowMs + backoffMs;
  return backoffMs;
}

inline bool statusFlushContextMatches(
    const char* itemCommandId,
    const char* activeCommandId) {
  if (!itemCommandId || !itemCommandId[0] ||
      !activeCommandId || !activeCommandId[0]) {
    return false;
  }
  const char* left = itemCommandId;
  const char* right = activeCommandId;
  while (*left && *right && *left == *right) {
    left++;
    right++;
  }
  return *left == '\0' && *right == '\0';
}

}  // namespace rpv2transport
