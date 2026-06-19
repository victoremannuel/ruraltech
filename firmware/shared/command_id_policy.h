#pragma once

#include <stddef.h>
#include <string.h>

namespace rtcmdid {

constexpr size_t COMMAND_ID_MAX_LEN = 128;
constexpr size_t COMMAND_ID_MAX_PAYLOAD_LEN = COMMAND_ID_MAX_LEN - 1;

enum class CopyResult : unsigned char {
  kOk = 0,
  kInvalidDestination,
  kMissing,
  kTooLong,
};

inline CopyResult copyToBuffer(
    char* dst,
    size_t dstSize,
    const char* src,
    size_t* sourceLength = nullptr) {
  if (!dst || dstSize == 0) {
    return CopyResult::kInvalidDestination;
  }
  dst[0] = '\0';
  if (!src || !src[0]) {
    if (sourceLength) *sourceLength = 0;
    return CopyResult::kMissing;
  }
  const size_t len = strlen(src);
  if (sourceLength) *sourceLength = len;
  if (len >= dstSize) {
    return CopyResult::kTooLong;
  }
  memcpy(dst, src, len + 1);
  return CopyResult::kOk;
}

inline const char* copyResultReason(CopyResult result) {
  switch (result) {
    case CopyResult::kOk:
      return nullptr;
    case CopyResult::kInvalidDestination:
      return "command_id_buffer_invalid";
    case CopyResult::kMissing:
      return "missing_command_id";
    case CopyResult::kTooLong:
      return "command_id_too_long";
  }
  return "command_id_copy_failed";
}

static_assert(
    COMMAND_ID_MAX_LEN >= 96,
    "Command ID buffer is too small for AUTO_AREA_FENCE identifiers");

}  // namespace rtcmdid
