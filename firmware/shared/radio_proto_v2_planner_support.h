#pragma once

#include <stdint.h>

namespace rpv2plan {

struct CandidateDecision {
  bool measurementOk = false;
  bool fitsLimit = false;
  bool reducibleOversize = false;
  bool terminalCodecError = false;
  bool terminalSinglePointOversize = false;
  const char* reason = "codec_or_buffer_error";
};

static inline CandidateDecision classifyCandidate(
    bool encodeOk,
    bool measurementOk,
    uint16_t wireLenFinal,
    uint16_t limit,
    const char* measuredReason,
    uint16_t candidateCount) {
  CandidateDecision decision{};
  decision.measurementOk = encodeOk && measurementOk;
  decision.fitsLimit = decision.measurementOk && wireLenFinal <= limit;
  if (decision.fitsLimit) {
    decision.reason = nullptr;
    return decision;
  }

  const bool oversize = decision.measurementOk && wireLenFinal > limit;
  if (oversize && candidateCount > 1) {
    decision.reducibleOversize = true;
    decision.reason = "secure_envelope_too_large";
    return decision;
  }
  if (oversize) {
    decision.terminalSinglePointOversize = true;
    decision.reason = "fence_single_point_chunk_too_large";
    return decision;
  }

  decision.terminalCodecError = true;
  decision.reason =
      measuredReason && measuredReason[0] ? measuredReason : "codec_or_buffer_error";
  return decision;
}

}  // namespace rpv2plan
