#pragma once

#include <Arduino.h>

namespace rtrv1 {

enum InnerMsgType : uint8_t {
  RTR_PAGE = 0x01,
  RTR_PAGE_ACK = 0x02,
  RTR_LINK_ACK = 0x03,
  RTR_LINK_NACK = 0x04,
  RTR_ABORT = 0x05,
  RTR_ROUTE_STATUS = 0x06,
  RTR_SESSION_STATUS = 0x07,

  RTR_SESSION_BEGIN = 0x10,
  RTR_SESSION_DATA = 0x11,
  RTR_SESSION_COMMIT = 0x12,
  RTR_APP_ACK = 0x13,

  RTR_CRITICAL_EVENT = 0x20,

  RTR_TELEMETRY_POSITION = 0x30,
  RTR_TELEMETRY_HEALTH = 0x31,

  RTR_HEARTBEAT = 0x40,
  RTR_CAPABILITIES = 0x41,
  RTR_TIME_SYNC = 0x42,
};

struct __attribute__((packed)) Header {
  uint8_t version;
  uint8_t trafficClass;
  uint8_t innerMsgType;
  uint8_t flags;
  uint64_t sessionId;
  uint32_t messageId;
  uint32_t sourceId;
  uint32_t finalDestId;
  uint32_t nextHopId;
  uint16_t fragmentIndex;
  uint16_t fragmentTotal;
  uint8_t hopCount;
  uint8_t ttl;
};

struct __attribute__((packed)) PageBody {
  uint8_t commandType;
  uint8_t priority;
  uint16_t estimatedFragments;
  uint32_t sessionTimeoutSec;
  uint32_t wakeLockSec;
  uint32_t routeId;
};

struct __attribute__((packed)) PageAckBody {
  uint8_t accepted;
  uint8_t sessionModeActive;
  uint16_t suggestedRxWindowMs;
  uint32_t wakeLockUntilSec;
};

struct __attribute__((packed)) SessionBeginBody {
  uint8_t commandType;
  uint8_t payloadCodec;
  uint16_t totalFragments;
  uint32_t totalPlainBytes;
  uint32_t payloadCrc32;
  uint32_t commitToken;
};

struct __attribute__((packed)) SessionDataPrefix {
  uint16_t dataBytes;
  uint16_t reserved;
};

struct __attribute__((packed)) SessionCommitBody {
  uint32_t totalPlainBytes;
  uint16_t totalFragments;
  uint16_t reserved;
  uint32_t payloadCrc32;
  uint32_t commitToken;
};

struct __attribute__((packed)) LinkAckBody {
  uint8_t ackedInnerType;
  uint8_t accepted;
  uint16_t ackedFragmentIndex;
  uint16_t nextExpectedFragment;
  uint16_t reserved;
  uint32_t observedCrc32;
};

struct __attribute__((packed)) LinkNackBody {
  uint8_t nackOfInnerType;
  uint8_t reserved0;
  uint16_t nackFragmentIndex;
  uint16_t nextExpectedFragment;
  uint16_t reasonCode;
  uint32_t detail;
};

struct __attribute__((packed)) AppAckBody {
  uint8_t applied;
  uint8_t statusClass;
  uint16_t reasonCode;
  uint32_t activeCrc32;
  uint16_t activePoints;
  uint16_t extra;
};

struct __attribute__((packed)) TelemetryPositionBody {
  int32_t latE7;
  int32_t lonE7;
  int16_t speedDeciKmph;
  uint16_t hdopCenti;
  uint8_t sats;
  uint8_t mode;
  uint16_t flags;
};

static_assert(sizeof(Header) == 34, "RTRv1 Header size mismatch");
static_assert(sizeof(PageBody) == 16, "RTRv1 PageBody size mismatch");
static_assert(sizeof(PageAckBody) == 8, "RTRv1 PageAckBody size mismatch");
static_assert(sizeof(SessionBeginBody) == 16, "RTRv1 SessionBeginBody size mismatch");
static_assert(sizeof(SessionDataPrefix) == 4, "RTRv1 SessionDataPrefix size mismatch");
static_assert(sizeof(SessionCommitBody) == 16, "RTRv1 SessionCommitBody size mismatch");
static_assert(sizeof(LinkAckBody) == 12, "RTRv1 LinkAckBody size mismatch");
static_assert(sizeof(LinkNackBody) == 12, "RTRv1 LinkNackBody size mismatch");
static_assert(sizeof(AppAckBody) == 12, "RTRv1 AppAckBody size mismatch");
static_assert(sizeof(TelemetryPositionBody) == 16, "RTRv1 TelemetryPositionBody size mismatch");

}  // namespace rtrv1
