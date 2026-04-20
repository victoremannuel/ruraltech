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
  return 0;
}
