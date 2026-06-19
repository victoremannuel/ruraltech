#pragma once

#include <stdint.h>

namespace rpv2transport {

constexpr uint8_t MAX_POINTS_FRAGMENT_ATTEMPTS = 3;
constexpr uint32_t STATUS_FLUSH_MAX_BACKOFF_MS = 30000UL;
constexpr uint8_t STATUS_FLUSH_NORMAL_BUDGET = 1;
constexpr uint8_t STATUS_FLUSH_MAX_BUDGET = 2;
constexpr uint32_t STATUS_FLUSH_MAX_SLICE_MS = 750UL;
constexpr uint32_t STATUS_FLUSH_MIN_GAP_MS = 250UL;

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

inline uint8_t clampStatusFlushBudget(uint8_t requestedBudget) {
  return requestedBudget > STATUS_FLUSH_MAX_BUDGET
             ? STATUS_FLUSH_MAX_BUDGET
             : requestedBudget;
}

inline bool statusFlushSliceExpired(uint32_t startedAtMs, uint32_t nowMs) {
  return static_cast<uint32_t>(nowMs - startedAtMs) >=
         STATUS_FLUSH_MAX_SLICE_MS;
}

inline bool statusFlushGapElapsed(uint32_t lastSliceAtMs, uint32_t nowMs) {
  return lastSliceAtMs == 0 ||
         static_cast<uint32_t>(nowMs - lastSliceAtMs) >=
             STATUS_FLUSH_MIN_GAP_MS;
}

inline uint8_t statusFlushPriority(bool terminal, bool activeCommandMatch) {
  if (activeCommandMatch) return terminal ? 0 : 1;
  return terminal ? 2 : 3;
}

inline bool statusTextEquals(const char* left, const char* right) {
  if (!left || !right) return false;
  while (*left && *right && *left == *right) {
    left++;
    right++;
  }
  return *left == '\0' && *right == '\0';
}

inline bool isCoalescableStatus(const char* status) {
  return statusTextEquals(status, "awaiting_begin_ack") ||
         statusTextEquals(status, "page_acked") ||
         statusTextEquals(status, "awaiting_points_ack") ||
         statusTextEquals(status, "points_retry_pending") ||
         statusTextEquals(status, "awaiting_commit_ack") ||
         statusTextEquals(status, "rpv2_begin_sent") ||
         statusTextEquals(status, "rpv2_commit_sent");
}

inline bool canReplaceQueuedStatus(bool incomingTerminal, bool queuedTerminal) {
  return incomingTerminal && !queuedTerminal;
}

inline bool shouldOpenCommitWindow(
    bool ackSent,
    bool sessionActive,
    bool stageComplete,
    uint16_t expectedFragment,
    uint16_t totalChunks) {
  return ackSent && sessionActive && stageComplete && totalChunks > 0 &&
         expectedFragment >= totalChunks;
}

inline bool shouldOpenFirstPointsWindow(
    bool beginAckSent,
    bool sessionActive,
    bool stageComplete,
    uint16_t expectedFragment,
    uint16_t totalChunks) {
  return beginAckSent && sessionActive && !stageComplete &&
         expectedFragment == 1 && totalChunks > 0;
}

inline bool commitSessionMatches(
    uint64_t expectedRadioCommandId,
    uint32_t expectedSessionNonce,
    uint64_t receivedRadioCommandId,
    uint32_t receivedSessionNonce) {
  return expectedRadioCommandId == receivedRadioCommandId &&
         expectedSessionNonce == receivedSessionNonce;
}

inline bool commitWaitExpired(
    bool sessionActive,
    bool stageComplete,
    bool waitingForCommit,
    uint32_t nowMs,
    uint32_t deadlineMs) {
  return sessionActive && stageComplete && waitingForCommit &&
         deadlineReached(nowMs, deadlineMs);
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
