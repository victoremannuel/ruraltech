#include <assert.h>
#include <string.h>

#include "../shared/command_contract.h"

int main() {
  using rtcmd::ChunkRange;
  using rtcmd::ValidationCode;

  assert(rtcmd::isValidCoordinate(-23.55, -46.63));
  assert(!rtcmd::isValidCoordinate(120.0, -46.63));
  assert(rtcmd::isAdminRole("adm"));
  assert(rtcmd::isAdminRole(" ADMIN "));
  assert(!rtcmd::isAdminRole("user"));
  assert(rtcmd::targetIncludesGateway(nullptr));
  assert(rtcmd::targetIncludesGateway("gateway"));
  assert(!rtcmd::targetIncludesGateway("collars"));
  assert(rtcmd::targetIncludesCollars("collars"));
  assert(rtcmd::targetIncludesCollars("collar"));
  assert(!rtcmd::targetIncludesCollars("gateway"));

  assert(
      rtcmd::validateSetParamsPayload(false, true, false, "", "") ==
      ValidationCode::kMissingWifiOtaEnabled);
  assert(
      rtcmd::validateSetParamsPayload(true, false, false, "user", "user") ==
      ValidationCode::kAdminRequiredForLoraOnly);
  assert(
      rtcmd::validateSetParamsPayload(true, false, true, "", "") ==
      ValidationCode::kOk);
  assert(
      rtcmd::validateSetParamsPayload(true, true, false, "", "") ==
      ValidationCode::kOk);

  assert(rtcmd::validatePointCount(2, 32) == ValidationCode::kTooFewPoints);
  assert(rtcmd::validatePointCount(33, 32) == ValidationCode::kTooManyPoints);
  assert(rtcmd::validatePointCount(3, 32) == ValidationCode::kOk);
  assert(
      rtcmd::validatePhaseCount(0, 8) == ValidationCode::kInvalidPhaseCount);
  assert(rtcmd::validatePhaseCount(1, 8) == ValidationCode::kOk);

  const uint16_t pointCosts[5] = {20, 20, 20, 20, 20};
  ChunkRange ranges[8];
  uint8_t rangeCount = 0;
  ValidationCode chunkCode = rtcmd::planPointChunks(
      pointCosts,
      5,
      30,
      70,
      32,
      ranges,
      8,
      &rangeCount);
  assert(chunkCode == ValidationCode::kOk);
  assert(rangeCount == 3);
  assert(ranges[0].start == 0 && ranges[0].end == 2);
  assert(ranges[1].start == 2 && ranges[1].end == 4);
  assert(ranges[2].start == 4 && ranges[2].end == 5);

  const uint16_t oversizedPoint[3] = {150, 20, 20};
  rangeCount = 0;
  chunkCode = rtcmd::planPointChunks(
      oversizedPoint,
      3,
      10,
      120,
      32,
      ranges,
      8,
      &rangeCount);
  assert(chunkCode == ValidationCode::kPointChunkTooLarge);

  const uint16_t invalidPointCost[3] = {15, 0, 15};
  rangeCount = 0;
  chunkCode = rtcmd::planPointChunks(
      invalidPointCost,
      3,
      10,
      120,
      32,
      ranges,
      8,
      &rangeCount);
  assert(chunkCode == ValidationCode::kInvalidPointValue);

  const char* reason =
      rtcmd::validationCodeToReason(ValidationCode::kAdminRequiredForLoraOnly);
  assert(reason != nullptr && strcmp(reason, "admin_required_for_lora_only") == 0);

  return 0;
}
