#include <assert.h>

#include "../../gateway-matriz/RtrWakeOrchestrator.h"

int main() {
  rtrwake::SessionCore session{};
  session.active = true;
  session.deviceId = 77;
  session.state = rtrwake::State::PAGING_READY_TO_SEND;
  session.lastUplinkAtMs = 1000;
  session.predictedWakeAtMs = 1200;
  session.nextPageAttemptAtMs = 1000;
  session.cloudTxDeferred = true;

  assert(rtrwake::hasFreshWakeHint(session, 1300, rtrv1::FAST_PAGE_DEADLINE_MS));
  assert(rtrwake::wakeHintAgeMs(session, 1300) == 300);
  assert(!rtrwake::hasFreshWakeHint(session, 1301, rtrv1::FAST_PAGE_DEADLINE_MS));
  assert(rtrwake::wakeHintAgeMs(session, 1301) == 301);

  rtrwake::requireFreshUplink(&session, 1301);
  assert(session.state == rtrwake::State::PAGING_WAITING_UPLINK);
  assert(session.requiresFreshUplink);
  assert(session.lastUplinkAtMs == 0);
  assert(session.predictedWakeAtMs == 0);
  assert(session.nextPageAttemptAtMs == 0);
  assert(!session.cloudTxDeferred);
  assert(!session.pageSent);
  assert(!session.pageAcked);
  session.predictedWakeAtMs = 1302;
  assert(!rtrwake::predictedWakeReady(session, 5000));

  assert(!rtrwake::noteUplinkHint(&session, 999, 6000));
  assert(session.requiresFreshUplink);
  assert(session.state == rtrwake::State::PAGING_WAITING_UPLINK);
  assert(rtrwake::noteUplinkHint(&session, 77, 1400));
  assert(session.state == rtrwake::State::PAGING_READY_TO_SEND);
  assert(!session.requiresFreshUplink);
  assert(session.lastUplinkAtMs == 1400);
  assert(session.nextPageAttemptAtMs == 1400);
  assert(session.predictedWakeAtMs == 0);
  assert(session.cloudTxDeferred);
  assert(rtrwake::hasFreshWakeHint(session, 1400, rtrv1::FAST_PAGE_DEADLINE_MS));

  return 0;
}
