#pragma once

#include <Arduino.h>
#include "../firmware/shared/radio_transport_v1_constants.h"

namespace rtrwake {

enum class State : uint8_t {
  IDLE = 0,
  PAGING_WAITING_UPLINK = 1,
  PAGING_READY_TO_SEND = 2,
  PAGING_AWAITING_ACK = 3,
  PAGE_ACKED = 4,
  SESSION_START_READY = 5,
  SESSION_IN_PROGRESS = 6,
  COMPLETED = 7,
  FAILED = 8,
};

struct Presence {
  uint32_t deviceId = 0;
  uint32_t lastSeenAtMs = 0;
  uint32_t estimatedCycleMs = 0;
  bool valid = false;
};

struct SessionCore {
  bool active = false;
  State state = State::IDLE;
  uint32_t deviceId = 0;
  uint32_t uplinkSeq = 0;
  uint64_t pageSessionId = 0;
  uint32_t pageMessageId = 0;
  uint8_t campaignCount = 0;
  uint8_t maxCampaigns = 2;
  uint32_t createdAtMs = 0;
  uint32_t lastUplinkAtMs = 0;
  uint32_t predictedWakeAtMs = 0;
  uint32_t nextPageAttemptAtMs = 0;
  uint32_t lastPageSentAtMs = 0;
  uint32_t pageAckDeadlineAtMs = 0;
  bool pageSent = false;
  bool pageAcked = false;
  bool cloudTxDeferred = false;
  bool sessionStarted = false;
  bool finished = false;
};

struct FastPathMetric {
  bool valid = false;
  uint32_t rxAcceptedAtMs = 0;
  uint32_t pageTxAtMs = 0;
  uint32_t deltaMs = 0;
  bool deadlineMet = false;
};

static inline const char* stateLabel(State state) {
  switch (state) {
    case State::IDLE: return "idle";
    case State::PAGING_WAITING_UPLINK: return "paging_waiting_uplink";
    case State::PAGING_READY_TO_SEND: return "paging_ready_to_send";
    case State::PAGING_AWAITING_ACK: return "paging_awaiting_ack";
    case State::PAGE_ACKED: return "page_acked";
    case State::SESSION_START_READY: return "session_start_ready";
    case State::SESSION_IN_PROGRESS: return "session_in_progress";
    case State::COMPLETED: return "completed";
    case State::FAILED: return "failed";
    default: return "unknown";
  }
}

static inline void updatePresence(
    Presence* presence,
    uint32_t deviceId,
    uint32_t nowMs) {
  if (!presence) return;
  if (!presence->valid || presence->deviceId != deviceId) {
    presence->deviceId = deviceId;
    presence->lastSeenAtMs = nowMs;
    presence->estimatedCycleMs = 0;
    presence->valid = true;
    return;
  }
  if (presence->lastSeenAtMs != 0 && nowMs > presence->lastSeenAtMs) {
    presence->estimatedCycleMs = nowMs - presence->lastSeenAtMs;
  }
  presence->lastSeenAtMs = nowMs;
}

static inline bool noteUplinkHint(
    SessionCore* session,
    uint32_t deviceId,
    uint32_t nowMs) {
  if (!session || !session->active || session->deviceId != deviceId) return false;
  session->lastUplinkAtMs = nowMs;
  session->nextPageAttemptAtMs = nowMs;
  session->cloudTxDeferred = true;
  if (session->state == State::PAGING_WAITING_UPLINK ||
      session->state == State::PAGING_READY_TO_SEND) {
    session->state = State::PAGING_READY_TO_SEND;
    return true;
  }
  return false;
}

static inline bool predictedWakeReady(
    const SessionCore& session,
    uint32_t nowMs) {
  return session.active &&
      session.state == State::PAGING_WAITING_UPLINK &&
      session.predictedWakeAtMs != 0 &&
      (int32_t)(nowMs - session.predictedWakeAtMs) >= 0;
}

static inline void markPageAttempt(
    SessionCore* session,
    uint32_t nowMs,
    uint32_t ackTimeoutMs) {
  if (!session) return;
  if (session->campaignCount < 0xFF) session->campaignCount++;
  session->pageSent = true;
  session->pageAcked = false;
  session->lastPageSentAtMs = nowMs;
  session->pageAckDeadlineAtMs = nowMs + ackTimeoutMs;
}

static inline bool pageAckMatches(
    const SessionCore& session,
    uint32_t deviceId,
    uint64_t pageSessionId,
    uint32_t pageMessageId) {
  return session.active &&
      session.deviceId == deviceId &&
      session.pageSessionId == pageSessionId &&
      session.pageMessageId == pageMessageId;
}

static inline void markPageAcked(SessionCore* session) {
  if (!session) return;
  session->pageAcked = true;
  session->pageSent = false;
  session->pageAckDeadlineAtMs = 0;
  session->state = State::PAGE_ACKED;
}

static inline bool pageAckTimedOut(
    const SessionCore& session,
    uint32_t nowMs) {
  return session.active &&
      session.state == State::PAGING_AWAITING_ACK &&
      session.pageAckDeadlineAtMs != 0 &&
      (int32_t)(nowMs - session.pageAckDeadlineAtMs) >= 0;
}

static inline bool canRetryAfterTimeout(const SessionCore& session) {
  return session.campaignCount < session.maxCampaigns;
}

static inline void scheduleRetryWaitingUplink(
    SessionCore* session,
    uint32_t nowMs) {
  if (!session) return;
  session->pageSent = false;
  session->pageAcked = false;
  session->pageAckDeadlineAtMs = 0;
  session->nextPageAttemptAtMs = nowMs;
  session->cloudTxDeferred = false;
  session->state = State::PAGING_WAITING_UPLINK;
}

static inline FastPathMetric computeFastPathMetric(
    const SessionCore& session,
    uint32_t deadlineMs) {
  FastPathMetric metric{};
  if (session.lastUplinkAtMs == 0 || session.lastPageSentAtMs == 0) return metric;
  if ((int32_t)(session.lastPageSentAtMs - session.lastUplinkAtMs) < 0) return metric;
  metric.valid = true;
  metric.rxAcceptedAtMs = session.lastUplinkAtMs;
  metric.pageTxAtMs = session.lastPageSentAtMs;
  metric.deltaMs = session.lastPageSentAtMs - session.lastUplinkAtMs;
  metric.deadlineMet = metric.deltaMs <= deadlineMs;
  return metric;
}

static inline bool shouldDeferCloudTx(
    const SessionCore& session,
    uint32_t deviceId) {
  return session.active &&
      session.deviceId == deviceId &&
      (session.state == State::PAGING_WAITING_UPLINK ||
       session.state == State::PAGING_READY_TO_SEND);
}

static inline const char* aggregateCommandStatus(
    bool allTerminal,
    bool anyFailed,
    bool anyPendingWake) {
  if (allTerminal) return anyFailed ? "failed" : "completed";
  if (anyPendingWake) return "paging_waiting_uplink";
  return "dispatching";
}

}  // namespace rtrwake
