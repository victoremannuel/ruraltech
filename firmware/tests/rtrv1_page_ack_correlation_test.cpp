#include <assert.h>

#include "../../gateway-matriz/RtrWakeOrchestrator.h"

int main() {
  rtrwake::SessionCore session{};
  session.active = true;
  session.deviceId = 0xC011A001UL;
  session.pageSessionId = 0x1122334455667788ULL;
  session.pageMessageId = 77;

  assert(rtrwake::pageAckMatches(
      session,
      0xC011A001UL,
      0x1122334455667788ULL,
      77));
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
