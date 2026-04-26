#include <assert.h>
#include <string.h>

#include "../../firmware/shared/rtr_diag_support.h"

int main() {
  rtrdiag::PageSnapshot page{};

  rtrdiag::notePageTx(&page, 77, 0x1122334455667788ULL, 41, 1, 9000, 10500);
  rtrdiag::noteAckRxWindowBegin(&page, 9000);
  rtrdiag::noteAckRejected(&page, "ack_after_hard_timeout");
  rtrdiag::noteAckRxWindowEnd(&page, 10501, "timeout");

  assert(page.lastPageSentAtMs == 9000);
  assert(page.lastPageAckDeadlineAtMs == 10500);
  assert(page.lastAckRxWindowBeginAtMs == 9000);
  assert(page.lastAckRxWindowEndAtMs == 10501);
  assert(strcmp(page.lastAckRxWindowResult, "timeout") == 0);
  assert(strcmp(page.lastAckLateReason, "ack_after_hard_timeout") == 0);

  rtrdiag::noteAckLatency(&page, 321);
  rtrdiag::notePagePostTxFast(&page, 17);
  rtrdiag::noteAckMatched(&page, false);

  assert(page.lastPageTxToAckRxLatencyMs == 321);
  assert(page.lastPagePostTxFastDurationMs == 17);
  assert(strcmp(page.lastAckLateReason, "none") == 0);

  return 0;
}
