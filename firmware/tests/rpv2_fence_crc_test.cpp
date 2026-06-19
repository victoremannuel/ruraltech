#include <assert.h>
#include <stdint.h>

#include "../shared/rpv2_fence_crc.h"

using rpv2fencecrc::FencePointE7;

static const FencePointE7 kFence6[] = {
    {-166753830, -494850390},
    {-166753900, -494850410},
    {-166754020, -494850300},
    {-166754100, -494850120},
    {-166753940, -494849980},
    {-166753780, -494850140},
};

static const FencePointE7 kFence7[] = {
    {-166753830, -494850390},
    {-166753900, -494850410},
    {-166754020, -494850300},
    {-166754100, -494850120},
    {-166753940, -494849980},
    {-166753780, -494850140},
    {-166753700, -494850280},
};

int main() {
  const uint32_t crc6a =
      rpv2fencecrc::computeCanonicalFenceCrc(kFence6, 6);
  const uint32_t crc6b =
      rpv2fencecrc::computeCanonicalFenceCrc(kFence6, 6);
  assert(crc6a == crc6b);

  FencePointE7 reordered6[6]{};
  for (uint16_t i = 0; i < 6; ++i) reordered6[i] = kFence6[i];
  const FencePointE7 tmp = reordered6[1];
  reordered6[1] = reordered6[2];
  reordered6[2] = tmp;
  assert(rpv2fencecrc::computeCanonicalFenceCrc(reordered6, 6) != crc6a);

  FencePointE7 changed6[6]{};
  for (uint16_t i = 0; i < 6; ++i) changed6[i] = kFence6[i];
  changed6[4].lonE7 += 1;
  assert(rpv2fencecrc::computeCanonicalFenceCrc(changed6, 6) != crc6a);

  FencePointE7 reassembled6[6]{};
  for (uint16_t i = 0; i < 5; ++i) reassembled6[i] = kFence6[i];
  reassembled6[5] = kFence6[5];
  assert(rpv2fencecrc::computeCanonicalFenceCrc(reassembled6, 6) == crc6a);

  const uint32_t crc7 =
      rpv2fencecrc::computeCanonicalFenceCrc(kFence7, 7);
  FencePointE7 reassembled7[7]{};
  for (uint16_t i = 0; i < 5; ++i) reassembled7[i] = kFence7[i];
  for (uint16_t i = 5; i < 7; ++i) reassembled7[i] = kFence7[i];
  assert(rpv2fencecrc::computeCanonicalFenceCrc(reassembled7, 7) == crc7);
  assert(crc7 != crc6a);

  struct PaddedPoint {
    uint8_t prefix;
    int32_t latE7;
    uint16_t middle;
    int32_t lonE7;
  };
  PaddedPoint padded[6]{};
  FencePointE7 adapted[6]{};
  for (uint16_t i = 0; i < 6; ++i) {
    padded[i].prefix = static_cast<uint8_t>(0xA0U + i);
    padded[i].latE7 = kFence6[i].latE7;
    padded[i].middle = static_cast<uint16_t>(0xB000U + i);
    padded[i].lonE7 = kFence6[i].lonE7;
    adapted[i] = {padded[i].latE7, padded[i].lonE7};
  }
  assert(rpv2fencecrc::computeCanonicalFenceCrc(adapted, 6) == crc6a);
  assert(rpv2fencecrc::computeCanonicalFenceCrc(nullptr, 0) != 0);
  assert(rpv2fencecrc::computeCanonicalFenceCrc(nullptr, 1) == 0);
  return 0;
}
