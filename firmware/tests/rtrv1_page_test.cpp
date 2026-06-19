#include <assert.h>

#include "../shared/radio_transport_v1_codec.h"
#include "../shared/radio_transport_v1_session_id.h"

int main() {
  const uint64_t sessionA =
      rtrv1::makeSessionId(0x0102030405060708ULL, 0xC011A001UL, 0x11112222UL);
  const uint64_t sessionB =
      rtrv1::makeSessionId(0x0102030405060708ULL, 0xC011A001UL, 0x11112222UL);
  const uint64_t sessionC =
      rtrv1::makeSessionId(0x0102030405060708ULL, 0xC011A002UL, 0x11112222UL);

  assert(sessionA == sessionB);
  assert(sessionA != sessionC);

  rtrv1::Header header{};
  header.version = rtrv1::PROTOCOL_VERSION;
  header.trafficClass = rtrv1::TRAFFIC_CLASS_P0;
  header.innerMsgType = rtrv1::RTR_PAGE_ACK;
  header.flags = rtrv1::FLAG_FINAL | rtrv1::FLAG_WAKE_LOCK;
  header.sessionId = sessionA;
  header.messageId = 77;
  header.sourceId = 0xC011A001UL;
  header.finalDestId = 0x90010001UL;
  header.nextHopId = 0x90010001UL;
  header.fragmentIndex = 0;
  header.fragmentTotal = 1;
  header.hopCount = 0;
  header.ttl = rtrv1::DEFAULT_TTL;

  rtrv1::PageAckBody ack{};
  ack.accepted = 1;
  ack.sessionModeActive = 1;
  ack.suggestedRxWindowMs = rtrv1::DISCOVERY_RX_WINDOW_MS;
  ack.wakeLockUntilSec = 600;

  uint8_t frame[96]{};
  const size_t len = rtrv1::encodeFrame(header, ack, frame, sizeof(frame));
  assert(len == sizeof(rtrv1::Header) + sizeof(rtrv1::PageAckBody));

  rtrv1::Header decodedHeader{};
  rtrv1::PageAckBody decodedAck{};
  assert(rtrv1::decodePageAck(frame, len, &decodedHeader, &decodedAck));
  assert(decodedHeader.sessionId == sessionA);
  assert(decodedAck.accepted == 1);
  assert(decodedAck.sessionModeActive == 1);
  assert(decodedAck.suggestedRxWindowMs == rtrv1::DISCOVERY_RX_WINDOW_MS);

  return 0;
}
