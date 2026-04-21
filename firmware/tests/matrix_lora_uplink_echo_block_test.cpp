#include <assert.h>

#include "../../gateway-matriz/MatrixLoRaTxAudit.h"

int main() {
  LoRaFrame uplink{};
  uplink.msgType = MsgType::TELEMETRY;
  uplink.seq = 1311000001UL;

  assert(!shouldAllowMatrixLoRaTx(
      MatrixLoRaTxReason::RelayForwardValidated,
      &uplink));
  assert(isAcceptedUplinkEchoSourceType(uplink.msgType));
  return 0;
}
