#include <cassert>
#include <cstdint>
#include <limits>

#include "../shared/rtr_wake_policy.h"

int main() {
  constexpr uint32_t kFloor = 300000u;
  constexpr uint32_t kMargin = 30000u;

  // cycle=0 → floor
  assert(rtrwakepolicy::waitingUplinkTimeoutMs(0, kFloor, kMargin) == kFloor);

  // small cycle: 2×5000+30000=40000 < floor → floor
  assert(rtrwakepolicy::waitingUplinkTimeoutMs(5000, kFloor, kMargin) == kFloor);

  // cycle that exactly hits floor: 2×135000+30000=300000 == floor
  assert(rtrwakepolicy::waitingUplinkTimeoutMs(135000, kFloor, kMargin) == kFloor);

  // observed bench cycle: 2×469975+30000=969950
  assert(rtrwakepolicy::waitingUplinkTimeoutMs(469975, kFloor, kMargin) == 969950u);

  // very large cycle
  assert(rtrwakepolicy::waitingUplinkTimeoutMs(200000, kFloor, kMargin) == 430000u);

  // small cycles remain protected by the floor
  assert(rtrwakepolicy::waitingUplinkTimeoutMs(80000, kFloor, kMargin) == kFloor);

  // zero floor: any cycle overrides
  assert(rtrwakepolicy::waitingUplinkTimeoutMs(10000, 0, kMargin) == 50000u);

  // zero margin: pure 2× cycle vs floor
  assert(rtrwakepolicy::waitingUplinkTimeoutMs(200000, kFloor, 0) == 400000u);
  assert(rtrwakepolicy::waitingUplinkTimeoutMs(50000, kFloor, 0) == kFloor);

  // saturation-safe arithmetic
  assert(rtrwakepolicy::waitingUplinkTimeoutMs(
             std::numeric_limits<uint32_t>::max(),
             kFloor,
             kMargin) == std::numeric_limits<uint32_t>::max());

  return 0;
}
