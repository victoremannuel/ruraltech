#include <assert.h>
#include <string.h>

#include "../../gateway-matriz/FenceRpv2Planner.h"

namespace {
struct IntegrationState {
  bool plannerCalled = false;
  uint16_t candidateEvalCount = 0;
  uint16_t rejectCount = 0;
  uint16_t fitCount = 0;
  uint16_t finalCount = 0;
};

static bool measureProgressive(
    const rpv2::EncodedPoint*,
    uint16_t,
    uint16_t pointCount,
    const rpv2fenceplanner::PlannerContext&,
    rpv2fenceplanner::MeasuredCandidate* measured,
    void*) {
  measured->encodeOk = true;
  measured->measurementOk = true;
  measured->plainFrameSize = static_cast<uint16_t>(40 + (pointCount * 8));
  measured->secureWireSize = static_cast<uint16_t>(86 + (pointCount * 8));
  measured->wireLenFinal = measured->secureWireSize;
  measured->reason = measured->wireLenFinal > 128 ? "secure_envelope_too_large" : nullptr;
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
  measured->plainFrameSize = 100;
  measured->secureWireSize = static_cast<uint16_t>(129 + pointCount);
  measured->wireLenFinal = measured->secureWireSize;
  measured->reason = "secure_envelope_too_large";
  return true;
}

static void logEvent(const rpv2fenceplanner::LogEvent& event, void* userData) {
  IntegrationState* state = static_cast<IntegrationState*>(userData);
  if (!state || !event.eventType) return;
  if (strcmp(event.eventType, "RPV2_PLAN_ENTER") == 0) state->plannerCalled = true;
  if (strcmp(event.eventType, "RPV2_PLAN_CANDIDATE_EVAL") == 0) state->candidateEvalCount++;
  if (strcmp(event.eventType, "RPV2_PLAN_CHUNK_REJECT") == 0) state->rejectCount++;
  if (strcmp(event.eventType, "RPV2_PLAN_CHUNK_FIT") == 0) state->fitCount++;
  if (strcmp(event.eventType, "RPV2_PLAN_FINAL") == 0) state->finalCount++;
}

static bool simulateCloudDispatch(
    const rpv2::EncodedPoint* points,
    uint16_t pointCount,
    rpv2fenceplanner::MeasureCandidateFn measureFn,
    IntegrationState* state,
    rpv2fenceplanner::DispatchDecision* dispatchDecision,
    Rpv2FenceChunkPlan* planOut) {
  rpv2fenceplanner::PlannerContext ctx{};
  ctx.deviceId = 123;
  ctx.scopeId = 0xDEADBEEF00000001ULL;
  ctx.radioCommandId = 0x1122334455667788ULL;
  ctx.sessionNonce = 0xA1B2C3D4UL;
  ctx.commandId = "cloud-cmd";
  ctx.source = "cloud_queue";
  ctx.plannerRevision = "canonical_fence_planner_v1";
  ctx.gitShortSha = "abcdef0";
  ctx.maxWireBytes = 128;
  Rpv2FenceChunkPlan plan{};
  const bool ok = rpv2fenceplanner::buildFenceRpv2PlanStrict(
      points,
      pointCount,
      ctx,
      &plan,
      rpv2::MAX_FENCE_POINTS,
      measureFn,
      nullptr,
      logEvent,
      state);
  if (dispatchDecision) {
    *dispatchDecision = rpv2fenceplanner::decideDispatchAfterPlanning(plan);
  }
  if (planOut) *planOut = plan;
  return ok;
}
}  // namespace

int main() {
  rpv2::EncodedPoint points6[6]{};
  for (int i = 0; i < 6; ++i) {
    points6[i].latE7 = -167000000 - (i * 1000);
    points6[i].lonE7 = -492500000 + (i * 1000);
  }

  {
    IntegrationState state{};
    rpv2fenceplanner::DispatchDecision decision{};
    Rpv2FenceChunkPlan plan{};
    const bool ok = simulateCloudDispatch(
        points6,
        6,
        measureProgressive,
        &state,
        &decision,
        &plan);
    assert(ok);
    assert(state.plannerCalled);
    assert(state.candidateEvalCount >= 2);
    assert(state.rejectCount >= 1);
    assert(state.fitCount >= 1);
    assert(state.finalCount == 1);
    assert(plan.planReady);
    assert(plan.totalChunks >= 2);
    for (uint16_t i = 0; i < plan.totalChunks; ++i) {
      assert(plan.items[i].secureWireSize <= 128);
    }
    assert(decision.shouldCreateWakeSession);
    assert(!decision.shouldPublishFailure);
  }

  {
    IntegrationState state{};
    rpv2fenceplanner::DispatchDecision decision{};
    Rpv2FenceChunkPlan plan{};
    const bool ok = simulateCloudDispatch(
        points6,
        3,
        measureAlwaysOversize,
        &state,
        &decision,
        &plan);
    assert(!ok);
    assert(state.plannerCalled);
    assert(state.candidateEvalCount >= 3);
    assert(state.rejectCount >= 2);
    assert(state.finalCount == 1);
    assert(!plan.planReady);
    assert(strcmp(plan.reasonLabel, "fence_single_point_chunk_too_large") == 0);
    assert(!decision.shouldCreateWakeSession);
    assert(decision.shouldPublishFailure);
    assert(decision.shouldClearCommand);
  }

  return 0;
}
