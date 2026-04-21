#include <assert.h>

#include "../../gateway-matriz/RtrWakeOrchestrator.h"

int main() {
  rtrwake::SessionCore session{};
  session.active = true;
  session.state = rtrwake::State::PAGING_AWAITING_ACK;
  session.deviceId = 0xC011A001UL;
  session.pageSessionId = 0x1122334455667788ULL;
  session.pageMessageId = 77;
  session.pageSent = true;
  session.lastPageSentAtMs = 1000;
  session.pageAckDeadlineAtMs = 2500;

  assert(rtrwake::pageAckMatches(
      session,
      0xC011A001UL,
      0x1122334455667788ULL,
      77));
  assert(rtrwake::canConsumePageAckFastPath(session));
  assert(!rtrwake::isLatePageAck(session, 2499));
  assert(rtrwake::isLatePageAck(session, 2501));
  assert(!rtrwake::pageAckMatches(
      session,
      0xC011A002UL,
      0x1122334455667788ULL,
      77));
  assert(!rtrwake::pageAckMatches(
      session,
      0xC011A001UL,
      0x9988776655443322ULL,
      77));
  assert(!rtrwake::pageAckMatches(
      session,
      0xC011A001UL,
      0x1122334455667788ULL,
      78));

  return 0;
}
