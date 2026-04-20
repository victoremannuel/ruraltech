#include <assert.h>

#include "../shared/radio_transport_v1_collar_policy.h"

int main() {
  assert(
      rtrv1::discoveryWindowMs(true, 2500, 5000) == 5000);
  assert(
      rtrv1::discoveryWindowMs(false, 2500, 5000) == 2500);
  assert(rtrv1::shouldOpenSecondaryRxWindow(false, false));
  assert(!rtrv1::shouldOpenSecondaryRxWindow(true, false));
  assert(!rtrv1::shouldOpenSecondaryRxWindow(false, true));
  return 0;
}
