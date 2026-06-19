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
  assert(rtrv1::shouldHoldSleepForRetryGrace(5000, 3000, false, false, rtrv1::COLLAR_SLEEP_GRACE_MS));
  assert(!rtrv1::shouldHoldSleepForRetryGrace(9000, 3000, false, false, rtrv1::COLLAR_SLEEP_GRACE_MS));
  assert(!rtrv1::shouldHoldSleepForRetryGrace(5000, 3000, true, false, rtrv1::COLLAR_SLEEP_GRACE_MS));
  assert(rtrv1::remainingSleepGraceMs(5000, 3000, rtrv1::COLLAR_SLEEP_GRACE_MS) ==
      rtrv1::COLLAR_SLEEP_GRACE_MS - 2000);
  assert(rtrv1::remainingSleepGraceMs(9000, 3000, rtrv1::COLLAR_SLEEP_GRACE_MS) == 0);
  return 0;
}
