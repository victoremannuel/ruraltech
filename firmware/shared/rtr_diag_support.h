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

struct PageSnapshot {
  uint32_t lastWakeHintAtMs = 0;
  uint32_t lastWakeHintSeq = 0;
  uint32_t lastPageTargetDeviceId = 0;
  uint64_t lastPageSessionId = 0;
  uint32_t lastPageMessageId = 0;
  uint32_t lastPageSentAtMs = 0;
  uint32_t lastPageAckDeadlineAtMs = 0;
  uint32_t lastPageRetryAtMs = 0;
  uint32_t lastWakeToPageLatencyMs = 0;
  uint32_t lastSoftDeadlineMs = 0;
  uint8_t lastPageCampaignCount = 0;
  bool lastWakeHintAccepted = false;
  bool lastSoftDeadlineMet = false;
  char lastPageOutcome[kOutcomeSize] = "none";
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
    const char* outcome) {
  if (!snapshot) return;
  snapshot->lastPageRetryAtMs = retryAtMs;
  if (outcome && outcome[0]) {
    copyText(snapshot->lastPageOutcome, sizeof(snapshot->lastPageOutcome), outcome);
  }
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
