#include <cassert>
#include <cstdint>

#include "../shared/rtr_wake_policy.h"

int main() {
  constexpr uint32_t kFloor = 180000u;
  constexpr uint32_t kMargin = 30000u;

  // cycle=0 → floor
  assert(rtrwakepolicy::waitingUplinkTimeoutMs(0, kFloor, kMargin) == kFloor);

  // small cycle: 2×5000+30000=40000 < floor → floor
  assert(rtrwakepolicy::waitingUplinkTimeoutMs(5000, kFloor, kMargin) == kFloor);

  // cycle that exactly hits floor: 2×75000+30000=180000 == floor
  assert(rtrwakepolicy::waitingUplinkTimeoutMs(75000, kFloor, kMargin) == kFloor);

  // large cycle: 2×100000+30000=230000 > floor → dynamic
  assert(rtrwakepolicy::waitingUplinkTimeoutMs(100000, kFloor, kMargin) == 230000u);

  // very large cycle
  assert(rtrwakepolicy::waitingUplinkTimeoutMs(200000, kFloor, kMargin) == 430000u);

  // margin applied correctly: cycle=80000, 2×80000+30000=190000 > 180000
  assert(rtrwakepolicy::waitingUplinkTimeoutMs(80000, kFloor, kMargin) == 190000u);

  // zero floor: any cycle overrides
  assert(rtrwakepolicy::waitingUplinkTimeoutMs(10000, 0, kMargin) == 50000u);

  // zero margin: pure 2× cycle vs floor
  assert(rtrwakepolicy::waitingUplinkTimeoutMs(100000, kFloor, 0) == 200000u);
  assert(rtrwakepolicy::waitingUplinkTimeoutMs(50000, kFloor, 0) == kFloor);

  return 0;
}
