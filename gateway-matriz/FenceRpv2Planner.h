#pragma once

#include <stdint.h>
#include <string.h>

#include "../firmware/shared/radio_proto_v2_codec.h"
#include "../firmware/shared/radio_proto_v2_crc.h"
#include "../firmware/shared/radio_proto_v2_planner_support.h"
#include "../firmware/shared/radio_proto_v2_reason_codes.h"

struct Rpv2FenceChunkPlanItem {
  uint16_t fragmentIndex = 0;
  uint16_t startPointIndex = 0;
  uint8_t pointCount = 0;
  uint16_t plainFrameSize = 0;
  uint16_t secureWireSize = 0;
};

struct Rpv2FenceChunkPlan {
  bool planReady = false;
  uint16_t totalPoints = 0;
  uint16_t totalChunks = 0;
  uint16_t candidateEvalCount = 0;
  uint16_t rejectCount = 0;
  uint16_t fitCount = 0;
  uint16_t minWireLen = 0;
  uint16_t maxWireLen = 0;
  uint16_t lastReasonCode = rpv2::REASON_NONE;
  uint32_t fenceCrc32 = 0;
  uint32_t fenceVersion = 1;
  char reasonLabel[48]{};
  rpv2::EncodedPoint points[rpv2::MAX_FENCE_POINTS]{};
  Rpv2FenceChunkPlanItem items[rpv2::MAX_FENCE_POINTS]{};
};

