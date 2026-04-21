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
  session.pageSent = true;
  session.lastPageSentAtMs = 1000;
  session.pageAckDeadlineAtMs = 2000;
  assert(!rtrwake::isLatePageAck(session, 1999));
  assert(rtrwake::isLatePageAck(session, 2001));
  return 0;
}
