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

  rtrdiag::PageSnapshot page{};
  rtrdiag::noteWakeHint(&page, 2000, 55, true);
  rtrdiag::notePageTx(&page, 77, 0xAA55ULL, 19, 2, 2100, 3600);
  assert(page.lastWakeHintAtMs == 2000);
  assert(page.lastWakeHintSeq == 55);
  assert(page.lastWakeHintAccepted);
  assert(page.lastPageTargetDeviceId == 77);
  assert(page.lastPageSessionId == 0xAA55ULL);
  assert(page.lastPageMessageId == 19);
  assert(page.lastPageCampaignCount == 2);
  assert(page.lastPageSentAtMs == 2100);
  assert(page.lastPageAckDeadlineAtMs == 3600);
  assert(strcmp(page.lastPageOutcome, "tx_ok") == 0);
  rtrdiag::notePageOutcome(&page, "timeout_final");
  assert(strcmp(page.lastPageOutcome, "timeout_final") == 0);

  rtrdiag::CollarWindowSnapshot collar{};
  rtrdiag::noteDiscoveryWindowOpen(&collar, false, 100, 2500);
  rtrdiag::noteRawDownlinkSeen(&collar, 140, 92, -88, 5.5f, 4);
  rtrdiag::noteRawDownlinkRejected(&collar, "decrypt_failed");
  rtrdiag::noteDiscoveryWindowOpen(&collar, true, 300, 1800);
  rtrdiag::noteRawDownlinkAccepted(&collar);
  rtrdiag::notePageRx(&collar, 320);
  rtrdiag::notePageAckTx(&collar, 333);
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
