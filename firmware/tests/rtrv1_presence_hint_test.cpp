#include <assert.h>

#include "../../gateway-matriz/RtrWakeOrchestrator.h"

int main() {
  rtrwake::Presence presence{};
  rtrwake::updatePresence(&presence, 42, 1000);
  assert(presence.valid);
  assert(presence.deviceId == 42);
  assert(presence.lastSeenAtMs == 1000);
  assert(presence.estimatedCycleMs == 0);

  rtrwake::updatePresence(&presence, 42, 1600);
  assert(presence.lastSeenAtMs == 1600);
  assert(presence.estimatedCycleMs == 600);

  rtrwake::SessionCore session{};
  session.active = true;
  session.deviceId = 42;
  session.state = rtrwake::State::PAGING_WAITING_UPLINK;
  session.predictedWakeAtMs = 2200;
  assert(!rtrwake::predictedWakeReady(session, 2100));
  assert(rtrwake::predictedWakeReady(session, 2200));
  assert(rtrwake::noteUplinkHint(&session, 42, 2300));
  assert(session.state == rtrwake::State::PAGING_READY_TO_SEND);

  return 0;
}
