#pragma once

#include <Arduino.h>

namespace rtrv1 {

constexpr uint8_t PROTOCOL_VERSION = 1;

constexpr uint8_t TRAFFIC_CLASS_P0 = 0;
constexpr uint8_t TRAFFIC_CLASS_P1 = 1;
constexpr uint8_t TRAFFIC_CLASS_P2 = 2;
constexpr uint8_t TRAFFIC_CLASS_P3 = 3;
constexpr uint8_t TRAFFIC_CLASS_P4 = 4;

constexpr uint16_t MAX_LORA_WIRE_BYTES = 128;
constexpr uint16_t WIRE_BUDGET_BYTES = 120;

constexpr uint32_t DISCOVERY_RX_WINDOW_MS = 1200;
constexpr uint32_t SESSION_WAKE_LOCK_MS = 600000;
constexpr uint32_t IDLE_SESSION_TIMEOUT_MS = 30000;
constexpr uint32_t PAGE_ACK_TIMEOUT_MS = 1500;
constexpr uint32_t LINK_ACK_TIMEOUT_MS = 1500;
constexpr uint32_t APP_ACK_TIMEOUT_MS = 3000;
constexpr uint32_t FAST_PAGE_DEADLINE_MS = 300;
constexpr uint32_t INTER_FRAME_GAP_MS = 80;
constexpr uint32_t RELAY_FORWARD_DELAY_MIN_MS = 30;
constexpr uint32_t RELAY_FORWARD_DELAY_MAX_MS = 80;

constexpr uint8_t MAX_FRAGMENT_RETRIES = 1;
constexpr uint8_t MAX_PAGE_CAMPAIGNS = 2;
constexpr uint8_t MAX_PAGE_ATTEMPTS = MAX_PAGE_CAMPAIGNS;
constexpr uint8_t DEFAULT_TTL = 4;
constexpr uint16_t DEDUP_CACHE_TTL_SEC = 120;
constexpr uint16_t SESSION_CACHE_TTL_SEC = 600;

constexpr uint8_t FLAG_ACK_REQUIRED = 1 << 0;
constexpr uint8_t FLAG_APP_ACK_REQUIRED = 1 << 1;
constexpr uint8_t FLAG_RELAY_ALLOWED = 1 << 2;
constexpr uint8_t FLAG_RETRY = 1 << 3;
constexpr uint8_t FLAG_FINAL = 1 << 4;
constexpr uint8_t FLAG_PAGE = 1 << 5;
constexpr uint8_t FLAG_WAKE_LOCK = 1 << 6;

}  // namespace rtrv1
