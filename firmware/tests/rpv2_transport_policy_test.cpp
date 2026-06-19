#include <cassert>
#include <cstdint>

#include "../shared/rpv2_transport_policy.h"

int main() {
  assert(rpv2transport::isImmediatelyPreviousFragment(1, 2));
  assert(!rpv2transport::isImmediatelyPreviousFragment(2, 2));
  assert(!rpv2transport::isImmediatelyPreviousFragment(3, 2));

  assert(rpv2transport::acceptedRangeEndsAt(0, 5, 5));
  assert(rpv2transport::acceptedRangeEndsAt(5, 1, 6));
  assert(!rpv2transport::acceptedRangeEndsAt(0, 4, 5));

  assert(rpv2transport::shouldRetryFragment(1));
  assert(rpv2transport::shouldRetryFragment(2));
  assert(!rpv2transport::shouldRetryFragment(3));

  assert(!rpv2transport::deadlineReached(99, 100));
  assert(rpv2transport::deadlineReached(100, 100));
  assert(rpv2transport::deadlineReached(101, 100));
  assert(rpv2transport::deadlineReached(5, UINT32_MAX - 5));
  return 0;
}
