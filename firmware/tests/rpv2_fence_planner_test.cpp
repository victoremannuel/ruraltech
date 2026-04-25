#include <assert.h>
#include <string.h>

#include "../shared/radio_proto_v2_codec.h"
#include "../shared/radio_proto_v2_crc.h"
#include "../shared/radio_proto_v2_planner_support.h"

namespace {
enum class MsgType : uint8_t {
  SET_FENCE = 10,
};

struct ProgressivePlanResult {
  bool planReady = false;
  uint8_t chunkCount = 0;
  uint8_t firstAcceptedPointCount = 0;
  uint8_t rejectCountBeforeFirstFit = 0;
  uint16_t maxWireLen = 0;
  const char* reason = nullptr;
};

struct LoRaFrameStub {
  uint32_t deviceId = 0;
  uint64_t scopeId = 0;
  MsgType msgType = MsgType::SET_FENCE;
  uint32_t seq = 0;
  uint32_t timestamp = 0;
  uint8_t nonce[12]{};
  uint8_t payloadLen = 0;
  uint8_t payload[128]{};
  uint8_t tag[16]{};
};

static size_t encodePlainLikeGateway(const LoRaFrameStub& f) {
  return 4 + 8 + 1 + 4 + 4 + 12 + 1 + f.payloadLen + 16;
}

static uint16_t exactWireLenForPayload(
    const uint8_t* payload,
    uint8_t payloadLen) {
  LoRaFrameStub tx;
  tx.deviceId = 123;
  tx.scopeId = 0xDEADBEEF00000001ULL;
  tx.payloadLen = payloadLen;
  memcpy(tx.payload, payload, payloadLen);
  const size_t packedLen = encodePlainLikeGateway(tx);
  const size_t cipherLen = packedLen - 16;
  return static_cast<uint16_t>(12 + cipherLen + 16);
}

static ProgressivePlanResult buildProgressivePlanForPoints(
    const rpv2::PointLatLonE7* points,
    uint8_t totalPoints) {
  ProgressivePlanResult result;
  rpv2::Header header{};
  header.protocolVersion = rpv2::PROTOCOL_VERSION;
  header.msgType = rpv2::FENCE_POINTS;
  header.flags = rpv2::FLAG_ACK_REQUIRED | rpv2::FLAG_FROM_MATRIX;
  header.headerLen = sizeof(rpv2::Header);
  header.radioCommandId = 0x1122334455667788ULL;
  header.sessionNonce = 0xA1B2C3D4UL;
  header.fragmentTotal = 1;

  uint8_t frame[128]{};
  uint8_t start = 0;
  while (start < totalPoints) {
    bool fit = false;
    for (uint8_t candidateCount = static_cast<uint8_t>(totalPoints - start);
         candidateCount >= 1;
         --candidateCount) {
      header.fragmentIndex = result.chunkCount + 1;
      rpv2::FencePointsPrefix prefix{};
      prefix.startPointIndex = start;
      prefix.pointCount = candidateCount;
      const size_t len = rpv2::encodePointsFrame(
          header,
          prefix,
          points + start,
          candidateCount,
          frame,
          sizeof(frame));
      assert(len > 0);
      const uint16_t wireLen = exactWireLenForPayload(frame, static_cast<uint8_t>(len));
      if (wireLen > result.maxWireLen) result.maxWireLen = wireLen;
      if (wireLen <= 128) {
        result.planReady = true;
        result.chunkCount++;
        if (result.firstAcceptedPointCount == 0) {
          result.firstAcceptedPointCount = candidateCount;
        }
        start = static_cast<uint8_t>(start + candidateCount);
        fit = true;
        break;
      }
      if (result.firstAcceptedPointCount == 0) {
        result.rejectCountBeforeFirstFit++;
      }
      if (candidateCount == 1) {
        result.planReady = false;
        result.reason = "fence_single_point_chunk_too_large";
        return result;
      }
    }
    assert(fit);
  }
  return result;
}

static ProgressivePlanResult buildForcedOversizePlan(
    uint8_t totalPoints,
    uint8_t firstFittingCount) {
  ProgressivePlanResult result;
  uint8_t start = 0;
  while (start < totalPoints) {
    bool fit = false;
    for (uint8_t candidateCount = static_cast<uint8_t>(totalPoints - start);
         candidateCount >= 1;
         --candidateCount) {
      if (candidateCount > firstFittingCount) {
        if (result.firstAcceptedPointCount == 0) {
          result.rejectCountBeforeFirstFit++;
        }
        if (candidateCount == 1) {
          result.reason = "fence_single_point_chunk_too_large";
          return result;
        }
        continue;
      }
      result.planReady = true;
      result.chunkCount++;
      if (result.firstAcceptedPointCount == 0) {
        result.firstAcceptedPointCount = candidateCount;
      }
      start = static_cast<uint8_t>(start + candidateCount);
      fit = true;
      break;
    }
    assert(fit);
  }
  return result;
}

static ProgressivePlanResult buildAlwaysOversizePlan(uint8_t totalPoints) {
  ProgressivePlanResult result;
  for (uint8_t candidateCount = totalPoints; candidateCount >= 1; --candidateCount) {
    if (candidateCount == 1) {
      result.reason = "fence_single_point_chunk_too_large";
      return result;
    }
  }
  return result;
}
}  // namespace

