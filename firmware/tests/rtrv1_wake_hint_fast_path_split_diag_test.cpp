#include <assert.h>
#include <string.h>

#include "../../firmware/shared/rtr_diag_support.h"

int main() {
  rtrdiag::PageSnapshot page{};

  rtrdiag::noteWakeHint(&page, 1000, 41, true);
  rtrdiag::noteWakeHintFastPath(&page, 12, 25, "none");
  rtrdiag::noteImmediateEnter(&page, 1000, 77, 41, "main_lora_rx");
  rtrdiag::noteImmediateResult(&page, 1025, 77, 41, 25, "page_tx_ok", true, "main_lora_rx");

  assert(page.lastWakeHintAtMs == 1000);
  assert(page.lastWakeHintSeq == 41);
  assert(page.lastWakeHintAccepted);
  assert(page.lastWakeHintFastDurationMs == 12);
  assert(page.lastPrePageGapMs == 25);
  assert(strcmp(page.lastPrePageBlockedBy, "none") == 0);
  assert(strcmp(page.lastImmediateSource, "main_lora_rx") == 0);
  assert(strcmp(page.lastImmediateResult, "page_tx_ok") == 0);

  rtrdiag::notePrePageBlockedBy(&page, "cloud_tx");
  assert(strcmp(page.lastPrePageBlockedBy, "cloud_tx") == 0);

  return 0;
}
