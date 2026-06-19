#pragma once

#include <Arduino.h>

namespace rpv2 {

enum ReasonCode : uint16_t {
  REASON_NONE = 0,
  REASON_PROTOCOL_UNSUPPORTED = 1,
  REASON_CAPABILITY_STALE = 2,
  REASON_DEVICE_OFFLINE = 3,
  REASON_BEGIN_TIMEOUT = 10,
  REASON_BEGIN_REJECTED = 11,
  REASON_SESSION_ALREADY_ACTIVE = 12,
  REASON_REPLAY_BLOCKED = 13,
  REASON_INVALID_HEADER = 14,
  REASON_INVALID_FIELD = 15,
  REASON_INVALID_TOTAL_POINTS = 16,
  REASON_INVALID_TOTAL_CHUNKS = 17,
  REASON_INVALID_CHUNK_INDEX = 18,
  REASON_INVALID_POINT_COUNT = 19,
  REASON_POINTS_TIMEOUT = 20,
  REASON_POINTS_OUT_OF_ORDER = 21,
  REASON_POINTS_DUPLICATED = 22,
  REASON_POINTS_OVERFLOW = 23,
  REASON_POINTS_GAP = 24,
  REASON_CRC_MISMATCH = 30,
  REASON_COMMIT_TIMEOUT = 31,
  REASON_COMMIT_REJECTED = 32,
  REASON_STAGE_NOT_COMPLETE = 33,
  REASON_STAGE_STORAGE_ERROR = 34,
  REASON_ACTIVE_STORAGE_ERROR = 35,
  REASON_APPLY_FAILED = 36,
  REASON_RETRY_EXHAUSTED = 40,
  REASON_NO_POINT_FITS_IN_FRAME = 41,
  REASON_SECURE_ENVELOPE_TOO_LARGE = 42,
  REASON_TARGET_UNKNOWN_TO_GATEWAY = 43,
  REASON_GATEWAY_RELAY_UNAVAILABLE = 44,
  REASON_SESSION_EXPIRED = 45,
  REASON_ABORTED_BY_MATRIX = 46,
  REASON_ABORTED_BY_COLLAR = 47,
};

static inline const char* reasonCodeLabel(uint16_t code) {
  switch (code) {
    case REASON_NONE: return "none";
    case REASON_PROTOCOL_UNSUPPORTED: return "protocol_unsupported";
    case REASON_CAPABILITY_STALE: return "capability_stale";
    case REASON_DEVICE_OFFLINE: return "device_offline";
    case REASON_BEGIN_TIMEOUT: return "begin_timeout";
    case REASON_BEGIN_REJECTED: return "begin_rejected";
    case REASON_SESSION_ALREADY_ACTIVE: return "session_already_active";
    case REASON_REPLAY_BLOCKED: return "replay_blocked";
    case REASON_INVALID_HEADER: return "invalid_header";
    case REASON_INVALID_FIELD: return "invalid_field";
    case REASON_INVALID_TOTAL_POINTS: return "invalid_total_points";
    case REASON_INVALID_TOTAL_CHUNKS: return "invalid_total_chunks";
    case REASON_INVALID_CHUNK_INDEX: return "invalid_chunk_index";
    case REASON_INVALID_POINT_COUNT: return "invalid_point_count";
    case REASON_POINTS_TIMEOUT: return "points_timeout";
    case REASON_POINTS_OUT_OF_ORDER: return "points_out_of_order";
    case REASON_POINTS_DUPLICATED: return "points_duplicated";
    case REASON_POINTS_OVERFLOW: return "points_overflow";
    case REASON_POINTS_GAP: return "points_gap";
    case REASON_CRC_MISMATCH: return "crc_mismatch";
    case REASON_COMMIT_TIMEOUT: return "commit_timeout";
    case REASON_COMMIT_REJECTED: return "commit_rejected";
    case REASON_STAGE_NOT_COMPLETE: return "stage_not_complete";
    case REASON_STAGE_STORAGE_ERROR: return "stage_storage_error";
    case REASON_ACTIVE_STORAGE_ERROR: return "active_storage_error";
    case REASON_APPLY_FAILED: return "apply_failed";
    case REASON_RETRY_EXHAUSTED: return "retry_exhausted";
    case REASON_NO_POINT_FITS_IN_FRAME: return "no_point_fits_in_frame";
    case REASON_SECURE_ENVELOPE_TOO_LARGE: return "secure_envelope_too_large";
    case REASON_TARGET_UNKNOWN_TO_GATEWAY: return "target_unknown_to_gateway";
    case REASON_GATEWAY_RELAY_UNAVAILABLE: return "gateway_relay_unavailable";
    case REASON_SESSION_EXPIRED: return "session_expired";
    case REASON_ABORTED_BY_MATRIX: return "aborted_by_matrix";
    case REASON_ABORTED_BY_COLLAR: return "aborted_by_collar";
    default: return "unknown";
  }
}

}  // namespace rpv2
