#pragma once

#include <Arduino.h>

namespace rpv2 {

constexpr uint8_t PROTOCOL_VERSION = 2;
constexpr uint8_t COORD_ENCODING_LATE7_LONE7 = 1;
constexpr uint8_t POINT_STRIDE_BYTES = 8;
constexpr uint16_t MAX_LORA_FRAME_BYTES = 128;
constexpr uint8_t MAX_FENCE_POINTS = 32;
constexpr uint8_t MIN_FENCE_POINTS = 3;
constexpr uint8_t MAX_RETRIES_PER_STAGE = 3;
constexpr uint32_t BEGIN_ACK_TIMEOUT_MS = 6000;
constexpr uint32_t POINTS_ACK_TIMEOUT_MS = 4000;
constexpr uint32_t COMMIT_ACK_TIMEOUT_MS = 6000;
constexpr uint32_t APPLY_STATUS_TIMEOUT_MS = 10000;
constexpr uint32_t INTER_FRAME_GAP_MS = 250;
constexpr uint32_t SESSION_TTL_MS = 120000;
constexpr uint32_t CAPABILITY_STALE_MS = 300000;
constexpr uint8_t REPLAY_WINDOW_SESSIONS = 8;

constexpr uint8_t FLAG_ACK_REQUIRED = 0x01;
constexpr uint8_t FLAG_RETRY = 0x02;
constexpr uint8_t FLAG_FROM_MATRIX = 0x10;
constexpr uint8_t FLAG_FROM_COLLAR = 0x20;

}  // namespace rpv2
