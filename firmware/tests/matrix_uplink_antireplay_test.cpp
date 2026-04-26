#include <assert.h>
#include <string.h>

#include "../shared/matrix_uplink_antireplay.h"

int main() {
  using rtmatrix::antireplay::ReplayEntry;

  ReplayEntry entries[4]{};
  entries[0] = ReplayEntry{
      3222380545UL, 0x9FFFC95AA1624895ULL, 1, 274000002UL};
  entries[1] = ReplayEntry{
      3222380545UL, 0xAAAAAAAAAAAAAAAAULL, 1, 91UL};
  entries[2] = ReplayEntry{
      3222380545UL, 0x9FFFC95AA1624895ULL, 2, 77UL};

  assert(
      rtmatrix::antireplay::findEntry(
          entries, 4, 3222380545UL, 0x9FFFC95AA1624895ULL, 1) == 0);
  assert(
      rtmatrix::antireplay::findEntry(
          entries, 4, 3222380545UL, 0xBBBBBBBBBBBBBBBBULL, 1) == -1);

  uint32_t before = 0;
  uint32_t after = 99;
  assert(rtmatrix::antireplay::resetEntry(
      entries,
      4,
      3222380545UL,
      0x9FFFC95AA1624895ULL,
      1,
      &before,
      &after));
  assert(before == 274000002UL);
  assert(after == 0);
  assert(entries[0].deviceId == 0);
  assert(entries[1].lastSeq == 91UL);
  assert(entries[2].lastSeq == 77UL);

  assert(rtmatrix::antireplay::resetEntry(
      entries,
      4,
      3222380545UL,
      0x9FFFC95AA1624895ULL,
      1,
      &before,
      &after));
  assert(before == 0);
  assert(after == 0);

  char scopeHex[rtmatrix::antireplay::kScopeHexSize]{};
  rtmatrix::antireplay::scopeIdToHex(
      0x9FFFC95AA1624895ULL, scopeHex, sizeof(scopeHex));
  assert(strcmp(scopeHex, "9FFFC95AA1624895") == 0);
  assert(rtmatrix::antireplay::signedSeqDelta(19000001UL, 274000002UL) < 0);

  return 0;
}
