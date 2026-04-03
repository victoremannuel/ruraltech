#include "command_contract.h"

#include <ctype.h>
#include <math.h>
#include <string.h>

namespace rtcmd {

namespace {

const char* skipSpaces(const char* text) {
  if (text == nullptr) return "";
  while (*text != '\0' && isspace(static_cast<unsigned char>(*text))) {
    ++text;
  }
  return text;
}

bool equalsTokenIgnoreCase(const char* raw, const char* expected) {
  const char* left = skipSpaces(raw);
  const char* right = expected;
  while (*left != '\0' && *right != '\0') {
    const char a = static_cast<char>(tolower(static_cast<unsigned char>(*left)));
    const char b = static_cast<char>(tolower(static_cast<unsigned char>(*right)));
    if (a != b) return false;
    ++left;
    ++right;
  }
  while (*left != '\0' && isspace(static_cast<unsigned char>(*left))) {
    ++left;
  }
  return *left == '\0' && *right == '\0';
}

}  // namespace

bool isValidCoordinate(double lat, double lon) {
  if (!isfinite(lat) || !isfinite(lon)) return false;
  return lat >= -90.0 && lat <= 90.0 && lon >= -180.0 && lon <= 180.0;
}

bool isAdminRole(const char* role) {
  return equalsTokenIgnoreCase(role, "adm") ||
         equalsTokenIgnoreCase(role, "admin");
}

bool isValidScopeId(const char* scopeId) {
  const char* text = skipSpaces(scopeId);
  size_t count = 0;
  while (*text != '\0') {
    const unsigned char ch = static_cast<unsigned char>(*text);
    if (!isxdigit(ch)) return false;
    ++count;
    ++text;
  }
  return count == 16;
}

bool isTraceableCommandId(const char* commandId) {
  const char* text = skipSpaces(commandId);
  size_t count = 0;
  while (*text != '\0') {
    const unsigned char ch = static_cast<unsigned char>(*text);
    if (!(isalnum(ch) || ch == '-' || ch == '_')) return false;
    ++count;
    ++text;
  }
  return count >= 6;
}

bool hasAdminModePermission(
    bool requestedByAdmin,
    const char* requestedByRole,
    const char* actorRole) {
  if (requestedByAdmin) return true;
  return isAdminRole(requestedByRole) || isAdminRole(actorRole);
}

bool targetIncludesGateway(const char* target) {
  const char* normalized = skipSpaces(target);
  if (*normalized == '\0') return true;
  return equalsTokenIgnoreCase(normalized, "all") ||
         equalsTokenIgnoreCase(normalized, "gateway");
}

bool targetIncludesCollars(const char* target) {
  const char* normalized = skipSpaces(target);
  if (*normalized == '\0') return true;
  return equalsTokenIgnoreCase(normalized, "all") ||
         equalsTokenIgnoreCase(normalized, "collars") ||
         equalsTokenIgnoreCase(normalized, "collar");
}

ValidationCode validateSetParamsPayload(
    bool hasWifiOtaEnabled,
    bool wifiOtaEnabled,
    bool requestedByAdmin,
    const char* requestedByRole,
    const char* actorRole) {
  if (!hasWifiOtaEnabled) return ValidationCode::kMissingWifiOtaEnabled;
  if (wifiOtaEnabled) return ValidationCode::kOk;
  return hasAdminModePermission(requestedByAdmin, requestedByRole, actorRole)
      ? ValidationCode::kOk
      : ValidationCode::kAdminRequiredForLoraOnly;
}

ValidationCode validatePointCount(uint8_t pointCount, uint8_t maxPoints) {
  if (pointCount < 3) return ValidationCode::kTooFewPoints;
  if (pointCount > maxPoints) return ValidationCode::kTooManyPoints;
  return ValidationCode::kOk;
}

ValidationCode validatePhaseCount(uint8_t phaseCount, uint8_t maxPhases) {
  if (phaseCount == 0 || phaseCount > maxPhases) {
    return ValidationCode::kInvalidPhaseCount;
  }
  return ValidationCode::kOk;
}

ValidationCode planPointChunks(
    const uint16_t* pointCosts,
    uint8_t pointCount,
    uint16_t chunkOverheadBytes,
    uint16_t maxPayloadBytes,
    uint8_t maxPoints,
    ChunkRange* outRanges,
    uint8_t outCapacity,
    uint8_t* outCount) {
  if (outCount == nullptr || outRanges == nullptr || pointCosts == nullptr) {
    return ValidationCode::kInvalidPointValue;
  }
  *outCount = 0;

  const ValidationCode pointCountValidation =
      validatePointCount(pointCount, maxPoints);
  if (pointCountValidation != ValidationCode::kOk) {
    return pointCountValidation;
  }
  if (chunkOverheadBytes >= maxPayloadBytes) {
    return ValidationCode::kPointChunkTooLarge;
  }

  uint8_t start = 0;
  while (start < pointCount) {
    uint16_t used = chunkOverheadBytes;
    uint8_t end = start;

    while (end < pointCount) {
      const uint16_t pointCost = pointCosts[end];
      if (pointCost == 0) return ValidationCode::kInvalidPointValue;
      if (used >= maxPayloadBytes || pointCost > (uint16_t)(maxPayloadBytes - used)) {
        break;
      }
      used = static_cast<uint16_t>(used + pointCost);
      ++end;
    }

    if (end == start) return ValidationCode::kPointChunkTooLarge;
    if (*outCount >= outCapacity) return ValidationCode::kTooManyChunks;

    outRanges[*outCount].start = start;
    outRanges[*outCount].end = end;
    *outCount = static_cast<uint8_t>(*outCount + 1);

    if (*outCount > maxPoints) return ValidationCode::kTooManyChunks;
    start = end;
  }

  return ValidationCode::kOk;
}

const char* validationCodeToReason(ValidationCode code) {
  switch (code) {
    case ValidationCode::kOk:
      return nullptr;
    case ValidationCode::kMissingWifiOtaEnabled:
      return "missing_wifi_ota_enabled";
    case ValidationCode::kAdminRequiredForLoraOnly:
      return "admin_required_for_lora_only";
    case ValidationCode::kTooFewPoints:
      return "too_few_points";
    case ValidationCode::kTooManyPoints:
      return "too_many_points";
    case ValidationCode::kInvalidPointValue:
      return "invalid_point_value";
    case ValidationCode::kPointChunkTooLarge:
      return "point_chunk_too_large";
    case ValidationCode::kTooManyChunks:
      return "too_many_chunks";
    case ValidationCode::kInvalidPhaseCount:
      return "invalid_phase_count";
  }
  return "invalid_payload";
}

}  // namespace rtcmd