namespace rpv2fenceplanner {

struct PlannerContext {
  uint32_t deviceId = 0;
  uint64_t scopeId = 0;
  uint64_t radioCommandId = 0;
  uint32_t sessionNonce = 0;
  const char* commandId = nullptr;
  const char* source = nullptr;
  const char* plannerRevision = "canonical_fence_planner_v1";
  const char* gitShortSha = nullptr;
  uint16_t maxWireBytes = 128;
};

struct MeasuredCandidate {
  bool encodeOk = false;
  bool measurementOk = false;
  uint16_t plainFrameSize = 0;
  uint16_t secureWireSize = 0;
  uint16_t wireLenFinal = 0;
  const char* reason = nullptr;
};

struct LogEvent {
  const char* eventType = nullptr;
  const char* classification = nullptr;
  const char* reason = nullptr;
  const char* source = nullptr;
  const char* plannerRevision = nullptr;
  const char* gitShortSha = nullptr;
  const char* commandId = nullptr;
  uint32_t deviceId = 0;
  uint64_t radioCommandId = 0;
  uint16_t totalPoints = 0;
  uint16_t chunkCount = 0;
  uint16_t fragmentIndex = 0;
  uint16_t startPointIndex = 0;
  uint16_t endPointIndex = 0;
  uint16_t pointCount = 0;
  uint16_t plainFrameSize = 0;
  uint16_t secureWireSize = 0;
  uint16_t wireLenFinal = 0;
  uint16_t limit = 0;
  bool measurementOk = false;
  bool fitsLimit = false;
  bool planReady = false;
};

using MeasureCandidateFn = bool (*)(
    const rpv2::EncodedPoint* points,
    uint16_t startPointIndex,
    uint16_t pointCount,
    const PlannerContext& ctx,
    MeasuredCandidate* measured,
    void* userData);

using LogEventFn = void (*)(const LogEvent& event, void* userData);

struct DispatchDecision {
  bool shouldCreateWakeSession = false;
  bool shouldPublishFailure = false;
  bool shouldClearCommand = false;
  const char* failureReason = nullptr;
  uint16_t reasonCode = rpv2::REASON_NONE;
};

static inline uint16_t reasonCodeFromLabel(const char* reason) {
  if (!reason || !reason[0]) return rpv2::REASON_NONE;
  if (strcmp(reason, "fence_single_point_chunk_too_large") == 0) {
    return rpv2::REASON_SECURE_ENVELOPE_TOO_LARGE;
  }
  if (strcmp(reason, "secure_envelope_too_large") == 0) {
    return rpv2::REASON_SECURE_ENVELOPE_TOO_LARGE;
  }
  if (strcmp(reason, "codec_or_buffer_error") == 0) {
    return rpv2::REASON_NO_POINT_FITS_IN_FRAME;
  }
  if (strcmp(reason, "planner_or_dispatch_stall") == 0) {
    return rpv2::REASON_RETRY_EXHAUSTED;
  }
  return rpv2::REASON_NO_POINT_FITS_IN_FRAME;
}

static inline DispatchDecision decideDispatchAfterPlanning(const Rpv2FenceChunkPlan& plan) {
  DispatchDecision decision{};
  if (plan.planReady) {
    decision.shouldCreateWakeSession = true;
    return decision;
  }
  decision.shouldPublishFailure = true;
  decision.shouldClearCommand = true;
  decision.failureReason = plan.reasonLabel[0] ? plan.reasonLabel : "plan_failed";
  decision.reasonCode = plan.lastReasonCode;
  return decision;
}

static inline void emitLog(
    const LogEventFn logFn,
    void* logUserData,
    const LogEvent& event) {
  if (logFn) logFn(event, logUserData);
}

static inline bool buildFenceRpv2PlanStrict(
    const rpv2::EncodedPoint* points,
    uint16_t pointCount,
    const PlannerContext& ctx,
    Rpv2FenceChunkPlan* plan,
    uint16_t maxChunks,
    const MeasureCandidateFn measureFn,
    void* measureUserData,
    const LogEventFn logFn = nullptr,
    void* logUserData = nullptr) {
  if (!plan || !points || !measureFn) return false;
  *plan = Rpv2FenceChunkPlan{};
  plan->totalPoints = pointCount;

  LogEvent event{};
  event.commandId = ctx.commandId;
  event.deviceId = ctx.deviceId;
  event.radioCommandId = ctx.radioCommandId;
  event.totalPoints = pointCount;
  event.limit = ctx.maxWireBytes;
  event.source = ctx.source;
  event.plannerRevision = ctx.plannerRevision;
  event.gitShortSha = ctx.gitShortSha;

  LogEvent enterEvent{};
  enterEvent.eventType = "RPV2_PLAN_ENTER";
  enterEvent.source = ctx.source;
  enterEvent.commandId = ctx.commandId;
  enterEvent.deviceId = ctx.deviceId;
  enterEvent.radioCommandId = ctx.radioCommandId;
  enterEvent.totalPoints = pointCount;
  enterEvent.limit = ctx.maxWireBytes;
  emitLog(logFn, logUserData, enterEvent);
  LogEvent revEvent{};
  revEvent.eventType = "RPV2_PLANNER_REV";
  revEvent.plannerRevision = ctx.plannerRevision;
  revEvent.gitShortSha = ctx.gitShortSha;
  emitLog(logFn, logUserData, revEvent);

  if (pointCount < rpv2::MIN_FENCE_POINTS || pointCount > rpv2::MAX_FENCE_POINTS) {
    strncpy(plan->reasonLabel, "invalid_point_count", sizeof(plan->reasonLabel) - 1);
    plan->lastReasonCode = rpv2::REASON_INVALID_POINT_COUNT;
    LogEvent failedEvent{};
    failedEvent.eventType = "RPV2_PLAN_FAILED_TERMINAL";
    failedEvent.reason = plan->reasonLabel;
    failedEvent.commandId = ctx.commandId;
    failedEvent.deviceId = ctx.deviceId;
    failedEvent.radioCommandId = ctx.radioCommandId;
    failedEvent.pointCount = pointCount;
    failedEvent.limit = ctx.maxWireBytes;
    emitLog(logFn, logUserData, failedEvent);
    LogEvent finalEvent{};
    finalEvent.eventType = "RPV2_PLAN_FINAL";
    finalEvent.reason = plan->reasonLabel;
    finalEvent.commandId = ctx.commandId;
    finalEvent.deviceId = ctx.deviceId;
    finalEvent.chunkCount = 0;
    finalEvent.totalPoints = pointCount;
    finalEvent.planReady = false;
    finalEvent.plainFrameSize = plan->minWireLen;
    finalEvent.wireLenFinal = plan->maxWireLen;
    emitLog(logFn, logUserData, finalEvent);
    return false;
  }

  memcpy(plan->points, points, sizeof(rpv2::EncodedPoint) * pointCount);
  plan->fenceCrc32 =
      rpv2fencecrc::computeCanonicalFenceCrc(plan->points, pointCount);

  uint16_t startPointIndex = 0;
  while (startPointIndex < pointCount) {
    const uint16_t remaining = pointCount - startPointIndex;
    uint16_t candidateCount = remaining;
    bool accepted = false;

    while (candidateCount >= 1) {
      MeasuredCandidate measured{};
      const bool measuredCallOk = measureFn(
          plan->points,
          startPointIndex,
          candidateCount,
          ctx,
          &measured,
          measureUserData);
      if (!measuredCallOk && !measured.reason) {
        measured.reason = "codec_or_buffer_error";
      }
      const rpv2plan::CandidateDecision decision = rpv2plan::classifyCandidate(
          measured.encodeOk,
          measured.measurementOk,
          measured.wireLenFinal,
          ctx.maxWireBytes,
          measured.reason,
          candidateCount);
      const char* classification = decision.fitsLimit
          ? "fit"
          : decision.reducibleOversize
              ? "oversize_reducible"
              : decision.terminalSinglePointOversize
                  ? "oversize_terminal_single_point"
                  : "codec_or_buffer_error";
      plan->candidateEvalCount++;
      LogEvent evalEvent{};
      evalEvent.eventType = "RPV2_PLAN_CANDIDATE_EVAL";
      evalEvent.classification = classification;
      evalEvent.reason = decision.reason;
      evalEvent.commandId = ctx.commandId;
      evalEvent.deviceId = ctx.deviceId;
      evalEvent.radioCommandId = ctx.radioCommandId;
      evalEvent.fragmentIndex = static_cast<uint16_t>(plan->totalChunks + 1);
      evalEvent.startPointIndex = startPointIndex;
      evalEvent.endPointIndex = static_cast<uint16_t>(startPointIndex + candidateCount - 1);
      evalEvent.pointCount = candidateCount;
      evalEvent.plainFrameSize = measured.plainFrameSize;
      evalEvent.secureWireSize = measured.secureWireSize;
      evalEvent.wireLenFinal = measured.wireLenFinal;
      evalEvent.limit = ctx.maxWireBytes;
      evalEvent.measurementOk = decision.measurementOk;
      evalEvent.fitsLimit = decision.fitsLimit;
      emitLog(logFn, logUserData, evalEvent);

      if (decision.fitsLimit) {
        if (plan->totalChunks >= maxChunks) {
          strncpy(plan->reasonLabel, "plan_capacity_exhausted", sizeof(plan->reasonLabel) - 1);
          plan->lastReasonCode = rpv2::REASON_NO_POINT_FITS_IN_FRAME;
          LogEvent capacityFailedEvent{};
          capacityFailedEvent.eventType = "RPV2_PLAN_FAILED_TERMINAL";
          capacityFailedEvent.classification = "plan_capacity_exhausted";
          capacityFailedEvent.reason = plan->reasonLabel;
          capacityFailedEvent.commandId = ctx.commandId;
          capacityFailedEvent.deviceId = ctx.deviceId;
          capacityFailedEvent.radioCommandId = ctx.radioCommandId;
          capacityFailedEvent.fragmentIndex = static_cast<uint16_t>(plan->totalChunks + 1);
          capacityFailedEvent.startPointIndex = startPointIndex;
          capacityFailedEvent.pointCount = candidateCount;
          capacityFailedEvent.wireLenFinal = measured.wireLenFinal;
          capacityFailedEvent.limit = ctx.maxWireBytes;
          emitLog(logFn, logUserData, capacityFailedEvent);
          LogEvent capacityFinalEvent{};
          capacityFinalEvent.eventType = "RPV2_PLAN_FINAL";
          capacityFinalEvent.reason = plan->reasonLabel;
          capacityFinalEvent.commandId = ctx.commandId;
          capacityFinalEvent.deviceId = ctx.deviceId;
          capacityFinalEvent.chunkCount = plan->totalChunks;
          capacityFinalEvent.totalPoints = pointCount;
          capacityFinalEvent.planReady = false;
          capacityFinalEvent.plainFrameSize = plan->minWireLen;
          capacityFinalEvent.wireLenFinal = plan->maxWireLen;
          emitLog(logFn, logUserData, capacityFinalEvent);
          return false;
        }
        Rpv2FenceChunkPlanItem& item = plan->items[plan->totalChunks];
        item.fragmentIndex = static_cast<uint16_t>(plan->totalChunks + 1);
        item.startPointIndex = startPointIndex;
        item.pointCount = static_cast<uint8_t>(candidateCount);
        item.plainFrameSize = measured.plainFrameSize;
        item.secureWireSize = measured.secureWireSize;
        plan->totalChunks++;
        plan->fitCount++;
        if (plan->minWireLen == 0 || measured.wireLenFinal < plan->minWireLen) {
          plan->minWireLen = measured.wireLenFinal;
        }
        if (measured.wireLenFinal > plan->maxWireLen) {
          plan->maxWireLen = measured.wireLenFinal;
        }
        LogEvent fitEvent{};
        fitEvent.eventType = "RPV2_PLAN_CHUNK_FIT";
        fitEvent.classification = classification;
        fitEvent.commandId = ctx.commandId;
        fitEvent.deviceId = ctx.deviceId;
        fitEvent.radioCommandId = ctx.radioCommandId;
        fitEvent.fragmentIndex = item.fragmentIndex;
        fitEvent.startPointIndex = item.startPointIndex;
        fitEvent.pointCount = item.pointCount;
        fitEvent.plainFrameSize = item.plainFrameSize;
        fitEvent.secureWireSize = item.secureWireSize;
        fitEvent.wireLenFinal = measured.wireLenFinal;
        fitEvent.limit = ctx.maxWireBytes;
        fitEvent.measurementOk = true;
        fitEvent.fitsLimit = true;
        emitLog(logFn, logUserData, fitEvent);
        startPointIndex = static_cast<uint16_t>(startPointIndex + candidateCount);
        accepted = true;
        break;
      }

      if (decision.reducibleOversize) {
        plan->rejectCount++;
        LogEvent rejectEvent{};
        rejectEvent.eventType = "RPV2_PLAN_CHUNK_REJECT";
        rejectEvent.classification = classification;
        rejectEvent.reason = decision.reason;
        rejectEvent.commandId = ctx.commandId;
        rejectEvent.deviceId = ctx.deviceId;
        rejectEvent.radioCommandId = ctx.radioCommandId;
        rejectEvent.fragmentIndex = static_cast<uint16_t>(plan->totalChunks + 1);
        rejectEvent.startPointIndex = startPointIndex;
        rejectEvent.pointCount = candidateCount;
        rejectEvent.wireLenFinal = measured.wireLenFinal;
        rejectEvent.limit = ctx.maxWireBytes;
        emitLog(logFn, logUserData, rejectEvent);
        candidateCount--;
        continue;
      }

      strncpy(
          plan->reasonLabel,
          decision.reason ? decision.reason : "codec_or_buffer_error",
          sizeof(plan->reasonLabel) - 1);
      plan->lastReasonCode = reasonCodeFromLabel(plan->reasonLabel);
      LogEvent terminalEvent{};
      terminalEvent.eventType = "RPV2_PLAN_FAILED_TERMINAL";
      terminalEvent.classification = classification;
      terminalEvent.reason = plan->reasonLabel;
      terminalEvent.commandId = ctx.commandId;
      terminalEvent.deviceId = ctx.deviceId;
      terminalEvent.radioCommandId = ctx.radioCommandId;
      terminalEvent.fragmentIndex = static_cast<uint16_t>(plan->totalChunks + 1);
      terminalEvent.startPointIndex = startPointIndex;
      terminalEvent.pointCount = candidateCount;
      terminalEvent.wireLenFinal = measured.wireLenFinal;
      terminalEvent.limit = ctx.maxWireBytes;
      emitLog(logFn, logUserData, terminalEvent);
      LogEvent terminalFinalEvent{};
      terminalFinalEvent.eventType = "RPV2_PLAN_FINAL";
      terminalFinalEvent.reason = plan->reasonLabel;
      terminalFinalEvent.commandId = ctx.commandId;
      terminalFinalEvent.deviceId = ctx.deviceId;
      terminalFinalEvent.chunkCount = plan->totalChunks;
      terminalFinalEvent.totalPoints = pointCount;
      terminalFinalEvent.planReady = false;
      terminalFinalEvent.plainFrameSize = plan->minWireLen;
      terminalFinalEvent.wireLenFinal = plan->maxWireLen;
      emitLog(logFn, logUserData, terminalFinalEvent);
      return false;
    }

    if (!accepted) {
      if (!plan->reasonLabel[0]) {
        strncpy(plan->reasonLabel, "codec_or_buffer_error", sizeof(plan->reasonLabel) - 1);
        plan->lastReasonCode = reasonCodeFromLabel(plan->reasonLabel);
      }
      LogEvent incompleteFinalEvent{};
      incompleteFinalEvent.eventType = "RPV2_PLAN_FINAL";
      incompleteFinalEvent.reason = plan->reasonLabel;
      incompleteFinalEvent.commandId = ctx.commandId;
      incompleteFinalEvent.deviceId = ctx.deviceId;
      incompleteFinalEvent.chunkCount = plan->totalChunks;
      incompleteFinalEvent.totalPoints = pointCount;
      incompleteFinalEvent.planReady = false;
      incompleteFinalEvent.plainFrameSize = plan->minWireLen;
      incompleteFinalEvent.wireLenFinal = plan->maxWireLen;
      emitLog(logFn, logUserData, incompleteFinalEvent);
      return false;
    }
  }

  plan->planReady = true;
  plan->lastReasonCode = rpv2::REASON_NONE;
  plan->reasonLabel[0] = '\0';
  LogEvent readyFinalEvent{};
  readyFinalEvent.eventType = "RPV2_PLAN_FINAL";
  readyFinalEvent.commandId = ctx.commandId;
  readyFinalEvent.deviceId = ctx.deviceId;
  readyFinalEvent.chunkCount = plan->totalChunks;
  readyFinalEvent.totalPoints = pointCount;
  readyFinalEvent.planReady = true;
  readyFinalEvent.plainFrameSize = plan->minWireLen;
  readyFinalEvent.wireLenFinal = plan->maxWireLen;
  emitLog(logFn, logUserData, readyFinalEvent);
  return true;
}

}  // namespace rpv2fenceplanner
