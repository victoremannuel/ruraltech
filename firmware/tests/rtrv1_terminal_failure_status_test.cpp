#include <assert.h>
#include <string.h>

#include "../../gateway-matriz/RtrWakeOrchestrator.h"

int main() {
  assert(strcmp(
      rtrwake::aggregateCommandStatus(true, true, false),
      "failed") == 0);
  assert(strcmp(
      rtrwake::aggregateCommandStatus(true, false, false),
      "completed") == 0);
  assert(strcmp(
      rtrwake::aggregateCommandStatus(false, false, true),
      "paging_waiting_uplink") == 0);
  assert(strcmp(
      rtrwake::aggregateCommandStatus(false, false, false),
      "dispatching") == 0);

  rtrwake::SessionCore session{};
  session.active = true;
  session.state = rtrwake::State::PAGING_AWAITING_ACK;
  session.deviceId = 1234;
  session.pageSessionId = 0xAA55ULL;
  session.pageMessageId = 99;
  rtrwake::markPageAttempt(&session, 1000, 1000);
  session.inFlightPage.sessionId = 0xAA55ULL;
  session.inFlightPage.messageId = 99;
  session.inFlightPage.hardDeadlineAtMs = 2900;
  assert(!rtrwake::isLatePageAck(session, 2899));
  assert(rtrwake::isLatePageAck(session, 2901));
  return 0;
}
