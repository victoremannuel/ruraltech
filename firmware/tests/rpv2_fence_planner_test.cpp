#include <assert.h>
#include <initializer_list>
#include <string.h>

#include "../../gateway-matriz/FenceRpv2Planner.h"

namespace {
struct MeasurePolicy {
  uint16_t maxFit = 5;
  uint16_t failAtOrAbove = 0;
  uint16_t maxCandidateSeen = 0;
};

struct TestLogState {
  uint16_t finalCount = 0;
  uint16_t terminalCount = 0;
  uint16_t reducibleMeasurementRejects = 0;
};

static bool measureCandidate(
    const rpv2::EncodedPoint*,
    uint16_t,
    uint16_t pointCount,
    const rpv2fenceplanner::PlannerContext&,
    rpv2fenceplanner::MeasuredCandidate* measured,
    void* userData) {
  MeasurePolicy* policy = static_cast<MeasurePolicy*>(userData);
  assert(policy);
  if (pointCount > policy->maxCandidateSeen) policy->maxCandidateSeen = pointCount;

  if (policy->failAtOrAbove != 0 && pointCount >= policy->failAtOrAbove) {
    measured->reason = "points_encode_failed";
    return false;
  }

  measured->encodeOk = true;
  measured->measurementOk = true;
  measured->plainFrameSize = static_cast<uint16_t>(40 + pointCount * 8);
  measured->secureWireSize = static_cast<uint16_t>(86 + pointCount * 8);
  measured->wireLenFinal = measured->secureWireSize;
  if (pointCount > policy->maxFit) {
    measured->reason = "secure_envelope_too_large";
  }
  return true;
}

static void captureLog(const rpv2fenceplanner::LogEvent& event, void* userData) {
  TestLogState* state = static_cast<TestLogState*>(userData);
  if (!state || !event.eventType) return;
  if (strcmp(event.eventType, "RPV2_PLAN_FINAL") == 0) state->finalCount++;
  if (strcmp(event.eventType, "RPV2_PLAN_FAILED_TERMINAL") == 0) state->terminalCount++;
  if (strcmp(event.eventType, "RPV2_PLAN_CHUNK_REJECT") == 0 &&
      event.classification &&
      strcmp(event.classification, "codec_or_buffer_error_reducible") == 0 &&
      event.reason &&
      strcmp(event.reason, "candidate_measure_failed_reducing") == 0) {
    state->reducibleMeasurementRejects++;
  }
}

static rpv2fenceplanner::PlannerContext defaultContext() {
  rpv2fenceplanner::PlannerContext ctx{};
  ctx.deviceId = 123;
  ctx.scopeId = 0xDEADBEEF00000001ULL;
  ctx.radioCommandId = 0x1122334455667788ULL;
  ctx.sessionNonce = 0xA1B2C3D4UL;
  ctx.commandId = "AUTO_AREA_FENCE:test:1234567890ABCDEF:23A00185B336A70A";
  ctx.source = "cloud_queue";
  ctx.plannerRevision = "canonical_fence_planner_v1";
  ctx.gitShortSha = "abcdef0";
  ctx.maxWireBytes = 128;
  return ctx;
}

static void fillPoints(rpv2::EncodedPoint* points, uint16_t count) {
  for (uint16_t i = 0; i < count; ++i) {
    points[i].latE7 = -167000000 - static_cast<int32_t>(i * 1000);
    points[i].lonE7 = -492500000 + static_cast<int32_t>(i * 1000);
  }
}

static void assertPlan(
    uint16_t pointCount,
    std::initializer_list<uint8_t> expectedChunks) {
  rpv2::EncodedPoint points[rpv2::MAX_FENCE_POINTS]{};
  fillPoints(points, pointCount);
  MeasurePolicy policy{};
  TestLogState logs{};
  Rpv2FenceChunkPlan plan{};
  const rpv2fenceplanner::PlannerContext ctx = defaultContext();

  const bool ok = rpv2fenceplanner::buildFenceRpv2PlanStrict(
      points,
      pointCount,
      ctx,
      &plan,
      rpv2::MAX_FENCE_POINTS,
      measureCandidate,
      &policy,
      captureLog,
      &logs);

  assert(ok);
  assert(plan.planReady);
  assert(plan.totalPoints == pointCount);
  assert(plan.totalChunks == expectedChunks.size());
  assert(plan.reasonLabel[0] == '\0');
  assert(plan.lastReasonCode == rpv2::REASON_NONE);
  assert(logs.finalCount == 1);
  assert(logs.terminalCount == 0);
  assert(policy.maxCandidateSeen <= rpv2fenceplanner::kDefaultMaxFencePointsPerChunk);

  uint16_t index = 0;
  uint16_t coveredPoints = 0;
  for (const uint8_t expectedCount : expectedChunks) {
    assert(plan.items[index].fragmentIndex == index + 1);
    assert(plan.items[index].startPointIndex == coveredPoints);
    assert(plan.items[index].pointCount == expectedCount);
    assert(plan.items[index].secureWireSize <= ctx.maxWireBytes);
    coveredPoints = static_cast<uint16_t>(coveredPoints + expectedCount);
    index++;
  }
  assert(coveredPoints == pointCount);
}
}  // namespace

