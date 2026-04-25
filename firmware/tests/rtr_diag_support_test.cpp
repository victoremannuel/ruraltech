#include <assert.h>
#include <string.h>

#include "../shared/rtr_diag_support.h"

int main() {
  rtrdiag::DecryptFailSnapshot decrypt{};
  rtrdiag::noteDecryptFail(
      &decrypt,
      1234,
      7,
      166,
      -91,
      7.5f,
      0x0040,
      "rx_decrypt_failed",
      "decrypt_or_hmac_failed",
      "A1B2C3D4",
      "00112233445566778899AABB",
      "DEADBEEFCAFEBABE");
  assert(decrypt.atMs == 1234);
  assert(decrypt.count == 7);
  assert(decrypt.len == 166);
  assert(decrypt.rssi == -91);
  assert(decrypt.snr == 7.5f);
  assert(decrypt.irqFlags == 0x0040);
  assert(strcmp(decrypt.radioState, "rx_decrypt_failed") == 0);
  assert(strcmp(decrypt.reason, "decrypt_or_hmac_failed") == 0);
  assert(strcmp(decrypt.headHex, "A1B2C3D4") == 0);
  assert(strcmp(decrypt.nonceHex, "00112233445566778899AABB") == 0);
  assert(strcmp(decrypt.tagHex, "DEADBEEFCAFEBABE") == 0);

  const uint8_t repeated70[16] = {
      0x70, 0x70, 0x70, 0x70, 0x70, 0x70, 0x70, 0x70,
      0x70, 0x70, 0x70, 0x70, 0x70, 0x70, 0x70, 0x70};
  const uint8_t varied[16] = {
      0x70, 0x71, 0x70, 0x71, 0x70, 0x71, 0x70, 0x71,
      0x70, 0x71, 0x70, 0x71, 0x70, 0x71, 0x70, 0x71};
  assert(rtrdiag::hasExtremeRepeatedPrefix(repeated70, sizeof(repeated70), 12));
  assert(!rtrdiag::hasExtremeRepeatedPrefix(varied, sizeof(varied), 12));
  assert(rtrdiag::looksLikeRawNoise(112, -127, 0.0f, repeated70, sizeof(repeated70)));
  assert(!rtrdiag::looksLikeRawNoise(112, -90, 7.5f, varied, sizeof(varied)));
  assert(rtrdiag::looksLikeInvalidRepeatedPattern(
      repeated70,
      12,
      repeated70,
      8,
      repeated70,
      8));

  rtrdiag::PageSnapshot page{};
  rtrdiag::noteWakeHint(&page, 2000, 55, true);
  rtrdiag::notePageTx(&page, 77, 0xAA55ULL, 19, 2, 2100, 3600);
  rtrdiag::notePageLatency(&page, 100, 300, true);
  assert(page.lastWakeHintAtMs == 2000);
  assert(page.lastWakeHintSeq == 55);
  assert(page.lastWakeHintAccepted);
  assert(page.lastPageTargetDeviceId == 77);
  assert(page.lastPageSessionId == 0xAA55ULL);
  assert(page.lastPageMessageId == 19);
  assert(page.lastPageCampaignCount == 2);
  assert(page.lastPageSentAtMs == 2100);
  assert(page.lastPageAckDeadlineAtMs == 3600);
  assert(page.lastWakeToPageLatencyMs == 100);
  assert(page.lastSoftDeadlineMs == 300);
  assert(page.lastSoftDeadlineMet);
  assert(page.inFlightPageValid);
  assert(page.inFlightPageSessionId == 0xAA55ULL);
  assert(page.inFlightPageMessageId == 19);
  assert(page.inFlightPageCampaignCount == 2);
  assert(strcmp(page.lastPageOutcome, "tx_ok") == 0);
  rtrdiag::noteInFlightPageContext(&page, true, 0xAA55ULL, 19, 2, 2100, 3600, 4500, false);
  rtrdiag::notePageRetry(&page, 4500, 3, "timeout_retry_grace");
  assert(page.lastPageRetryAtMs == 4500);
  assert(page.retryPending);
  assert(page.retryAtMs == 4500);
  assert(page.retryCampaignCount == 3);
  assert(strcmp(page.lastPageOutcome, "timeout_retry_grace") == 0);
  rtrdiag::noteAckRejected(&page, "state_not_awaiting_ack");
  assert(strcmp(page.lastAckRejectedReason, "state_not_awaiting_ack") == 0);
  rtrdiag::noteAckMatched(&page, true);
  assert(page.inFlightPageAckAccepted);
  assert(page.lastAckMatchedInGrace);
  assert(!page.retryPending);
  rtrdiag::notePageOutcome(&page, "timeout_final");
  assert(strcmp(page.lastPageOutcome, "timeout_final") == 0);

  rtrdiag::RawRxSnapshot raw{};
  rtrdiag::noteRawRxSeen(&raw, 112, -127, 0.0f);
  rtrdiag::noteRawNoiseDrop(&raw, "implausible_raw_signal", "70707070");
  rtrdiag::noteRawPatternDrop(&raw, "repeated_pattern", "70707070");
  rtrdiag::noteRawDecryptAttempt(&raw);
  rtrdiag::noteRawDecryptFailed(&raw);
  rtrdiag::noteRawAccepted(&raw);
  assert(raw.rawRxSeenCount == 1);
  assert(raw.rawRxNoiseDropCount == 1);
  assert(raw.rawRxInvalidPatternDropCount == 1);
  assert(raw.rawRxDecryptAttemptCount == 1);
  assert(raw.rawRxDecryptFailedCount == 1);
  assert(raw.rawRxAcceptedCount == 1);
  assert(strcmp(raw.lastRawNoiseReason, "repeated_pattern") == 0);
  assert(strcmp(raw.lastRawPatternHex, "70707070") == 0);

  rtrdiag::CollarWindowSnapshot collar{};
  rtrdiag::noteDiscoveryWindowOpen(&collar, false, 100, 2500);
  rtrdiag::noteRawDownlinkSeen(&collar, 140, 92, -88, 5.5f, 4);
  rtrdiag::noteRawDownlinkRejected(&collar, "decrypt_failed");
  rtrdiag::noteDiscoveryWindowOpen(&collar, true, 300, 1800);
  rtrdiag::noteRawDownlinkAccepted(&collar);
  rtrdiag::notePageRx(&collar, 320);
  rtrdiag::notePageAckTx(&collar, 333);
  rtrdiag::noteSleepGraceHold(&collar, 340, 700);
  rtrdiag::noteWindowClosed(&collar, 350, true);
  assert(collar.discoveryWindowOpenCount == 1);
  assert(collar.secondaryWindowOpenCount == 1);
  assert(collar.lastDiscoveryWindowMs == 2500);
  assert(collar.lastSecondaryWindowMs == 1800);
  assert(collar.lastDownlinkRawSeenAtMs == 140);
  assert(collar.lastDownlinkRawLen == 92);
  assert(collar.lastDownlinkRawRssi == -88);
  assert(collar.lastDownlinkRawSnr == 5.5f);
  assert(collar.lastDownlinkRawMsgType == 4);
  assert(collar.rawDownlinkSeenCount == 1);
  assert(collar.rawDownlinkRejectedCount == 1);
  assert(collar.rawDownlinkAcceptedCount == 1);
  assert(collar.pageRxCount == 1);
  assert(collar.lastPageRxAtMs == 320);
  assert(collar.lastPageAckTxAtMs == 333);
  assert(collar.lastSleepGraceHoldAtMs == 340);
  assert(collar.lastSleepGraceWindowMs == 700);
  assert(collar.sleepGraceHoldCount == 1);
  assert(collar.lastWindowCloseAtMs == 350);
  assert(collar.lastWindowHandled);
  assert(strcmp(collar.lastDownlinkDropReason, "accepted") == 0);

  assert(rtrdiag::secondaryWindowMs(1200, 0) == 1200);
  assert(rtrdiag::secondaryWindowMs(1200, 2400) == 2400);
  assert(!rtrdiag::benchWakeHoldActive(5000, 0, 1200));
  assert(rtrdiag::benchWakeHoldActive(5000, 4500, 1200));
  assert(!rtrdiag::benchWakeHoldActive(7000, 4500, 1200));
  return 0;
}
