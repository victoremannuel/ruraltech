#include <assert.h>
#include <string.h>

#include "../shared/radio_proto_v2_codec.h"
#include "../shared/radio_proto_v2_crc.h"
#include "../shared/radio_proto_v2_planner_support.h"
#include "../../gateway-matriz/FenceRpv2Planner.h"

namespace {
enum class MsgType : uint8_t {
  SET_FENCE = 10,
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

struct TestLogState {
  uint16_t finalCount = 0;
  uint16_t candidateEvalCount = 0;
  uint16_t rejectCount = 0;
  uint16_t fitCount = 0;
};

static size_t encodePlainLikeGateway(const LoRaFrameStub& f) {
  return 4 + 8 + 1 + 4 + 4 + 12 + 1 + f.payloadLen + 16;
}

static uint16_t exactWireLenForPayload(const uint8_t* payload, uint8_t payloadLen) {
  LoRaFrameStub tx;
  tx.deviceId = 123;
  tx.scopeId = 0xDEADBEEF00000001ULL;
  tx.payloadLen = payloadLen;
  memcpy(tx.payload, payload, payloadLen);
  const size_t packedLen = encodePlainLikeGateway(tx);
  const size_t cipherLen = packedLen - 16;
  return static_cast<uint16_t>(12 + cipherLen + 16);
}

static bool measureCandidate(
    const rpv2::EncodedPoint* points,
    uint16_t startPointIndex,
    uint16_t pointCount,
    const rpv2fenceplanner::PlannerContext& ctx,
    rpv2fenceplanner::MeasuredCandidate* measured,
    void*) {
  uint8_t payload[128]{};
  rpv2::Header header{};
  header.protocolVersion = rpv2::PROTOCOL_VERSION;
  header.msgType = rpv2::FENCE_POINTS;
  header.flags = rpv2::FLAG_ACK_REQUIRED | rpv2::FLAG_FROM_MATRIX;
  header.headerLen = sizeof(rpv2::Header);
  header.radioCommandId = ctx.radioCommandId;
  header.sessionNonce = ctx.sessionNonce;
  header.fragmentIndex = 1;
  header.fragmentTotal = 1;
  rpv2::FencePointsPrefix prefix{};
  prefix.startPointIndex = startPointIndex;
  prefix.pointCount = static_cast<uint8_t>(pointCount);
  const size_t len = rpv2::encodePointsFrame(
      header,
      prefix,
      reinterpret_cast<const rpv2::PointLatLonE7*>(points + startPointIndex),
      prefix.pointCount,
      payload,
      sizeof(payload));
  measured->encodeOk = len > 0;
  measured->plainFrameSize = static_cast<uint16_t>(len);
  if (!measured->encodeOk) {
    measured->reason = "points_encode_failed";
    return false;
  }
  measured->measurementOk = true;
  measured->secureWireSize = exactWireLenForPayload(payload, static_cast<uint8_t>(len));
  measured->wireLenFinal = measured->secureWireSize;
  return true;
}

static bool measureAlwaysOversize(
    const rpv2::EncodedPoint*,
    uint16_t,
    uint16_t pointCount,
    const rpv2fenceplanner::PlannerContext&,
    rpv2fenceplanner::MeasuredCandidate* measured,
    void*) {
  measured->encodeOk = true;
  measured->measurementOk = true;
  measured->plainFrameSize = 96;
  measured->secureWireSize = static_cast<uint16_t>(129 + pointCount);
  measured->wireLenFinal = measured->secureWireSize;
  measured->reason = "secure_envelope_too_large";
  return true;
}

static void captureLog(const rpv2fenceplanner::LogEvent& event, void* userData) {
  TestLogState* state = static_cast<TestLogState*>(userData);
  if (!state || !event.eventType) return;
  if (strcmp(event.eventType, "RPV2_PLAN_CANDIDATE_EVAL") == 0) state->candidateEvalCount++;
  if (strcmp(event.eventType, "RPV2_PLAN_CHUNK_REJECT") == 0) state->rejectCount++;
  if (strcmp(event.eventType, "RPV2_PLAN_CHUNK_FIT") == 0) state->fitCount++;
  if (strcmp(event.eventType, "RPV2_PLAN_FINAL") == 0) state->finalCount++;
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
    assert(strcmp(reducible.reason, "secure_envelope_too_large") == 0);
  }

  rpv2::EncodedPoint points6[6]{};
  for (int i = 0; i < 6; ++i) {
    points6[i].latE7 = -167000000 - (i * 1000);
    points6[i].lonE7 = -492500000 + (i * 1000);
  }

  rpv2fenceplanner::PlannerContext ctx{};
  ctx.deviceId = 123;
  ctx.scopeId = 0xDEADBEEF00000001ULL;
  ctx.radioCommandId = 0x1122334455667788ULL;
  ctx.sessionNonce = 0xA1B2C3D4UL;
  ctx.commandId = "cmd-1";
  ctx.source = "cloud_queue";
  ctx.plannerRevision = "canonical_fence_planner_v1";
  ctx.gitShortSha = "abcdef0";
  ctx.maxWireBytes = 128;

  {
    Rpv2FenceChunkPlan plan{};
    TestLogState logState{};
    const bool ok = rpv2fenceplanner::buildFenceRpv2PlanStrict(
        points6,
        6,
        ctx,
        &plan,
        rpv2::MAX_FENCE_POINTS,
        measureCandidate,
        nullptr,
        captureLog,
        &logState);
    assert(ok);
    assert(plan.planReady);
    assert(plan.candidateEvalCount >= 2);
    assert(plan.rejectCount >= 1);
    assert(plan.fitCount >= 1);
    assert(plan.totalChunks >= 2);
    assert(plan.totalPoints == 6);
    assert(logState.candidateEvalCount == plan.candidateEvalCount);
    assert(logState.rejectCount == plan.rejectCount);
    assert(logState.fitCount == plan.fitCount);
    assert(logState.finalCount == 1);
    for (uint16_t i = 0; i < plan.totalChunks; ++i) {
      assert(plan.items[i].secureWireSize <= 128);
    }
    const rpv2fenceplanner::DispatchDecision decision =
        rpv2fenceplanner::decideDispatchAfterPlanning(plan);
    assert(decision.shouldCreateWakeSession);
    assert(!decision.shouldPublishFailure);
  }

  {
    Rpv2FenceChunkPlan plan{};
    TestLogState logState{};
    const bool ok = rpv2fenceplanner::buildFenceRpv2PlanStrict(
        points6,
        3,
        ctx,
        &plan,
        rpv2::MAX_FENCE_POINTS,
        measureAlwaysOversize,
        nullptr,
        captureLog,
        &logState);
    assert(!ok);
    assert(!plan.planReady);
    assert(plan.candidateEvalCount >= 3);
    assert(plan.rejectCount >= 2);
    assert(logState.finalCount == 1);
    assert(strcmp(plan.reasonLabel, "fence_single_point_chunk_too_large") == 0);
    const rpv2fenceplanner::DispatchDecision decision =
        rpv2fenceplanner::decideDispatchAfterPlanning(plan);
    assert(!decision.shouldCreateWakeSession);
    assert(decision.shouldPublishFailure);
    assert(decision.shouldClearCommand);
  }

  return 0;
}
