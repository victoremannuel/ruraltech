#include <assert.h>

#include "../shared/radio_transport_v1_crc.h"

int main() {
  static const uint8_t payload[] = {'R', 'T', 'R', 'v', '1'};
  const uint32_t crcA = rtrv1::crc32(payload, sizeof(payload));
  const uint32_t crcB = rtrv1::crc32(payload, sizeof(payload));
  static const uint8_t payload2[] = {'R', 'T', 'R', 'v', '2'};
  const uint32_t crcC = rtrv1::crc32(payload2, sizeof(payload2));

  assert(crcA == crcB);
  assert(crcA != 0);
  assert(crcA != crcC);

  return 0;
}
