#pragma once

#include <Arduino.h>
#include "../firmware/shared/radio_transport_v1_constants.h"

namespace rtrwake {

enum class State : uint8_t {
  IDLE = 0,
  PAGING_WAITING_UPLINK = 1,
  PAGING_READY_TO_SEND = 2,
  PAGING_AWAITING_ACK = 3,
  PAGING_RETRY_GRACE = 4,
  PAGE_ACKED = 5,
  SESSION_START_READY = 6,
  SESSION_IN_PROGRESS = 7,
  COMPLETED = 8,
  FAILED = 9,
};

struct Presence {
  uint32_t deviceId = 0;
  uint32_t lastSeenAtMs = 0;
  uint32_t estimatedCycleMs = 0;
  bool valid = false;
};

struct SessionCore {
  struct InFlightPageAttempt {
    bool valid = false;
    bool pageSent = false;
    bool ackAccepted = false;
    bool expired = false;
    bool cancelledByRetry = false;
    uint64_t sessionId = 0;
    uint32_t messageId = 0;
    uint8_t campaignCount = 0;
    uint32_t sentAtMs = 0;
    uint32_t softDeadlineAtMs = 0;
    uint32_t hardDeadlineAtMs = 0;
  };

  struct ScheduledRetry {
    bool pending = false;
    uint32_t retryAtMs = 0;
    uint8_t nextCampaignCount = 0;
    uint32_t graceMs = 0;
    const char* reason = nullptr;
  };

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
  bool beginDispatchPending = false;
  bool sessionStarted = false;
  bool finished = false;
  InFlightPageAttempt inFlightPage{};
  ScheduledRetry scheduledRetry{};
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
    case State::PAGING_RETRY_GRACE: return "paging_retry_grace";
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
  session->scheduledRetry = SessionCore::ScheduledRetry{};
  session->inFlightPage.valid = true;
  session->inFlightPage.pageSent = true;
  session->inFlightPage.ackAccepted = false;
  session->inFlightPage.expired = false;
  session->inFlightPage.cancelledByRetry = false;
  session->inFlightPage.sessionId = session->pageSessionId;
  session->inFlightPage.messageId = session->pageMessageId;
  session->inFlightPage.campaignCount = session->campaignCount;
  session->inFlightPage.sentAtMs = nowMs;
  session->inFlightPage.softDeadlineAtMs = nowMs + ackTimeoutMs;
  session->inFlightPage.hardDeadlineAtMs =
      session->inFlightPage.softDeadlineAtMs + rtrv1::PAGE_RETRY_GRACE_MS;
}

static inline bool pageAckMatches(
    const SessionCore& session,
    uint32_t deviceId,
    uint64_t pageSessionId,
    uint32_t pageMessageId) {
  return session.active &&
      session.deviceId == deviceId &&
      ((session.inFlightPage.valid &&
        session.inFlightPage.sessionId == pageSessionId &&
        session.inFlightPage.messageId == pageMessageId) ||
       (session.pageSessionId == pageSessionId &&
        session.pageMessageId == pageMessageId));
}

static inline void markPageAcked(SessionCore* session) {
  if (!session) return;
  session->pageAcked = true;
  session->pageSent = false;
  session->pageAckDeadlineAtMs = 0;
  session->inFlightPage.ackAccepted = true;
  session->scheduledRetry = SessionCore::ScheduledRetry{};
  session->state = State::PAGE_ACKED;
}

static inline bool inFlightAttemptSoftTimedOut(
    const SessionCore& session,
    uint32_t nowMs) {
  return session.active &&
      session.state == State::PAGING_AWAITING_ACK &&
      session.inFlightPage.valid &&
      session.inFlightPage.pageSent &&
      session.inFlightPage.softDeadlineAtMs != 0 &&
      !session.scheduledRetry.pending &&
      (int32_t)(nowMs - session.inFlightPage.softDeadlineAtMs) >= 0;
}

static inline bool inFlightAttemptHardTimedOut(
    const SessionCore& session,
    uint32_t nowMs) {
  return session.active &&
      (session.state == State::PAGING_AWAITING_ACK ||
       session.state == State::PAGING_RETRY_GRACE) &&
      session.inFlightPage.valid &&
      session.inFlightPage.pageSent &&
      session.inFlightPage.hardDeadlineAtMs != 0 &&
      !session.inFlightPage.ackAccepted &&
      (int32_t)(nowMs - session.inFlightPage.hardDeadlineAtMs) >= 0;
}

static inline bool awaitingAckWithoutPageSent(const SessionCore& session) {
  return session.active &&
      session.state == State::PAGING_AWAITING_ACK &&
      (!session.pageSent || session.lastPageSentAtMs == 0 || session.pageAckDeadlineAtMs == 0);
}

static inline bool canConsumePageAckFastPath(const SessionCore& session) {
  return session.active &&
      (session.state == State::PAGING_AWAITING_ACK ||
       session.state == State::PAGING_RETRY_GRACE) &&
      session.inFlightPage.valid &&
      session.inFlightPage.pageSent &&
      session.inFlightPage.sentAtMs != 0;
}

static inline bool isLatePageAck(
    const SessionCore& session,
    uint32_t nowMs) {
  return pageAckMatches(
             session,
             session.deviceId,
             session.pageSessionId,
             session.pageMessageId) &&
      session.active &&
      session.inFlightPage.valid &&
      session.inFlightPage.hardDeadlineAtMs != 0 &&
      (int32_t)(nowMs - session.inFlightPage.hardDeadlineAtMs) > 0;
}

static inline bool canRetryAfterTimeout(const SessionCore& session) {
  return session.campaignCount < session.maxCampaigns;
}

static inline void scheduleRetryReadyToSend(
    SessionCore* session,
    uint32_t nowMs,
    uint32_t graceMs) {
  if (!session) return;
  session->pageAcked = false;
  session->scheduledRetry.pending = true;
  session->scheduledRetry.retryAtMs = nowMs + graceMs;
  session->scheduledRetry.nextCampaignCount =
      session->campaignCount < 0xFF ? static_cast<uint8_t>(session->campaignCount + 1)
                                    : session->campaignCount;
  session->scheduledRetry.graceMs = graceMs;
  session->scheduledRetry.reason = "soft_timeout";
  session->cloudTxDeferred = true;
  session->state = State::PAGING_RETRY_GRACE;
}

static inline bool retryReadyToSend(
    const SessionCore& session,
    uint32_t nowMs) {
  return session.active &&
      session.state == State::PAGING_RETRY_GRACE &&
      session.scheduledRetry.pending &&
      session.scheduledRetry.retryAtMs != 0 &&
      !session.inFlightPage.valid &&
      (int32_t)(nowMs - session.scheduledRetry.retryAtMs) >= 0;
}

static inline void expireInFlightAttempt(SessionCore* session) {
  if (!session) return;
  session->inFlightPage.valid = false;
  session->inFlightPage.expired = true;
  session->pageSent = false;
  session->pageAckDeadlineAtMs = 0;
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
       session.state == State::PAGING_READY_TO_SEND ||
       session.state == State::PAGING_RETRY_GRACE);
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
