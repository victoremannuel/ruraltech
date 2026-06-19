#include <assert.h>

#include "../shared/radio_transport_v1_codec.h"
#include "../shared/radio_transport_v1_reason_codes.h"

int main() {
  rtrv1::Header header{};
  header.version = rtrv1::PROTOCOL_VERSION;
  header.trafficClass = rtrv1::TRAFFIC_CLASS_P0;
  header.innerMsgType = rtrv1::RTR_PAGE;
  header.flags = rtrv1::FLAG_ACK_REQUIRED | rtrv1::FLAG_PAGE;
  header.sessionId = 0x1122334455667788ULL;
  header.messageId = 0xA1B2C3D4UL;
  header.sourceId = 0x90010001UL;
  header.finalDestId = 0xC011A001UL;
  header.nextHopId = 0xC011A001UL;
  header.fragmentIndex = 0;
  header.fragmentTotal = 1;
  header.hopCount = 0;
  header.ttl = rtrv1::DEFAULT_TTL;

  rtrv1::PageBody body{};
  body.commandType = 10;
  body.priority = rtrv1::TRAFFIC_CLASS_P1;
  body.estimatedFragments = 7;
  body.sessionTimeoutSec = 600;
  body.wakeLockSec = 600;
  body.routeId = 0x12345678UL;

  uint8_t frame[96]{};
  const size_t len = rtrv1::encodeFrame(header, body, frame, sizeof(frame));
  assert(len == sizeof(rtrv1::Header) + sizeof(rtrv1::PageBody));

  rtrv1::Header decodedHeader{};
  rtrv1::PageBody decodedBody{};
  assert(rtrv1::decodePage(frame, len, &decodedHeader, &decodedBody));
  assert(decodedHeader.sessionId == header.sessionId);
  assert(decodedHeader.messageId == header.messageId);
  assert(decodedBody.estimatedFragments == body.estimatedFragments);
  assert(decodedBody.routeId == body.routeId);

  assert(rtrv1::reasonCodeLabel(rtrv1::REASON_PAGE_TIMEOUT) != nullptr);
  assert(rtrv1::reasonCodeLabel(rtrv1::REASON_DROP_SCOPE_MISMATCH) != nullptr);

  return 0;
}