int main() {
  assert(rpv2fenceplanner::maxFencePointsPerChunkForWireLimit(128) == 5);
  assert(rpv2fenceplanner::maxFencePointsPerChunkForWireLimit(255) == 5);

  assertPlan(3, {3});
  assertPlan(4, {4});
  assertPlan(5, {5});
  assertPlan(6, {5, 1});
  assertPlan(7, {5, 2});
  assertPlan(8, {5, 3});
  assertPlan(12, {5, 5, 2});
  assertPlan(20, {5, 5, 5, 5});
  assertPlan(32, {5, 5, 5, 5, 5, 5, 2});

  rpv2::EncodedPoint points[rpv2::MAX_FENCE_POINTS]{};
  fillPoints(points, rpv2::MAX_FENCE_POINTS);
  const rpv2fenceplanner::PlannerContext ctx = defaultContext();

  for (const uint16_t invalidCount : {uint16_t{2}, uint16_t{33}}) {
    Rpv2FenceChunkPlan plan{};
    MeasurePolicy policy{};
    TestLogState logs{};
    const bool ok = rpv2fenceplanner::buildFenceRpv2PlanStrict(
        points,
        invalidCount,
        ctx,
        &plan,
        rpv2::MAX_FENCE_POINTS,
        measureCandidate,
        &policy,
        captureLog,
        &logs);
    assert(!ok);
    assert(strcmp(plan.reasonLabel, "invalid_point_count") == 0);
    assert(plan.lastReasonCode == rpv2::REASON_INVALID_POINT_COUNT);
    assert(logs.terminalCount == 1);
  }

  {
    Rpv2FenceChunkPlan plan{};
    MeasurePolicy policy{};
    TestLogState logs{};
    const bool ok = rpv2fenceplanner::buildFenceRpv2PlanStrict(
        points,
        32,
        ctx,
        &plan,
        6,
        measureCandidate,
        &policy,
        captureLog,
        &logs);
    assert(!ok);
    assert(strcmp(plan.reasonLabel, "plan_capacity_exhausted") == 0);
    assert(plan.lastReasonCode == rpv2::REASON_NO_POINT_FITS_IN_FRAME);
    assert(plan.totalChunks == 6);
    assert(logs.terminalCount == 1);
  }

  {
    Rpv2FenceChunkPlan plan{};
    MeasurePolicy policy{};
    policy.failAtOrAbove = 5;
    TestLogState logs{};
    const bool ok = rpv2fenceplanner::buildFenceRpv2PlanStrict(
        points,
        8,
        ctx,
        &plan,
        rpv2::MAX_FENCE_POINTS,
        measureCandidate,
        &policy,
        captureLog,
        &logs);
    assert(ok);
    assert(plan.totalChunks == 2);
    assert(plan.items[0].pointCount == 4);
    assert(plan.items[1].pointCount == 4);
    assert(logs.reducibleMeasurementRejects == 1);
    assert(logs.terminalCount == 0);
  }

  {
    Rpv2FenceChunkPlan plan{};
    MeasurePolicy policy{};
    policy.failAtOrAbove = 1;
    TestLogState logs{};
    const bool ok = rpv2fenceplanner::buildFenceRpv2PlanStrict(
        points,
        3,
        ctx,
        &plan,
        rpv2::MAX_FENCE_POINTS,
        measureCandidate,
        &policy,
        captureLog,
        &logs);
    assert(!ok);
    assert(strcmp(plan.reasonLabel, "single_point_encode_failed") == 0);
    assert(plan.lastReasonCode == rpv2::REASON_NO_POINT_FITS_IN_FRAME);
    assert(plan.rejectCount == 2);
    assert(logs.reducibleMeasurementRejects == 2);
    assert(logs.terminalCount == 1);
  }

  return 0;
}
