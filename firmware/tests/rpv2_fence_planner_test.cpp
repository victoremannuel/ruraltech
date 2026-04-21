#include <assert.h>
#include <string.h>

#include "../shared/radio_proto_v2_codec.h"
#include "../shared/radio_proto_v2_crc.h"

namespace {
enum class MsgType : uint8_t {
  SET_FENCE = 10,
};

struct LoRaFrameStub {
  uint32_t deviceId = 0;
  uint64_t scopeId = 0;
  MsgType msgType = MsgType::SET_FENCE;
  uint32_t seq = 0;
  uint32_t timestamp = 0;
  uint8_t nonce[12]{};
  uint8_t payloadLen = 0;
  uint8_t payload[128]{};
  uint8_t tag[16]{};
};

static size_t encodePlainLikeGateway(const LoRaFrameStub& f) {
  return 4 + 8 + 1 + 4 + 4 + 12 + 1 + f.payloadLen + 16;
}

static uint16_t exactWireLenForPayload(
    const uint8_t* payload,
    uint8_t payloadLen) {
  LoRaFrameStub tx;
  tx.deviceId = 123;
  tx.scopeId = 0xDEADBEEF00000001ULL;
  tx.payloadLen = payloadLen;
  memcpy(tx.payload, payload, payloadLen);
  const size_t packedLen = encodePlainLikeGateway(tx);
  const size_t cipherLen = packedLen - 16;
  return static_cast<uint16_t>(12 + cipherLen + 16);
}
}  // namespace

int main() {
  rpv2::Header header{};
  header.protocolVersion = rpv2::PROTOCOL_VERSION;
  header.flags = rpv2::FLAG_ACK_REQUIRED | rpv2::FLAG_FROM_MATRIX;
  header.headerLen = sizeof(rpv2::Header);
  header.radioCommandId = 0x1122334455667788ULL;
  header.sessionNonce = 0xA1B2C3D4UL;

  uint8_t frame[128]{};

  header.msgType = rpv2::FENCE_BEGIN;
  rpv2::FenceBeginBody begin{};
  begin.totalPoints = 6;
  begin.totalChunks = 1;
  begin.fenceCrc32 = 123;
  begin.fenceVersion = 1;
  begin.coordEncoding = 1;
  begin.pointStrideBytes = 8;
  const size_t beginLen = rpv2::encodeFrame(header, begin, frame, sizeof(frame));
  assert(beginLen > 0);
  assert(exactWireLenForPayload(frame, static_cast<uint8_t>(beginLen)) <= 128);

  header.msgType = rpv2::FENCE_POINTS;
  header.fragmentIndex = 1;
  header.fragmentTotal = 1;
  rpv2::FencePointsPrefix prefix{};
  prefix.startPointIndex = 0;
  prefix.pointCount = 1;
  rpv2::PointLatLonE7 point{};
  point.latE7 = -167000000;
  point.lonE7 = -492500000;
  const size_t singlePointLen = rpv2::encodePointsFrame(header, prefix, &point, 1, frame, sizeof(frame));
  assert(singlePointLen > 0);
  assert(exactWireLenForPayload(frame, static_cast<uint8_t>(singlePointLen)) <= 128);

  rpv2::PointLatLonE7 points6[6]{};
  for (int i = 0; i < 6; ++i) {
    points6[i].latE7 = -167000000 - (i * 1000);
    points6[i].lonE7 = -492500000 + (i * 1000);
  }
  uint8_t bestFit = 0;
  for (uint8_t count = 1; count <= 6; ++count) {
    prefix.pointCount = count;
    const size_t len = rpv2::encodePointsFrame(header, prefix, points6, count, frame, sizeof(frame));
    assert(len > 0);
    const uint16_t wireLen = exactWireLenForPayload(frame, static_cast<uint8_t>(len));
    if (wireLen <= 128) bestFit = count;
  }
  assert(bestFit >= 1);
  assert(bestFit < 6);
  const uint8_t plannedChunks = static_cast<uint8_t>((6 + bestFit - 1) / bestFit);
  assert(plannedChunks >= 2);

  header.msgType = rpv2::FENCE_COMMIT;
  rpv2::FenceCommitBody commit{};
  commit.totalPoints = 6;
  commit.totalChunks = 2;
  commit.fenceCrc32 = 123;
  commit.stagedCrc32Expected = 123;
  commit.activateMode = 1;
  commit.requireApplyStatus = 1;
  commit.commitToken = 321;
  const size_t commitLen = rpv2::encodeFrame(header, commit, frame, sizeof(frame));
  assert(commitLen > 0);
  assert(exactWireLenForPayload(frame, static_cast<uint8_t>(commitLen)) <= 128);

  return 0;
}