int main() {
  {
    const rpv2plan::CandidateDecision reducible = rpv2plan::classifyCandidate(
        true,
        true,
        134,
        128,
        "secure_envelope_too_large",
        6);
    assert(reducible.measurementOk);
    assert(!reducible.fitsLimit);
    assert(reducible.reducibleOversize);
    assert(!reducible.terminalCodecError);
    assert(!reducible.terminalSinglePointOversize);
    assert(strcmp(reducible.reason, "secure_envelope_too_large") == 0);
  }

  {
    const rpv2plan::CandidateDecision terminalSinglePoint = rpv2plan::classifyCandidate(
        true,
        true,
        134,
        128,
        "secure_envelope_too_large",
        1);
    assert(terminalSinglePoint.measurementOk);
    assert(!terminalSinglePoint.fitsLimit);
    assert(!terminalSinglePoint.reducibleOversize);
    assert(!terminalSinglePoint.terminalCodecError);
    assert(terminalSinglePoint.terminalSinglePointOversize);
    assert(strcmp(terminalSinglePoint.reason, "fence_single_point_chunk_too_large") == 0);
  }

  {
    const rpv2plan::CandidateDecision codecFailure = rpv2plan::classifyCandidate(
        false,
        false,
        0,
        128,
        "points_encode_failed",
        3);
    assert(!codecFailure.measurementOk);
    assert(!codecFailure.fitsLimit);
    assert(!codecFailure.reducibleOversize);
    assert(codecFailure.terminalCodecError);
    assert(!codecFailure.terminalSinglePointOversize);
    assert(strcmp(codecFailure.reason, "points_encode_failed") == 0);
  }

  rpv2::Header header{};
  header.protocolVersion = rpv2::PROTOCOL_VERSION;
  header.flags = rpv2::FLAG_ACK_REQUIRED | rpv2::FLAG_FROM_MATRIX;
  header.headerLen = sizeof(rpv2::Header);
  header.radioCommandId = 0x1122334455667788ULL;
  header.sessionNonce = 0xA1B2C3D4UL;

  uint8_t frame[128]{};

  header.msgType = rpv2::FENCE_BEGIN;
  rpv2::FenceBeginBody begin{};
  begin.totalPoints = 6;
  begin.totalChunks = 1;
  begin.fenceCrc32 = 123;
  begin.fenceVersion = 1;
  begin.coordEncoding = 1;
  begin.pointStrideBytes = 8;
  const size_t beginLen = rpv2::encodeFrame(header, begin, frame, sizeof(frame));
  assert(beginLen > 0);
  assert(exactWireLenForPayload(frame, static_cast<uint8_t>(beginLen)) <= 128);

  header.msgType = rpv2::FENCE_POINTS;
  header.fragmentIndex = 1;
  header.fragmentTotal = 1;
  rpv2::FencePointsPrefix prefix{};
  prefix.startPointIndex = 0;
  prefix.pointCount = 1;
  rpv2::PointLatLonE7 point{};
  point.latE7 = -167000000;
  point.lonE7 = -492500000;
  const size_t singlePointLen = rpv2::encodePointsFrame(header, prefix, &point, 1, frame, sizeof(frame));
  assert(singlePointLen > 0);
  assert(exactWireLenForPayload(frame, static_cast<uint8_t>(singlePointLen)) <= 128);

  rpv2::PointLatLonE7 points6[6]{};
  for (int i = 0; i < 6; ++i) {
    points6[i].latE7 = -167000000 - (i * 1000);
    points6[i].lonE7 = -492500000 + (i * 1000);
  }
  uint8_t bestFit = 0;
  for (uint8_t count = 1; count <= 6; ++count) {
    prefix.pointCount = count;
    const size_t len = rpv2::encodePointsFrame(header, prefix, points6, count, frame, sizeof(frame));
    assert(len > 0);
    const uint16_t wireLen = exactWireLenForPayload(frame, static_cast<uint8_t>(len));
    if (wireLen <= 128) bestFit = count;
  }
  assert(bestFit >= 1);
  assert(bestFit < 6);
  const uint8_t plannedChunks = static_cast<uint8_t>((6 + bestFit - 1) / bestFit);
  assert(plannedChunks >= 2);

  const ProgressivePlanResult sixPointPlan = buildProgressivePlanForPoints(points6, 6);
  assert(sixPointPlan.planReady);
  assert(sixPointPlan.chunkCount >= 2);
  assert(sixPointPlan.firstAcceptedPointCount >= 1);
  assert(sixPointPlan.firstAcceptedPointCount < 6);
  assert(sixPointPlan.rejectCountBeforeFirstFit >= 1);

  const ProgressivePlanResult forcedReduction = buildForcedOversizePlan(6, 4);
  assert(forcedReduction.planReady);
  assert(forcedReduction.rejectCountBeforeFirstFit >= 1);
  assert(forcedReduction.firstAcceptedPointCount == 4);
  assert(forcedReduction.chunkCount >= 2);

  const ProgressivePlanResult forcedSinglePointFailure = buildAlwaysOversizePlan(3);
  assert(!forcedSinglePointFailure.planReady);
  assert(forcedSinglePointFailure.reason != nullptr);
  assert(strcmp(forcedSinglePointFailure.reason, "fence_single_point_chunk_too_large") == 0);

  header.msgType = rpv2::FENCE_COMMIT;
  rpv2::FenceCommitBody commit{};
  commit.totalPoints = 6;
  commit.totalChunks = 2;
  commit.fenceCrc32 = 123;
  commit.stagedCrc32Expected = 123;
  commit.activateMode = 1;
  commit.requireApplyStatus = 1;
  commit.commitToken = 321;
  const size_t commitLen = rpv2::encodeFrame(header, commit, frame, sizeof(frame));
  assert(commitLen > 0);
  assert(exactWireLenForPayload(frame, static_cast<uint8_t>(commitLen)) <= 128);

  return 0;
}
