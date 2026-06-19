#include <assert.h>

#include "../../gateway-matriz/MatrixLoRaTxAudit.h"

int main() {
  LoRaFrame uplink{};
  uplink.msgType = MsgType::EVENT;
  uplink.seq = 1311000002UL;

  assert(!shouldAllowMatrixLoRaTx(
      MatrixLoRaTxReason::RelayForwardValidated,
      &uplink));
  assert(isAcceptedUplinkEchoSourceType(uplink.msgType));
  return 0;
}
