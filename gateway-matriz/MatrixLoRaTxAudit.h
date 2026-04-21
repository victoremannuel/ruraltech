#pragma once

#include <Arduino.h>
#include "LoRaProtocol.h"

enum class MatrixLoRaTxReason : uint8_t {
  Unknown = 0,
  CommandDispatch = 1,
  RtrPage = 2,
  Rpv2Begin = 3,
  Rpv2Points = 4,
  Rpv2Commit = 5,
  ControlAck = 6,
  RelayForwardValidated = 7,
  InvalidAcceptedUplinkEcho = 8,
};

static inline const char* matrixLoRaTxReasonLabel(MatrixLoRaTxReason reason) {
  switch (reason) {
    case MatrixLoRaTxReason::CommandDispatch: return "command_dispatch";
    case MatrixLoRaTxReason::RtrPage: return "rtr_page";
    case MatrixLoRaTxReason::Rpv2Begin: return "rpv2_begin";
    case MatrixLoRaTxReason::Rpv2Points: return "rpv2_points";
    case MatrixLoRaTxReason::Rpv2Commit: return "rpv2_commit";
    case MatrixLoRaTxReason::ControlAck: return "control_ack";
    case MatrixLoRaTxReason::RelayForwardValidated: return "relay_forward_validated";
    case MatrixLoRaTxReason::InvalidAcceptedUplinkEcho: return "invalid_accepted_uplink_echo";
    case MatrixLoRaTxReason::Unknown:
    default: return "unknown";
  }
}

static inline bool isAcceptedUplinkEchoSourceType(MsgType msgType) {
  return msgType == MsgType::TELEMETRY ||
      msgType == MsgType::EVENT ||
      msgType == MsgType::ACK ||
      msgType == MsgType::NACK ||
      msgType == MsgType::RTR_CONTROL;
}

static inline bool shouldAllowMatrixLoRaTx(
    MatrixLoRaTxReason reason,
    const LoRaFrame* sourceUplinkOrNull) {
  (void)reason;
  if (!sourceUplinkOrNull) return true;
  return !isAcceptedUplinkEchoSourceType(sourceUplinkOrNull->msgType);
}

static inline bool isCommandLikeMatrixLoRaTxReason(MatrixLoRaTxReason reason) {
  return reason == MatrixLoRaTxReason::CommandDispatch ||
      reason == MatrixLoRaTxReason::RtrPage ||
      reason == MatrixLoRaTxReason::Rpv2Begin ||
      reason == MatrixLoRaTxReason::Rpv2Points ||
      reason == MatrixLoRaTxReason::Rpv2Commit ||
      reason == MatrixLoRaTxReason::ControlAck;
}
