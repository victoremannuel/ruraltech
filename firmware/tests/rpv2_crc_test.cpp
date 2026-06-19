#include <assert.h>

#include "../shared/radio_proto_v2_crc.h"

static void fillPoint(rpv2::EncodedPoint* dst, int32_t lat, int32_t lon) {
  dst->latE7 = lat;
  dst->lonE7 = lon;
}

int main() {
  rpv2::EncodedPoint points3[3]{};
  fillPoint(&points3[0], -167000000, -492500000);
  fillPoint(&points3[1], -167005000, -492500000);
  fillPoint(&points3[2], -167005000, -492495000);
  const uint32_t crc3a = rpv2::crc32Fence(points3, 3);
  const uint32_t crc3b = rpv2::crc32Fence(points3, 3);
  assert(crc3a == crc3b);

  rpv2::EncodedPoint points6[6]{};
  for (int i = 0; i < 6; ++i) {
    fillPoint(&points6[i], -167000000 - (i * 1000), -492500000 + (i * 500));
  }
  const uint32_t crc6 = rpv2::crc32Fence(points6, 6);
  assert(crc6 != 0);

  rpv2::EncodedPoint points32[32]{};
  for (int i = 0; i < 32; ++i) {
    fillPoint(&points32[i], -167000000 + (i * 100), -492500000 - (i * 100));
  }
  const uint32_t crc32 = rpv2::crc32Fence(points32, 32);
  assert(crc32 != 0);
  assert(crc32 != crc6);
  return 0;
}
