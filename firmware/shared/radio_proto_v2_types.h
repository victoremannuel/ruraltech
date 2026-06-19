#pragma once

#include <Arduino.h>

namespace rpv2 {

// RuralTech RPv2 is an internal ESP32-to-ESP32 binary protocol.
// On-wire layout is little-endian and every structure below must remain packed.

enum MsgType : uint8_t {
  FENCE_BEGIN = 0x21,
  FENCE_POINTS = 0x22,
  FENCE_COMMIT = 0x23,
  FENCE_ABORT = 0x24,
  FENCE_ACK = 0x25,
  FENCE_NACK = 0x26,
  FENCE_APPLY_STATUS = 0x27,
};

struct __attribute__((packed)) Header {
  uint8_t protocolVersion;
  uint8_t msgType;
  uint8_t flags;
  uint8_t headerLen;
  uint64_t radioCommandId;
  uint32_t sessionNonce;
  uint16_t fragmentIndex;
  uint16_t fragmentTotal;
};

struct __attribute__((packed)) FenceBeginBody {
  uint16_t totalPoints;
  uint16_t totalChunks;
  uint32_t fenceCrc32;
  uint32_t fenceVersion;
  uint8_t coordEncoding;
  uint8_t pointStrideBytes;
  uint16_t reserved;
};

struct __attribute__((packed)) FencePointsPrefix {
  uint16_t startPointIndex;
  uint8_t pointCount;
  uint8_t reserved;
};

struct __attribute__((packed)) PointLatLonE7 {
  int32_t latE7;
  int32_t lonE7;
};

struct __attribute__((packed)) FenceCommitBody {
  uint16_t totalPoints;
  uint16_t totalChunks;
  uint32_t fenceCrc32;
  uint32_t stagedCrc32Expected;
  uint8_t activateMode;
  uint8_t requireApplyStatus;
  uint16_t reserved;
  uint32_t commitToken;
};

struct __attribute__((packed)) FenceAbortBody {
  uint16_t reasonCode;
  uint16_t lastGoodFragment;
  uint32_t detail;
};

struct __attribute__((packed)) AckBody {
  uint8_t ackedMsgType;
  uint8_t statusCode;
  uint16_t ackedFragmentIndex;
  uint16_t nextExpectedFragment;
  uint16_t acceptedPoints;
  uint32_t observedCrc32;
};

struct __attribute__((packed)) NackBody {
  uint8_t nackOfMsgType;
  uint8_t statusCode;
  uint16_t nackFragmentIndex;
  uint16_t reasonCode;
  uint16_t nextExpectedFragment;
  uint32_t detail;
};

struct __attribute__((packed)) ApplyStatusBody {
  uint8_t applyStatus;
  uint8_t reserved;
  uint16_t reasonCode;
  uint32_t activeCrc32;
  uint16_t activePoints;
  uint16_t activeBankId;
};

static_assert(sizeof(Header) == 20, "RPv2 Header size mismatch");
static_assert(sizeof(FenceBeginBody) == 16, "RPv2 FenceBeginBody size mismatch");
static_assert(sizeof(FencePointsPrefix) == 4, "RPv2 FencePointsPrefix size mismatch");
static_assert(sizeof(PointLatLonE7) == 8, "RPv2 PointLatLonE7 size mismatch");
static_assert(sizeof(FenceCommitBody) == 20, "RPv2 FenceCommitBody size mismatch");
static_assert(sizeof(FenceAbortBody) == 8, "RPv2 FenceAbortBody size mismatch");
static_assert(sizeof(AckBody) == 12, "RPv2 AckBody size mismatch");
static_assert(sizeof(NackBody) == 12, "RPv2 NackBody size mismatch");
static_assert(sizeof(ApplyStatusBody) == 12, "RPv2 ApplyStatusBody size mismatch");

}  // namespace rpv2
