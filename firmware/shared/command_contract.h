#pragma once

#include <stddef.h>
#include <stdint.h>

namespace rtcmd {

enum class ValidationCode : uint8_t {
  kOk = 0,
  kMissingWifiOtaEnabled,
  kAdminRequiredForLoraOnly,
  kTooFewPoints,
  kTooManyPoints,
  kInvalidPointValue,
  kPointChunkTooLarge,
  kTooManyChunks,
  kInvalidPhaseCount,
};

struct ChunkRange {
  uint8_t start = 0;
  uint8_t end = 0;
};

bool isValidCoordinate(double lat, double lon);
bool isAdminRole(const char* role);
bool isValidScopeId(const char* scopeId);
bool isTraceableCommandId(const char* commandId);
bool hasAdminModePermission(
    bool requestedByAdmin,
    const char* requestedByRole,
    const char* actorRole);
bool targetIncludesGateway(const char* target);
bool targetIncludesCollars(const char* target);

ValidationCode validateSetParamsPayload(
    bool hasWifiOtaEnabled,
    bool wifiOtaEnabled,
    bool requestedByAdmin,
    const char* requestedByRole,
    const char* actorRole);
ValidationCode validatePointCount(uint8_t pointCount, uint8_t maxPoints);
ValidationCode validatePhaseCount(uint8_t phaseCount, uint8_t maxPhases);

ValidationCode planPointChunks(
    const uint16_t* pointCosts,
    uint8_t pointCount,
    uint16_t chunkOverheadBytes,
    uint16_t maxPayloadBytes,
    uint8_t maxPoints,
    ChunkRange* outRanges,
    uint8_t outCapacity,
    uint8_t* outCount);

const char* validationCodeToReason(ValidationCode code);

}  // namespace rtcmd
