#include <assert.h>
#include <string.h>

#include "../shared/radio_proto_v2_codec.h"
#include "../shared/radio_proto_v2_reason_codes.h"

int main() {
  rpv2::Header header{};
  header.protocolVersion = rpv2::PROTOCOL_VERSION;
  header.msgType = rpv2::FENCE_BEGIN;
  header.flags = rpv2::FLAG_ACK_REQUIRED | rpv2::FLAG_FROM_MATRIX;
  header.headerLen = sizeof(rpv2::Header);
  header.radioCommandId = 0x1122334455667788ULL;
  header.sessionNonce = 0xA1B2C3D4UL;
  header.fragmentIndex = 0;
  header.fragmentTotal = 2;

  rpv2::FenceBeginBody begin{};
  begin.totalPoints = 6;
  begin.totalChunks = 2;
  begin.fenceCrc32 = 0x89ABCDEFUL;
  begin.fenceVersion = 7;
  begin.coordEncoding = 1;
  begin.pointStrideBytes = 8;

  uint8_t frame[64]{};
  const size_t beginLen = rpv2::encodeFrame(header, begin, frame, sizeof(frame));
  assert(beginLen == sizeof(rpv2::Header) + sizeof(rpv2::FenceBeginBody));
  rpv2::Header decodedHeader{};
  rpv2::FenceBeginBody decodedBegin{};
  assert(rpv2::decodeFenceBegin(frame, beginLen, &decodedHeader, &decodedBegin));
  assert(decodedHeader.radioCommandId == header.radioCommandId);
  assert(decodedBegin.fenceCrc32 == begin.fenceCrc32);

  header.msgType = rpv2::FENCE_POINTS;
  header.fragmentIndex = 1;
  rpv2::FencePointsPrefix prefix{};
  prefix.startPointIndex = 0;
  prefix.pointCount = 2;
  rpv2::PointLatLonE7 points[2]{};
  points[0].latE7 = -167000000;
  points[0].lonE7 = -492500000;
  points[1].latE7 = -167005000;
  points[1].lonE7 = -492495000;
  const size_t pointsLen = rpv2::encodePointsFrame(
      header, prefix, points, 2, frame, sizeof(frame));
  const rpv2::PointLatLonE7* decodedPoints = nullptr;
  rpv2::FencePointsPrefix decodedPrefix{};
  assert(rpv2::decodeFencePoints(frame, pointsLen, &decodedHeader, &decodedPrefix, &decodedPoints));
  assert(decodedPrefix.pointCount == 2);
  assert(decodedPoints[1].lonE7 == points[1].lonE7);

  header.msgType = rpv2::FENCE_COMMIT;
  rpv2::FenceCommitBody commit{};
  commit.totalPoints = 6;
  commit.totalChunks = 2;
  commit.fenceCrc32 = 0x89ABCDEFUL;
  commit.stagedCrc32Expected = 0x89ABCDEFUL;
  commit.activateMode = 1;
  commit.requireApplyStatus = 1;
  commit.commitToken = 0x28191E3BUL;
  const size_t commitLen = rpv2::encodeFrame(header, commit, frame, sizeof(frame));
  rpv2::FenceCommitBody decodedCommit{};
  assert(rpv2::decodeFixedBodyFrame(rpv2::FENCE_COMMIT, frame, commitLen, &decodedHeader, &decodedCommit));
  assert(decodedCommit.commitToken == commit.commitToken);

  header.msgType = rpv2::FENCE_ACK;
  rpv2::AckBody ack{};
  ack.ackedMsgType = rpv2::FENCE_POINTS;
  ack.statusCode = 0;
  ack.ackedFragmentIndex = 1;
  ack.nextExpectedFragment = 2;
  ack.acceptedPoints = 2;
  ack.observedCrc32 = 1234;
  const size_t ackLen = rpv2::encodeFrame(header, ack, frame, sizeof(frame));
  rpv2::AckBody decodedAck{};
  assert(rpv2::decodeFixedBodyFrame(rpv2::FENCE_ACK, frame, ackLen, &decodedHeader, &decodedAck));
  assert(decodedAck.acceptedPoints == 2);

  header.msgType = rpv2::FENCE_NACK;
  rpv2::NackBody nack{};
  nack.nackOfMsgType = rpv2::FENCE_POINTS;
  nack.statusCode = 1;
  nack.nackFragmentIndex = 2;
  nack.reasonCode = rpv2::REASON_POINTS_OUT_OF_ORDER;
  nack.nextExpectedFragment = 2;
  nack.detail = 99;
  const size_t nackLen = rpv2::encodeFrame(header, nack, frame, sizeof(frame));
  rpv2::NackBody decodedNack{};
  assert(rpv2::decodeFixedBodyFrame(rpv2::FENCE_NACK, frame, nackLen, &decodedHeader, &decodedNack));
  assert(decodedNack.reasonCode == rpv2::REASON_POINTS_OUT_OF_ORDER);

  header.msgType = rpv2::FENCE_APPLY_STATUS;
  rpv2::ApplyStatusBody apply{};
  apply.applyStatus = 1;
  apply.reasonCode = rpv2::REASON_NONE;
  apply.activeCrc32 = 0x89ABCDEFUL;
  apply.activePoints = 6;
  apply.activeBankId = 1;
  const size_t applyLen = rpv2::encodeFrame(header, apply, frame, sizeof(frame));
  rpv2::ApplyStatusBody decodedApply{};
  assert(rpv2::decodeFixedBodyFrame(rpv2::FENCE_APPLY_STATUS, frame, applyLen, &decodedHeader, &decodedApply));
  assert(decodedApply.activePoints == 6);

  return 0;
}
