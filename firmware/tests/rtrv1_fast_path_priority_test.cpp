#include <assert.h>

#include "../../gateway-matriz/RtrWakeOrchestrator.h"

int main() {
  rtrwake::SessionCore core{};
  core.active = true;
  core.deviceId = 77;
  core.state = rtrwake::State::PAGING_WAITING_UPLINK;

  const bool stateChanged = rtrwake::noteUplinkHint(&core, 77, 5000);
  assert(stateChanged);
  assert(core.state == rtrwake::State::PAGING_READY_TO_SEND);
  assert(core.cloudTxDeferred);
  assert(rtrwake::shouldDeferCloudTx(core, 77));

  rtrwake::markPageAttempt(&core, 5120, rtrv1::PAGE_ACK_TIMEOUT_MS);
  core.state = rtrwake::State::PAGING_AWAITING_ACK;
  assert(core.campaignCount == 1);
  assert(core.lastPageSentAtMs == 5120);
  assert(rtrwake::canConsumePageAckFastPath(core));

  return 0;
}
