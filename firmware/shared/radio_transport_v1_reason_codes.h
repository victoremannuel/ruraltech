#pragma once

#include <Arduino.h>

namespace rtrv1 {

enum ReasonCode : uint16_t {
  REASON_NONE = 0,
  REASON_PAGE_TIMEOUT = 100,
  REASON_PAGE_REJECTED = 101,
  REASON_SESSION_ALREADY_ACTIVE = 102,
  REASON_INVALID_HEADER = 103,
  REASON_INVALID_FIELD = 104,
  REASON_SCOPE_MISMATCH = 105,
  REASON_BINDING_MISSING = 106,
  REASON_TARGET_MISMATCH = 107,
  REASON_LINK_ACK_TIMEOUT = 108,
  REASON_APP_ACK_TIMEOUT = 109,
  REASON_ABORTED_BY_MATRIX = 110,
  REASON_ABORTED_BY_COLLAR = 111,
  REASON_PAGE_TIMEOUT_FINAL = 112,
  REASON_PAGE_SEND_FAILED = 113,
  REASON_PAGE_ACK_INVALID = 114,
  REASON_SESSION_NOT_STARTED_AFTER_PAGE_ACK = 115,
  REASON_DROP_TARGET_MISMATCH = 200,
  REASON_DROP_SCOPE_MISMATCH = 201,
  REASON_DROP_DECRYPT_FAILED = 202,
  REASON_DROP_AUTH_FAILED = 203,
  REASON_DROP_REPLAY_BLOCKED = 204,
  REASON_DROP_DUPLICATE = 205,
  REASON_DROP_TTL_EXPIRED = 206,
  REASON_DROP_UNKNOWN_INNER_TYPE = 207,
  REASON_DROP_INVALID_FRAGMENT = 208,
  REASON_DROP_QUEUE_FULL = 209,
  REASON_DROP_ROUTE_MISSING = 210,
};

enum class RawDropReason : uint8_t {
  NONE = 0,
  DECRYPT_FAILED = 1,
  AUTH_FAILED = 2,
  SCOPE_MISMATCH = 3,
  TARGET_MISMATCH = 4,
  UNKNOWN_TYPE = 5,
  INVALID_HEADER = 6,
  REPLAY_BLOCKED = 7,
};

static inline const char* reasonCodeLabel(uint16_t code) {
  switch (code) {
    case REASON_NONE: return "none";
    case REASON_PAGE_TIMEOUT: return "page_timeout";
    case REASON_PAGE_REJECTED: return "page_rejected";
    case REASON_SESSION_ALREADY_ACTIVE: return "session_already_active";
    case REASON_INVALID_HEADER: return "invalid_header";
    case REASON_INVALID_FIELD: return "invalid_field";
    case REASON_SCOPE_MISMATCH: return "scope_mismatch";
    case REASON_BINDING_MISSING: return "binding_missing";
    case REASON_TARGET_MISMATCH: return "target_mismatch";
    case REASON_LINK_ACK_TIMEOUT: return "link_ack_timeout";
    case REASON_APP_ACK_TIMEOUT: return "app_ack_timeout";
    case REASON_ABORTED_BY_MATRIX: return "aborted_by_matrix";
    case REASON_ABORTED_BY_COLLAR: return "aborted_by_collar";
    case REASON_PAGE_TIMEOUT_FINAL: return "page_timeout_final";
    case REASON_PAGE_SEND_FAILED: return "page_send_failed";
    case REASON_PAGE_ACK_INVALID: return "page_ack_invalid";
    case REASON_SESSION_NOT_STARTED_AFTER_PAGE_ACK: return "session_not_started_after_page_ack";
    case REASON_DROP_TARGET_MISMATCH: return "drop_target_mismatch";
    case REASON_DROP_SCOPE_MISMATCH: return "drop_scope_mismatch";
    case REASON_DROP_DECRYPT_FAILED: return "drop_decrypt_failed";
    case REASON_DROP_AUTH_FAILED: return "drop_auth_failed";
    case REASON_DROP_REPLAY_BLOCKED: return "drop_replay_blocked";
    case REASON_DROP_DUPLICATE: return "drop_duplicate";
    case REASON_DROP_TTL_EXPIRED: return "drop_ttl_expired";
    case REASON_DROP_UNKNOWN_INNER_TYPE: return "drop_unknown_inner_type";
    case REASON_DROP_INVALID_FRAGMENT: return "drop_invalid_fragment";
    case REASON_DROP_QUEUE_FULL: return "drop_queue_full";
    case REASON_DROP_ROUTE_MISSING: return "drop_route_missing";
    default: return "unknown";
  }
}

static inline const char* rawDropReasonLabel(RawDropReason reason) {
  switch (reason) {
    case RawDropReason::NONE: return "none";
    case RawDropReason::DECRYPT_FAILED: return "decrypt_failed";
    case RawDropReason::AUTH_FAILED: return "auth_failed";
    case RawDropReason::SCOPE_MISMATCH: return "scope_mismatch";
    case RawDropReason::TARGET_MISMATCH: return "target_mismatch";
    case RawDropReason::UNKNOWN_TYPE: return "unknown_type";
    case RawDropReason::INVALID_HEADER: return "invalid_header";
    case RawDropReason::REPLAY_BLOCKED: return "replay_blocked";
    default: return "unknown";
  }
}

}  // namespace rtrv1
