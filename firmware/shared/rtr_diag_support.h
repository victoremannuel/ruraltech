#pragma once

#include <stddef.h>
#include <stdint.h>
#include <string.h>

namespace rtrdiag {

static constexpr size_t kHeadHexSize = 17;
static constexpr size_t kNonceHexSize = 25;
static constexpr size_t kTagHexSize = 17;
static constexpr size_t kReasonSize = 32;
static constexpr size_t kStateSize = 24;
static constexpr size_t kOutcomeSize = 20;
static constexpr size_t kPatternHexSize = 17;
static constexpr size_t kWakeStageSize = 32;

struct DecryptFailSnapshot {
  uint32_t atMs = 0;
  uint32_t count = 0;
  uint16_t len = 0;
  int16_t rssi = 0;
  float snr = 0.0f;
  uint16_t irqFlags = 0;
  char radioState[kStateSize]{};
  char reason[kReasonSize]{};
  char headHex[kHeadHexSize]{};
  char nonceHex[kNonceHexSize]{};
  char tagHex[kTagHexSize]{};
};

struct RawRxSnapshot {
  uint32_t rawRxSeenCount = 0;
  uint32_t rawRxNoiseDropCount = 0;
  uint32_t rawRxInvalidPatternDropCount = 0;
  uint32_t rawRxDecryptAttemptCount = 0;
  uint32_t rawRxDecryptFailedCount = 0;
  uint32_t rawRxAcceptedCount = 0;
  uint16_t lastRawCandidateLen = 0;
  int16_t lastRawCandidateRssi = 0;
  float lastRawCandidateSnr = 0.0f;
  char lastRawNoiseReason[kReasonSize]{};
  char lastRawPatternHex[kPatternHexSize]{};
};

struct WakeLoopSnapshot {
  uint32_t lastWakeLoopStageAtMs = 0;
  uint64_t lastWakeLoopStageSessionId = 0;
  uint32_t lastWakeLoopStageDeviceId = 0;
  uint32_t wakeLoopIterationCount = 0;
  uint32_t wakeLoopBudgetHitCount = 0;
  uint32_t wakeLoopYieldCount = 0;
  uint32_t lastSoftTimeoutAtMs = 0;
  uint32_t lastRetryScheduleAtMs = 0;
  uint32_t lastBeginDispatchAtMs = 0;
  char lastWakeLoopStage[kWakeStageSize]{};
};

struct PageSnapshot {
  uint32_t lastWakeHintAtMs = 0;
  uint32_t lastWakeHintSeq = 0;
  uint32_t lastImmediateEnterAtMs = 0;
  uint32_t lastImmediateResultAtMs = 0;
  uint32_t lastImmediateDeviceId = 0;
  uint32_t lastImmediateUplinkSeq = 0;
  uint32_t lastImmediateAgeMs = 0;
  uint32_t lastPageTargetDeviceId = 0;
  uint64_t lastPageSessionId = 0;
  uint32_t lastPageMessageId = 0;
  uint32_t lastPageSentAtMs = 0;
  uint32_t lastPageAckDeadlineAtMs = 0;
  uint32_t lastPageRetryAtMs = 0;
  uint32_t lastWakeToPageLatencyMs = 0;
  uint32_t lastSoftDeadlineMs = 0;
  uint64_t inFlightPageSessionId = 0;
  uint32_t inFlightPageMessageId = 0;
  uint32_t inFlightPageSentAtMs = 0;
  uint32_t inFlightPageSoftDeadlineAtMs = 0;
  uint32_t inFlightPageHardDeadlineAtMs = 0;
  uint32_t retryAtMs = 0;
  uint8_t lastPageCampaignCount = 0;
  uint8_t inFlightPageCampaignCount = 0;
  uint8_t retryCampaignCount = 0;
  bool lastWakeHintAccepted = false;
  bool lastSoftDeadlineMet = false;
  bool inFlightPageValid = false;
  bool inFlightPageAckAccepted = false;
  bool retryPending = false;
  bool lastAckMatchedInGrace = false;
  bool lastCloudDeferredForPage = false;
  char lastImmediateResult[kOutcomeSize] = "none";
  char lastOrderViolation[kReasonSize] = "none";
  char lastPageOutcome[kOutcomeSize] = "none";
  char lastAckRejectedReason[kReasonSize]{};
};

struct CollarWindowSnapshot {
  uint32_t discoveryWindowOpenCount = 0;
  uint32_t secondaryWindowOpenCount = 0;
  uint32_t lastDiscoveryWindowOpenAtMs = 0;
  uint32_t lastSecondaryWindowOpenAtMs = 0;
  uint32_t lastDownlinkRawSeenAtMs = 0;
  uint32_t lastPageRxAtMs = 0;
  uint32_t lastPageAckTxAtMs = 0;
  uint32_t lastWindowCloseAtMs = 0;
  uint32_t lastSleepGraceHoldAtMs = 0;
  uint32_t rawDownlinkSeenCount = 0;
  uint32_t rawDownlinkAcceptedCount = 0;
  uint32_t rawDownlinkRejectedCount = 0;
  uint32_t pageRxCount = 0;
  uint32_t sleepGraceHoldCount = 0;
  uint16_t lastDownlinkRawLen = 0;
  int16_t lastDownlinkRawRssi = 0;
  float lastDownlinkRawSnr = 0.0f;
  uint8_t lastDownlinkRawMsgType = 0;
  uint32_t lastDiscoveryWindowMs = 0;
  uint32_t lastSecondaryWindowMs = 0;
  uint32_t lastSleepGraceWindowMs = 0;
  bool lastWindowHandled = false;
  char lastDownlinkDropReason[kReasonSize]{};
};

static inline void copyText(char* dst, size_t dstSize, const char* src) {
  if (!dst || dstSize == 0) return;
  if (!src) {
    dst[0] = '\0';
    return;
  }
  strncpy(dst, src, dstSize - 1);
  dst[dstSize - 1] = '\0';
}

static inline bool hasExtremeRepeatedPrefix(
    const uint8_t* data,
    size_t len,
    size_t inspectLen = 12) {
  if (!data || len == 0) return false;
  const size_t capped = len < inspectLen ? len : inspectLen;
  if (capped < 8) return false;
  const uint8_t first = data[0];
  for (size_t i = 1; i < capped; ++i) {
    if (data[i] != first) return false;
  }
  return true;
}

static inline bool looksLikeRawNoise(
    uint16_t len,
    int16_t rssi,
    float snr,
    const uint8_t* data,
    size_t dataLen) {
  if (len < 28) return true;
  if (rssi <= -127 && snr == 0.0f && hasExtremeRepeatedPrefix(data, dataLen, 16)) {
    return true;
  }
  return false;
}

static inline bool looksLikeInvalidRepeatedPattern(
    const uint8_t* nonce,
    size_t nonceLen,
    const uint8_t* cipher,
    size_t cipherLen,
    const uint8_t* tag,
    size_t tagLen) {
  return hasExtremeRepeatedPrefix(nonce, nonceLen, 12) &&
      hasExtremeRepeatedPrefix(cipher, cipherLen, 8) &&
      hasExtremeRepeatedPrefix(tag, tagLen, 8);
}

static inline void noteRawRxSeen(
    RawRxSnapshot* snapshot,
    uint16_t len,
    int16_t rssi,
    float snr) {
  if (!snapshot) return;
  snapshot->rawRxSeenCount++;
  snapshot->lastRawCandidateLen = len;
  snapshot->lastRawCandidateRssi = rssi;
  snapshot->lastRawCandidateSnr = snr;
}

static inline void noteRawNoiseDrop(
    RawRxSnapshot* snapshot,
    const char* reason,
    const char* patternHex) {
  if (!snapshot) return;
  snapshot->rawRxNoiseDropCount++;
  copyText(snapshot->lastRawNoiseReason, sizeof(snapshot->lastRawNoiseReason), reason);
  copyText(snapshot->lastRawPatternHex, sizeof(snapshot->lastRawPatternHex), patternHex);
}

static inline void noteRawPatternDrop(
    RawRxSnapshot* snapshot,
    const char* reason,
    const char* patternHex) {
  if (!snapshot) return;
  snapshot->rawRxInvalidPatternDropCount++;
  copyText(snapshot->lastRawNoiseReason, sizeof(snapshot->lastRawNoiseReason), reason);
  copyText(snapshot->lastRawPatternHex, sizeof(snapshot->lastRawPatternHex), patternHex);
}

static inline void noteRawDecryptAttempt(RawRxSnapshot* snapshot) {
  if (!snapshot) return;
  snapshot->rawRxDecryptAttemptCount++;
}

static inline void noteRawDecryptFailed(RawRxSnapshot* snapshot) {
  if (!snapshot) return;
  snapshot->rawRxDecryptFailedCount++;
}

static inline void noteRawAccepted(RawRxSnapshot* snapshot) {
  if (!snapshot) return;
  snapshot->rawRxAcceptedCount++;
}

static inline void noteWakeLoopStage(
    WakeLoopSnapshot* snapshot,
    const char* stage,
    uint32_t atMs,
    uint64_t sessionId,
    uint32_t deviceId) {
  if (!snapshot) return;
  snapshot->lastWakeLoopStageAtMs = atMs;
  snapshot->lastWakeLoopStageSessionId = sessionId;
  snapshot->lastWakeLoopStageDeviceId = deviceId;
  copyText(snapshot->lastWakeLoopStage, sizeof(snapshot->lastWakeLoopStage), stage);
}

static inline void noteDecryptFail(
    DecryptFailSnapshot* snapshot,
    uint32_t atMs,
    uint32_t count,
    uint16_t len,
    int16_t rssi,
    float snr,
    uint16_t irqFlags,
    const char* radioState,
    const char* reason,
    const char* headHex,
    const char* nonceHex,
    const char* tagHex) {
  if (!snapshot) return;
  snapshot->atMs = atMs;
  snapshot->count = count;
  snapshot->len = len;
  snapshot->rssi = rssi;
  snapshot->snr = snr;
  snapshot->irqFlags = irqFlags;
  copyText(snapshot->radioState, sizeof(snapshot->radioState), radioState);
  copyText(snapshot->reason, sizeof(snapshot->reason), reason);
  copyText(snapshot->headHex, sizeof(snapshot->headHex), headHex);
  copyText(snapshot->nonceHex, sizeof(snapshot->nonceHex), nonceHex);
  copyText(snapshot->tagHex, sizeof(snapshot->tagHex), tagHex);
}

static inline void noteWakeHint(
    PageSnapshot* snapshot,
    uint32_t atMs,
    uint32_t seq,
    bool accepted) {
  if (!snapshot) return;
  snapshot->lastWakeHintAtMs = atMs;
  snapshot->lastWakeHintSeq = seq;
  snapshot->lastWakeHintAccepted = accepted;
}

static inline void noteImmediateEnter(
    PageSnapshot* snapshot,
    uint32_t atMs,
    uint32_t deviceId,
    uint32_t uplinkSeq) {
  if (!snapshot) return;
  snapshot->lastImmediateEnterAtMs = atMs;
  snapshot->lastImmediateDeviceId = deviceId;
  snapshot->lastImmediateUplinkSeq = uplinkSeq;
}

static inline void noteImmediateResult(
    PageSnapshot* snapshot,
    uint32_t atMs,
    uint32_t deviceId,
    uint32_t uplinkSeq,
    uint32_t ageMs,
    const char* result,
    bool cloudDeferred) {
  if (!snapshot) return;
  snapshot->lastImmediateResultAtMs = atMs;
  snapshot->lastImmediateDeviceId = deviceId;
  snapshot->lastImmediateUplinkSeq = uplinkSeq;
  snapshot->lastImmediateAgeMs = ageMs;
  snapshot->lastCloudDeferredForPage = cloudDeferred;
  copyText(
      snapshot->lastImmediateResult,
      sizeof(snapshot->lastImmediateResult),
      result && result[0] ? result : "unknown");
}

static inline void noteOrderViolation(PageSnapshot* snapshot, const char* reason) {
  if (!snapshot) return;
  copyText(
      snapshot->lastOrderViolation,
      sizeof(snapshot->lastOrderViolation),
      reason && reason[0] ? reason : "unknown");
}

static inline void notePageTx(
    PageSnapshot* snapshot,
    uint32_t deviceId,
    uint64_t sessionId,
    uint32_t messageId,
    uint8_t campaignCount,
    uint32_t sentAtMs,
    uint32_t ackDeadlineAtMs) {
  if (!snapshot) return;
  snapshot->lastPageTargetDeviceId = deviceId;
  snapshot->lastPageSessionId = sessionId;
  snapshot->lastPageMessageId = messageId;
  snapshot->lastPageCampaignCount = campaignCount;
  snapshot->lastPageSentAtMs = sentAtMs;
  snapshot->lastPageAckDeadlineAtMs = ackDeadlineAtMs;
  snapshot->inFlightPageValid = true;
  snapshot->inFlightPageSessionId = sessionId;
  snapshot->inFlightPageMessageId = messageId;
  snapshot->inFlightPageCampaignCount = campaignCount;
  snapshot->inFlightPageSentAtMs = sentAtMs;
  snapshot->inFlightPageAckAccepted = false;
  snapshot->retryPending = false;
  snapshot->retryAtMs = 0;
  snapshot->retryCampaignCount = 0;
  snapshot->lastAckMatchedInGrace = false;
  snapshot->lastAckRejectedReason[0] = '\0';
  copyText(snapshot->lastPageOutcome, sizeof(snapshot->lastPageOutcome), "tx_ok");
}

static inline void notePageOutcome(PageSnapshot* snapshot, const char* outcome) {
  if (!snapshot) return;
  copyText(snapshot->lastPageOutcome, sizeof(snapshot->lastPageOutcome), outcome);
}

static inline void notePageLatency(
    PageSnapshot* snapshot,
    uint32_t deltaMs,
    uint32_t softDeadlineMs,
    bool deadlineMet) {
  if (!snapshot) return;
  snapshot->lastWakeToPageLatencyMs = deltaMs;
  snapshot->lastSoftDeadlineMs = softDeadlineMs;
  snapshot->lastSoftDeadlineMet = deadlineMet;
}

static inline void notePageRetry(
    PageSnapshot* snapshot,
    uint32_t retryAtMs,
    uint8_t retryCampaignCount,
    const char* outcome) {
  if (!snapshot) return;
  snapshot->lastPageRetryAtMs = retryAtMs;
  snapshot->retryPending = true;
  snapshot->retryAtMs = retryAtMs;
  snapshot->retryCampaignCount = retryCampaignCount;
  if (outcome && outcome[0]) {
    copyText(snapshot->lastPageOutcome, sizeof(snapshot->lastPageOutcome), outcome);
  }
}

static inline void noteInFlightPageContext(
    PageSnapshot* snapshot,
    bool valid,
    uint64_t sessionId,
    uint32_t messageId,
    uint8_t campaignCount,
    uint32_t sentAtMs,
    uint32_t softDeadlineAtMs,
    uint32_t hardDeadlineAtMs,
    bool ackAccepted) {
  if (!snapshot) return;
  snapshot->inFlightPageValid = valid;
  snapshot->inFlightPageSessionId = sessionId;
  snapshot->inFlightPageMessageId = messageId;
  snapshot->inFlightPageCampaignCount = campaignCount;
  snapshot->inFlightPageSentAtMs = sentAtMs;
  snapshot->inFlightPageSoftDeadlineAtMs = softDeadlineAtMs;
  snapshot->inFlightPageHardDeadlineAtMs = hardDeadlineAtMs;
  snapshot->inFlightPageAckAccepted = ackAccepted;
}

static inline void noteAckMatched(PageSnapshot* snapshot, bool matchedInGrace) {
  if (!snapshot) return;
  snapshot->inFlightPageAckAccepted = true;
  snapshot->lastAckMatchedInGrace = matchedInGrace;
  snapshot->retryPending = false;
  snapshot->retryAtMs = 0;
  snapshot->retryCampaignCount = 0;
  snapshot->lastAckRejectedReason[0] = '\0';
}

static inline void noteAckRejected(PageSnapshot* snapshot, const char* reason) {
  if (!snapshot) return;
  copyText(
      snapshot->lastAckRejectedReason,
      sizeof(snapshot->lastAckRejectedReason),
      reason);
}

static inline void noteDiscoveryWindowOpen(
    CollarWindowSnapshot* snapshot,
    bool secondary,
    uint32_t atMs,
    uint32_t windowMs) {
  if (!snapshot) return;
  if (secondary) {
    snapshot->secondaryWindowOpenCount++;
    snapshot->lastSecondaryWindowOpenAtMs = atMs;
    snapshot->lastSecondaryWindowMs = windowMs;
  } else {
    snapshot->discoveryWindowOpenCount++;
    snapshot->lastDiscoveryWindowOpenAtMs = atMs;
    snapshot->lastDiscoveryWindowMs = windowMs;
  }
}

static inline void noteWindowClosed(
    CollarWindowSnapshot* snapshot,
    uint32_t atMs,
    bool handled) {
  if (!snapshot) return;
  snapshot->lastWindowCloseAtMs = atMs;
  snapshot->lastWindowHandled = handled;
}

static inline void noteRawDownlinkSeen(
    CollarWindowSnapshot* snapshot,
    uint32_t atMs,
    uint16_t rawLen,
    int16_t rssi,
    float snr,
    uint8_t msgType) {
  if (!snapshot) return;
  snapshot->lastDownlinkRawSeenAtMs = atMs;
  snapshot->lastDownlinkRawLen = rawLen;
  snapshot->lastDownlinkRawRssi = rssi;
  snapshot->lastDownlinkRawSnr = snr;
  snapshot->lastDownlinkRawMsgType = msgType;
  snapshot->rawDownlinkSeenCount++;
}

static inline void noteRawDownlinkRejected(
    CollarWindowSnapshot* snapshot,
    const char* reason) {
  if (!snapshot) return;
  snapshot->rawDownlinkRejectedCount++;
  copyText(
      snapshot->lastDownlinkDropReason,
      sizeof(snapshot->lastDownlinkDropReason),
      reason);
}

static inline void noteRawDownlinkAccepted(CollarWindowSnapshot* snapshot) {
  if (!snapshot) return;
  snapshot->rawDownlinkAcceptedCount++;
  copyText(
      snapshot->lastDownlinkDropReason,
      sizeof(snapshot->lastDownlinkDropReason),
      "accepted");
}

static inline void notePageRx(CollarWindowSnapshot* snapshot, uint32_t atMs) {
  if (!snapshot) return;
  snapshot->lastPageRxAtMs = atMs;
  snapshot->pageRxCount++;
}

static inline void notePageAckTx(CollarWindowSnapshot* snapshot, uint32_t atMs) {
  if (!snapshot) return;
  snapshot->lastPageAckTxAtMs = atMs;
}

static inline void noteSleepGraceHold(
    CollarWindowSnapshot* snapshot,
    uint32_t atMs,
    uint32_t windowMs) {
  if (!snapshot) return;
  snapshot->sleepGraceHoldCount++;
  snapshot->lastSleepGraceHoldAtMs = atMs;
  snapshot->lastSleepGraceWindowMs = windowMs;
}

static inline uint32_t secondaryWindowMs(
    uint32_t baseWindowMs,
    uint32_t overrideWindowMs) {
  return overrideWindowMs > 0 ? overrideWindowMs : baseWindowMs;
}

static inline bool benchWakeHoldActive(
    uint32_t nowMs,
    uint32_t lastUplinkAtMs,
    uint32_t holdAfterUplinkMs) {
  if (holdAfterUplinkMs == 0 || lastUplinkAtMs == 0) return false;
  return (uint32_t)(nowMs - lastUplinkAtMs) < holdAfterUplinkMs;
}

}  // namespace rtrdiag
